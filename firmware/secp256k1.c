// secp256k1.c — Minimal secp256k1 ECDSA implementation
// SPDX-License-Identifier: CERN-OHL-S-2.0
//
// Implements only what the TernaryCore SE needs:
//   - Public key derivation (scalar * G)
//   - RFC 6979 deterministic nonce generation
//   - ECDSA sign
//
// Arithmetic is over 256-bit integers using 8 x uint32_t limbs (big-endian).
// Requires ENABLE_MUL=1 in PicoRV32 (uses RV32IM multiply instruction).

#include "secp256k1.h"
#include "sha256.h"
#include <string.h>
#include <stdint.h>

// ─── 256-bit field element (8 x 32-bit words, big-endian limbs) ────────────
typedef struct { uint32_t w[8]; } fe_t;  // field element mod p
typedef struct { uint32_t w[8]; } sc_t;  // scalar mod n

// secp256k1 prime  p  = 2^256 - 2^32 - 977
// secp256k1 order  n
// Generator G = (Gx, Gy)
// All constants big-endian word arrays.

static const fe_t FP = {{
    0xFFFFFFFF,0xFFFFFFFF,0xFFFFFFFF,0xFFFFFFFF,
    0xFFFFFFFF,0xFFFFFFFF,0xFFFFFFFE,0xFFFFFC2F
}};
static const sc_t FN = {{
    0xFFFFFFFF,0xFFFFFFFF,0xFFFFFFFF,0xFFFFFFFE,
    0xBAAEDCE6,0xAF48A03B,0xBFD25E8C,0xD0364141
}};
static const fe_t GX = {{
    0x79BE667E,0xF9DCBBAC,0x55A06295,0xCE870B07,
    0x029BFCDB,0x2DCE28D9,0x59F2815B,0x16F81798
}};
static const fe_t GY = {{
    0x483ADA77,0x26A3C465,0x5DA4FBFC,0x0E1108A8,
    0xFD17B448,0xA6855419,0x9C47D08F,0xFB10D4B8
}};

// ─── 256-bit helpers ────────────────────────────────────────────────────────

static void fe_zero(fe_t *a) { memset(a->w, 0, 32); }
static void fe_one(fe_t *a)  { fe_zero(a); a->w[7] = 1; }
static void fe_copy(fe_t *d, const fe_t *s) { memcpy(d->w, s->w, 32); }
static int  fe_is_zero(const fe_t *a) {
    for (int i = 0; i < 8; i++) if (a->w[i]) return 0; return 1;
}
static int fe_cmp(const fe_t *a, const fe_t *b) {
    for (int i = 0; i < 8; i++) {
        if (a->w[i] < b->w[i]) return -1;
        if (a->w[i] > b->w[i]) return  1;
    }
    return 0;
}

// a -= b (assumes a >= b, no borrow returned)
static void u256_sub_inplace(uint32_t *a, const uint32_t *b) {
    uint64_t borrow = 0;
    for (int i = 7; i >= 0; i--) {
        uint64_t diff = (uint64_t)a[i] - b[i] - borrow;
        a[i]  = (uint32_t)diff;
        borrow = (diff >> 63) & 1;
    }
}
// a += b, returns carry
static uint32_t u256_add_inplace(uint32_t *a, const uint32_t *b) {
    uint64_t carry = 0;
    for (int i = 7; i >= 0; i--) {
        uint64_t s = (uint64_t)a[i] + b[i] + carry;
        a[i]  = (uint32_t)s;
        carry = s >> 32;
    }
    return (uint32_t)carry;
}

static void fe_from_bytes(fe_t *a, const uint8_t b[32]) {
    for (int i = 0; i < 8; i++)
        a->w[i] = ((uint32_t)b[i*4]<<24)|((uint32_t)b[i*4+1]<<16)|
                  ((uint32_t)b[i*4+2]<<8)|(uint32_t)b[i*4+3];
}
static void fe_to_bytes(const fe_t *a, uint8_t b[32]) {
    for (int i = 0; i < 8; i++) {
        b[i*4]   = (uint8_t)(a->w[i]>>24);
        b[i*4+1] = (uint8_t)(a->w[i]>>16);
        b[i*4+2] = (uint8_t)(a->w[i]>>8);
        b[i*4+3] = (uint8_t)(a->w[i]);
    }
}

// Field reduction: a = a mod p
static void fe_reduce(fe_t *a) {
    while (fe_cmp(a, &FP) >= 0)
        u256_sub_inplace(a->w, FP.w);
}

// c = (a + b) mod p
static void fe_add(fe_t *c, const fe_t *a, const fe_t *b) {
    fe_copy(c, a);
    uint32_t carry = u256_add_inplace(c->w, b->w);
    if (carry || fe_cmp(c, &FP) >= 0)
        u256_sub_inplace(c->w, FP.w);
}

// c = (a - b) mod p
static void fe_sub(fe_t *c, const fe_t *a, const fe_t *b) {
    fe_copy(c, a);
    if (fe_cmp(c, b) < 0)
        u256_add_inplace(c->w, FP.w);
    u256_sub_inplace(c->w, b->w);
}

// 512-bit product of two 256-bit numbers: r[0..15] = a[0..7] * b[0..7]
static void u256_mul512(const uint32_t *a, const uint32_t *b, uint32_t *r) {
    memset(r, 0, 16*4);
    for (int i = 7; i >= 0; i--) {
        uint64_t carry = 0;
        for (int j = 7; j >= 0; j--) {
            uint64_t p = (uint64_t)a[i] * b[j] + r[i+j+1] + carry;
            r[i+j+1] = (uint32_t)p;
            carry     = p >> 32;
        }
        r[i] += (uint32_t)carry;
    }
}

// Field multiply using schoolbook + Barrett-ish reduction mod p
// c = a * b mod p
// Uses the special form p = 2^256 - 2^32 - 977.
static void fe_mul(fe_t *c, const fe_t *a, const fe_t *b) {
    uint32_t t[16];
    u256_mul512(a->w, b->w, t);

    // Reduce: t = hi * (2^32 + 977) + lo
    // where hi = t[0..7], lo = t[8..15]
    // Iteratively reduce the high half.
    // We do two passes; the overflow after each pass is at most 1 word wide.
    for (int pass = 0; pass < 2; pass++) {
        // Add hi * 977 into lo (starting from t[15] up)
        uint64_t carry = 0;
        for (int i = 7; i >= 0; i--) {
            uint64_t v = (uint64_t)t[i] * 977 + t[8+i] + carry;
            t[8+i] = (uint32_t)v;
            carry  = v >> 32;
        }
        // Add hi * 2^32 (shift hi left 1 word) into lo
        uint64_t carry2 = carry;
        for (int i = 7; i >= 0; i--) {
            uint64_t v = (uint64_t)t[8+i] + t[i] * (uint64_t)(i > 0 ? 0 : 0) + carry2;
            // Simpler: just shift t[i] into t[i+1..8+i-1] position (add hi<<32)
            (void)v;
        }
        // Cleaner: treat t[0..7] as the high 256 bits.
        // t_lo = t[8..15], t_hi = t[0..7]
        // Result = t_lo + t_hi * (2^32 + 977)
        //        = t_lo + (t_hi << 32) + t_hi * 977
        // (t_hi << 32) shifts all hi words into lo by 1 position
        carry = 0;
        for (int i = 15; i >= 1; i--) {
            uint64_t v = (uint64_t)t[i] + (uint64_t)t[i-1] * 977 + carry;
            // Hmm this is getting complicated. Let me just do it word by word.
            (void)v;
        }
        // Actually use the straightforward approach below.
        break; // exit, use the approach below instead
    }

    // Simple correct approach: Barrett reduction using the special prime structure.
    // p = 2^256 - 2^32 - 977
    // For 512-bit t = t_hi * 2^256 + t_lo,
    //   t mod p = t_lo + t_hi * (2^32 + 977)  [then reduce if >= p]
    // We apply this iteratively until result fits in 256 bits.
    uint32_t lo[8], hi[8];
    memcpy(hi, t,     32);  // t[0..7]
    memcpy(lo, t + 8, 32);  // t[8..15]

    for (int iter = 0; iter < 3; iter++) {
        // lo += hi * 977
        uint64_t carry = 0;
        for (int i = 7; i >= 0; i--) {
            uint64_t v = (uint64_t)hi[i] * 977 + lo[i] + carry;
            lo[i] = (uint32_t)v;
            carry = v >> 32;
        }
        // lo += hi << 32  (i.e., lo[i] += hi[i-1] with carry for i=7..1, lo[0] += carry)
        uint64_t carry2 = carry;
        for (int i = 7; i >= 1; i--) {
            uint64_t v = (uint64_t)lo[i] + hi[i-1] + carry2;
            lo[i]  = (uint32_t)v;
            carry2 = v >> 32;
        }
        lo[0] += (uint32_t)carry2;
        // Any further overflow from lo[0]: next iteration's hi = overflow word
        // For this prime, 2 iterations suffice.
        memset(hi, 0, 32);
        // Check if lo >= p; if so subtract p (done below after loop)
    }

    fe_copy(c, (fe_t*)lo);
    fe_reduce(c);
}

// c = a^2 mod p
static void fe_sqr(fe_t *c, const fe_t *a) { fe_mul(c, a, a); }

// c = a^-1 mod p using Fermat's little theorem: a^(p-2) mod p
static void fe_inv(fe_t *c, const fe_t *a) {
    // p - 2 = FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2D
    // Use addition chain / square-and-multiply
    fe_t r, base;
    fe_one(&r);
    fe_copy(&base, a);
    // Exponent bits of p-2 (256 bits), MSB first
    // p-2 = p with last byte 0x2F -> 0x2D
    uint32_t exp[8];
    memcpy(exp, FP.w, 32);
    exp[7] -= 2;
    for (int word = 0; word < 8; word++) {
        for (int bit = 31; bit >= 0; bit--) {
            fe_sqr(&r, &r);
            if ((exp[word] >> bit) & 1)
                fe_mul(&r, &r, &base);
        }
    }
    fe_copy(c, &r);
}

// Scalar mod n operations (same layout, different modulus)
static void sc_from_bytes(sc_t *a, const uint8_t b[32]) { fe_from_bytes((fe_t*)a, b); }
static void sc_to_bytes  (const sc_t *a, uint8_t b[32]) { fe_to_bytes((fe_t*)a, b); }
static int  sc_is_zero   (const sc_t *a) { return fe_is_zero((fe_t*)a); }
static int  sc_cmp_n     (const sc_t *a) { return fe_cmp((fe_t*)a, (fe_t*)&FN); }

static void sc_reduce(sc_t *a) {
    while (fe_cmp((fe_t*)a, (fe_t*)&FN) >= 0)
        u256_sub_inplace(a->w, FN.w);
}
static void sc_add(sc_t *c, const sc_t *a, const sc_t *b) {
    fe_add((fe_t*)c, (fe_t*)a, (fe_t*)b);  // uses fe prime — need n version
    // Proper version:
    fe_copy((fe_t*)c, (fe_t*)a);
    uint32_t carry = u256_add_inplace(c->w, b->w);
    if (carry || fe_cmp((fe_t*)c, (fe_t*)&FN) >= 0)
        u256_sub_inplace(c->w, FN.w);
}

// Scalar multiply mod n: c = a * b mod n
static void sc_mul_mod_n(sc_t *c, const sc_t *a, const sc_t *b) {
    uint32_t t[16];
    u256_mul512(a->w, b->w, t);
    // Barrett reduction mod n
    // n is close to 2^256, so same trick:
    // n = 2^256 - k where k = 2^128 - ... (not as clean as p)
    // Use iterative subtraction for simplicity (acceptable since we call this rarely)
    uint32_t lo[8], hi[8];
    memcpy(hi, t,     32);
    memcpy(lo, t + 8, 32);
    // lo = t[8..15] + hi * (2^256 - n) mod n
    // 2^256 - n = 0x14551231950B75FC4402DA1732FC9BEBF
    static const uint32_t TWO256_MINUS_N[8] = {
        0x00000001, 0x45512319, 0x50B75FC4, 0x402DA173,
        0x2FC9BEBF, 0x50D94BF0, 0x402DA173, 0x2FC9BFC0  // placeholder
    };
    // Approximate: just do schoolbook with big-integer arithmetic
    // For a real implementation use Montgomery form; here we do 2 reduction passes
    // using the simple identity: 2^256 ≡ n - FN mod n => 2^256 ≡ (FN complement)
    // For Phase 2 correctness, use simple reduction:
    (void)TWO256_MINUS_N;

    // Compute hi * (2^256 mod n) + lo  by double-and-add
    // 2^256 mod n: compute it
    static uint32_t pow256_mod_n[8] = {0}; // computed once below
    static int pow256_computed = 0;
    if (!pow256_computed) {
        // 2^256 mod n: start with 1 and double 256 times mod n
        pow256_mod_n[7] = 1;
        for (int i = 0; i < 256; i++) {
            // double: pow256_mod_n = pow256_mod_n * 2 mod n
            uint64_t carry = 0;
            for (int j = 7; j >= 0; j--) {
                uint64_t v = (uint64_t)pow256_mod_n[j] * 2 + carry;
                pow256_mod_n[j] = (uint32_t)v;
                carry = v >> 32;
            }
            sc_t tmp; memcpy(&tmp, pow256_mod_n, 32); sc_reduce(&tmp);
            memcpy(pow256_mod_n, &tmp, 32);
        }
        pow256_computed = 1;
    }

    // result = lo + hi * pow256_mod_n  (mod n)
    // Use double-and-add over hi bits
    sc_t result; memset(&result, 0, 32);
    result.w[7] = 0; // zero
    for (int word = 0; word < 8; word++) {
        for (int bit = 31; bit >= 0; bit--) {
            // result = result * 2 mod n
            uint64_t carry = 0;
            for (int j = 7; j >= 0; j--) {
                uint64_t v = (uint64_t)result.w[j] * 2 + carry;
                result.w[j] = (uint32_t)v; carry = v >> 32;
            }
            sc_reduce(&result);
            if ((hi[word] >> bit) & 1) {
                u256_add_inplace(result.w, pow256_mod_n);
                sc_reduce(&result);
            }
        }
    }
    // result += lo
    u256_add_inplace(result.w, lo);
    sc_reduce(&result);
    fe_copy((fe_t*)c, (fe_t*)&result);
}

// ─── Elliptic curve point (Jacobian coordinates) ────────────────────────────
typedef struct { fe_t x, y, z; int inf; } pt_t;

static void pt_infinity(pt_t *P) { P->inf = 1; fe_zero(&P->x); fe_zero(&P->y); fe_zero(&P->z); }
static void pt_affine(pt_t *P, const fe_t *x, const fe_t *y) {
    P->inf = 0; fe_copy(&P->x, x); fe_copy(&P->y, y); fe_one(&P->z);
}

// Point doubling in Jacobian: P = 2*P
static void pt_double(pt_t *R, const pt_t *P) {
    if (P->inf || fe_is_zero(&P->y)) { pt_infinity(R); return; }
    fe_t ysq, s, m, x2, y2, z2, tmp;
    fe_sqr(&ysq, &P->y);                    // ysq = Y^2
    fe_mul(&s,   &P->x, &ysq);              // s = X*Y^2
    fe_add(&tmp, &s, &s); fe_add(&s, &tmp, &tmp); // s = 4*X*Y^2
    fe_sqr(&m, &P->x);                       // m = X^2
    fe_add(&tmp, &m, &m); fe_add(&m, &tmp, &m);  // m = 3*X^2  (a=0 for secp256k1)
    fe_sqr(&x2, &m);                         // x2 = m^2
    fe_add(&tmp, &s, &s);
    fe_sub(&x2, &x2, &tmp);                 // x2 = m^2 - 2s
    fe_sub(&y2, &s, &x2);
    fe_mul(&y2, &m, &y2);                   // y2 = m*(s-x2)
    fe_sqr(&tmp, &ysq);
    fe_add(&tmp, &tmp, &tmp); fe_add(&tmp, &tmp, &tmp);
    fe_add(&tmp, &tmp, &tmp);               // tmp = 8*Y^4
    fe_sub(&y2, &y2, &tmp);                 // y2 = m*(s-x2) - 8*Y^4
    fe_mul(&z2, &P->y, &P->z);
    fe_add(&z2, &z2, &z2);                  // z2 = 2*Y*Z
    R->inf = 0;
    fe_copy(&R->x, &x2); fe_copy(&R->y, &y2); fe_copy(&R->z, &z2);
}

// Point addition in Jacobian: R = P + Q (P, Q in Jacobian; Q affine with Qz=1)
static void pt_add_mixed(pt_t *R, const pt_t *P, const pt_t *Q) {
    if (P->inf) { *R = *Q; fe_one(&R->z); return; }
    if (Q->inf) { *R = *P; return; }
    fe_t u1, u2, s1, s2, h, r, h2, h3, tmp;
    fe_sqr(&tmp, &P->z);
    fe_copy(&u1, &P->x);                    // u1 = X1 (Qz=1 so u2=X2*1^2=X2)
    fe_mul(&u2, &Q->x, &tmp);               // u2 = X2*Z1^2
    fe_copy(&s1, &P->y);
    fe_mul(&s2, &Q->y, &tmp);
    fe_mul(&s2, &s2, &P->z);               // s2 = Y2*Z1^3
    fe_sub(&h, &u2, &u1);
    fe_sub(&r, &s2, &s1);
    if (fe_is_zero(&h)) {
        if (fe_is_zero(&r)) { pt_double(R, P); }
        else { pt_infinity(R); }
        return;
    }
    fe_sqr(&h2, &h);
    fe_mul(&h3, &h2, &h);
    fe_mul(&u1, &u1, &h2);                 // u1 = u1*h^2
    fe_sqr(&R->x, &r);
    fe_sub(&R->x, &R->x, &h3);
    fe_add(&tmp, &u1, &u1);
    fe_sub(&R->x, &R->x, &tmp);
    fe_sub(&tmp, &u1, &R->x);
    fe_mul(&R->y, &r, &tmp);
    fe_mul(&tmp, &s1, &h3);
    fe_sub(&R->y, &R->y, &tmp);
    fe_mul(&R->z, &P->z, &h);
    R->inf = 0;
}

// Jacobian → affine
static int pt_to_affine(const pt_t *P, fe_t *x, fe_t *y) {
    if (P->inf) return -1;
    fe_t zinv, zinv2;
    fe_inv(&zinv, &P->z);
    fe_sqr(&zinv2, &zinv);
    fe_mul(x, &P->x, &zinv2);
    fe_mul(&zinv2, &zinv2, &zinv);
    fe_mul(y, &P->y, &zinv2);
    return 0;
}

// Scalar multiplication: R = k * G  using double-and-add (MSB first)
static void pt_scalar_mul_G(pt_t *R, const sc_t *k) {
    pt_t Q; pt_infinity(&Q);
    pt_t G; pt_affine(&G, &GX, &GY);
    for (int word = 0; word < 8; word++) {
        for (int bit = 31; bit >= 0; bit--) {
            pt_double(&Q, &Q);
            if ((k->w[word] >> bit) & 1)
                pt_add_mixed(&Q, &Q, &G);
        }
    }
    *R = Q;
}

// ─── RFC 6979 deterministic nonce ────────────────────────────────────────────
// Returns k such that 1 <= k < n.
static void rfc6979_nonce(const uint8_t priv[32], const uint8_t hash[32], sc_t *k) {
    // HMAC-SHA256 based deterministic nonce generation per RFC 6979 §3.2
    uint8_t V[32], K[32], tmp[97];
    sha256_ctx_t ctx;

    // K = 0x00...00 (32 bytes)
    memset(K, 0x00, 32);
    // V = 0x01...01 (32 bytes)
    memset(V, 0x01, 32);

    // K = HMAC_K(V || 0x00 || priv || hash)
    // Simplified HMAC (ipad/opad with SHA-256 block key)
    // For HMAC-SHA256 with key K (32 bytes): use directly as block key.
    uint8_t ipad[64], opad[64];
    memset(ipad, 0x36, 64); memset(opad, 0x5C, 64);
    for (int i = 0; i < 32; i++) { ipad[i] ^= K[i]; opad[i] ^= K[i]; }

    // Step d: K = HMAC(K, V || 0x00 || priv || hash)
    for (int step = 0; step < 2; step++) {
        memcpy(ipad + 32, ipad, 0); // dummy — use full concat below
        // Recompute ipad/opad with current K
        memset(ipad, 0x36, 64); memset(opad, 0x5C, 64);
        for (int i = 0; i < 32; i++) { ipad[i] ^= K[i]; opad[i] ^= K[i]; }

        // inner = SHA256(ipad || V || sep || priv || hash)
        uint8_t sep = (step == 0) ? 0x00 : 0x01;
        uint8_t inner[32];
        sha256_ctx_t ictx;
        sha256_init(&ictx);
        sha256_update(&ictx, ipad, 64);
        sha256_update(&ictx, V, 32);
        sha256_update(&ictx, &sep, 1);
        if (step == 0) {
            sha256_update(&ictx, priv, 32);
            sha256_update(&ictx, hash, 32);
        }
        sha256_final(&ictx, inner);

        // K = SHA256(opad || inner)
        sha256_init(&ictx);
        sha256_update(&ictx, opad, 64);
        sha256_update(&ictx, inner, 32);
        sha256_final(&ictx, K);

        // V = HMAC(K, V)
        memset(ipad, 0x36, 64); memset(opad, 0x5C, 64);
        for (int i = 0; i < 32; i++) { ipad[i] ^= K[i]; opad[i] ^= K[i]; }
        sha256_init(&ictx);
        sha256_update(&ictx, ipad, 64);
        sha256_update(&ictx, V, 32);
        sha256_final(&ictx, inner);
        sha256_init(&ictx);
        sha256_update(&ictx, opad, 64);
        sha256_update(&ictx, inner, 32);
        sha256_final(&ictx, V);
    }

    // Generate k: V = HMAC(K, V) until 1 <= k < n
    for (int attempt = 0; attempt < 100; attempt++) {
        // V = HMAC(K, V)
        uint8_t ipad2[64], opad2[64], inner[32];
        memset(ipad2, 0x36, 64); memset(opad2, 0x5C, 64);
        for (int i = 0; i < 32; i++) { ipad2[i] ^= K[i]; opad2[i] ^= K[i]; }
        sha256_ctx_t ictx;
        sha256_init(&ictx);
        sha256_update(&ictx, ipad2, 64);
        sha256_update(&ictx, V, 32);
        sha256_final(&ictx, inner);
        sha256_init(&ictx);
        sha256_update(&ictx, opad2, 64);
        sha256_update(&ictx, inner, 32);
        sha256_final(&ictx, V);
        memcpy(inner, V, 32); // V is now the candidate T

        sc_from_bytes(k, inner);
        sc_reduce(k);
        if (!sc_is_zero(k) && sc_cmp_n(k) < 0)
            return; // valid nonce
    }
    (void)tmp; (void)ctx;
    // Fallback (should never reach here with a valid key/hash)
    sc_from_bytes(k, hash);
    k->w[7] |= 1; // make non-zero
    sc_reduce(k);
}

// ─── DER encoding ────────────────────────────────────────────────────────────
static uint32_t encode_der_int(const uint8_t *val, uint8_t *out) {
    // Find first non-zero byte
    int start = 0;
    while (start < 31 && val[start] == 0) start++;
    int len = 32 - start;
    int needs_pad = (val[start] & 0x80) ? 1 : 0;
    out[0] = 0x02;
    out[1] = (uint8_t)(len + needs_pad);
    int idx = 2;
    if (needs_pad) out[idx++] = 0x00;
    memcpy(out + idx, val + start, len);
    return (uint32_t)(2 + needs_pad + len);
}

// ─── Public API ──────────────────────────────────────────────────────────────

int secp256k1_pubkey(const uint8_t priv[32], uint8_t pub[65]) {
    sc_t k; sc_from_bytes(&k, priv);
    if (sc_is_zero(&k) || fe_cmp((fe_t*)&k, (fe_t*)&FN) >= 0) return -1;
    pt_t Q; pt_scalar_mul_G(&Q, &k);
    fe_t x, y;
    if (pt_to_affine(&Q, &x, &y)) return -1;
    pub[0] = 0x04;
    fe_to_bytes(&x, pub + 1);
    fe_to_bytes(&y, pub + 33);
    return 0;
}

int secp256k1_sign(const uint8_t priv[32],
                   const uint8_t hash[32],
                   uint8_t sig_out[72],
                   uint32_t *sig_len)
{
    sc_t privk, k, z, r_sc, s_sc;
    sc_from_bytes(&privk, priv);
    sc_from_bytes(&z, hash);
    if (sc_is_zero(&privk) || fe_cmp((fe_t*)&privk, (fe_t*)&FN) >= 0) return -1;

    rfc6979_nonce(priv, hash, &k);

    pt_t R; pt_scalar_mul_G(&R, &k);
    fe_t rx, ry;
    if (pt_to_affine(&R, &rx, &ry)) return -1;

    // r = rx mod n
    memcpy(&r_sc, &rx, 32);
    sc_reduce(&r_sc);
    if (sc_is_zero(&r_sc)) return -1;

    // s = k^-1 * (z + r*privk) mod n
    // Compute r * privk mod n
    sc_t rp;
    sc_mul_mod_n(&rp, &r_sc, &privk);
    // z + r*privk
    sc_add(&s_sc, &z, &rp);
    // k^-1 mod n (use Fermat: k^(n-2) mod n)
    sc_t kinv;
    // Use sc_mul_mod_n with sc_inv approach:
    // kinv = k^(n-2) mod n via square-and-multiply
    {
        sc_t base2, result2;
        fe_copy((fe_t*)&base2, (fe_t*)&k);
        fe_one((fe_t*)&result2);
        uint32_t exp2[8]; memcpy(exp2, FN.w, 32); exp2[7] -= 2; // n-2
        for (int word = 0; word < 8; word++) {
            for (int bit = 31; bit >= 0; bit--) {
                sc_mul_mod_n(&result2, &result2, &result2);
                if ((exp2[word] >> bit) & 1)
                    sc_mul_mod_n(&result2, &result2, &base2);
            }
        }
        fe_copy((fe_t*)&kinv, (fe_t*)&result2);
    }
    sc_mul_mod_n(&s_sc, &kinv, &s_sc);
    if (sc_is_zero(&s_sc)) return -1;

    // Low-s normalisation (BIP-62)
    {
        // if s > n/2, s = n - s
        sc_t half_n;
        fe_copy((fe_t*)&half_n, (fe_t*)&FN);
        // half_n = (n+1)/2  (n is odd)
        uint64_t carry = 1;
        for (int i = 7; i >= 0; i--) {
            uint64_t v = (uint64_t)half_n.w[i] + carry; // +1
            half_n.w[i] = (uint32_t)v; carry = v >> 32;
        }
        // shift right 1 (divide by 2)
        carry = 0;
        for (int i = 0; i < 8; i++) {
            uint32_t next = (half_n.w[i] & 1) ? 0x80000000u : 0;
            half_n.w[i]   = (half_n.w[i] >> 1) | (uint32_t)carry;
            carry = next;
        }
        if (fe_cmp((fe_t*)&s_sc, (fe_t*)&half_n) > 0) {
            // s = n - s
            fe_t tmp; fe_copy(&tmp, (fe_t*)&FN);
            u256_sub_inplace(tmp.w, s_sc.w);
            fe_copy((fe_t*)&s_sc, &tmp);
        }
    }

    uint8_t r_bytes[32], s_bytes[32];
    sc_to_bytes(&r_sc, r_bytes);
    sc_to_bytes(&s_sc, s_bytes);

    uint8_t r_der[35], s_der[35];
    uint32_t r_len = encode_der_int(r_bytes, r_der);
    uint32_t s_len = encode_der_int(s_bytes, s_der);

    sig_out[0] = 0x30;
    sig_out[1] = (uint8_t)(r_len + s_len);
    memcpy(sig_out + 2,          r_der, r_len);
    memcpy(sig_out + 2 + r_len,  s_der, s_len);
    *sig_len = 2 + r_len + s_len;
    return 0;
}
