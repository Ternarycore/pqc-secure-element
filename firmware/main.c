// main.c — TernaryCore Secure Element AT-command firmware (Phase 2)
// RISC-V RV32IM bare-metal, PicoRV32 on Tang Nano 9k.
// AT-commands arrive on UART1 (ESP32-S3 link), responses sent on UART1.
// Boot banner printed on UART0 (debug console).
//
// Protocol (must match ternarycore_se_hal.cpp):
//   AT+RAND:<len>             → RND:<hex_len_bytes>\r\nOK\r\n
//   AT+SIGN:ECDSA:<s>:<hash>  → SIG:<der_hex>\r\nOK\r\n
//   AT+STORE:<slot>:<hex64>   → OK\r\n / ERROR:<msg>\r\n
//   AT+DEL:<slot>             → OK\r\n / ERROR:<msg>\r\n
//   AT+PUBKEY:<slot>          → PUB:<hex33_compressed>\r\nOK\r\n
//   AT+TEST                   → OK\r\n / ERROR:<msg>\r\n
//   AT+INFO                   → INFO:TernaryCore-SE:2.0.0\r\nOK\r\n
//
// Error responses: ERR:<n>\r\n  (1=param,2=auth,3=locked,5=notfound,6=mem)

#include <stdint.h>
#include <stddef.h>

#include "periph.h"
#include "trng.h"
#include "sha256.h"
#include "secp256k1.h"
#include "keystore.h"

// ─── libc stubs (bare-metal, no standard library linked) ─────────────

void *memset(void *s, int c, size_t n) {
    unsigned char *p = (unsigned char *)s;
    while (n--) *p++ = (unsigned char)c;
    return s;
}

void *memcpy(void *d, const void *s, size_t n) {
    unsigned char       *dst = (unsigned char *)d;
    const unsigned char *src = (const unsigned char *)s;
    while (n--) *dst++ = *src++;
    return d;
}

// ─── String helpers ──────────────────────────────────────────────────

static int str_ncmp(const char *a, const char *b, int n) {
    for (int i = 0; i < n; i++) {
        if (a[i] != b[i]) return (unsigned char)a[i] - (unsigned char)b[i];
        if (a[i] == '\0') return 0;
    }
    return 0;
}

static unsigned int str_to_uint(const char *s) {
    unsigned int v = 0;
    while (*s >= '0' && *s <= '9') v = v * 10 + (unsigned int)(*s++ - '0');
    return v;
}

// ─── Hex helpers ─────────────────────────────────────────────────────

static char hex_digit(uint8_t n) {
    return (char)(n < 10 ? '0' + n : 'A' + (n - 10));
}

static int hex_val(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    return -1;
}

static void tx_hex(const uint8_t *data, size_t len) {
    for (size_t i = 0; i < len; i++) {
        uart_putc(UART1_BASE, hex_digit(data[i] >> 4));
        uart_putc(UART1_BASE, hex_digit(data[i] & 0xF));
    }
}

// Decode hex string into buf.  Returns number of bytes decoded, or 0 on error.
static size_t hex_decode(uint8_t *buf, size_t cap, const char *hex, size_t hex_len) {
    if (hex_len & 1) return 0;           // must be even
    size_t out = hex_len / 2;
    if (out > cap) return 0;
    for (size_t i = 0; i < out; i++) {
        int hi = hex_val(hex[i * 2]);
        int lo = hex_val(hex[i * 2 + 1]);
        if (hi < 0 || lo < 0) return 0;
        buf[i] = (uint8_t)((hi << 4) | lo);
    }
    return out;
}

// Return length of null-terminated string.
static size_t str_len(const char *s) {
    size_t n = 0;
    while (*s++) n++;
    return n;
}

// ─── AT-command I/O ──────────────────────────────────────────────────

#define CMD_BUF_SZ 256

static char cmd_buf[CMD_BUF_SZ];
static int  cmd_pos;

static void at_puts(const char *s) {
    uart_puts(UART1_BASE, s);
}

static void at_ok(void) {
    at_puts("OK\r\n");
}

static void at_error_msg(const char *msg) {
    at_puts("ERROR:");
    at_puts(msg);
    at_puts("\r\n");
}

// Numeric error code for HAL mapping:
// 1=SE_ERR_PARAM, 2=SE_ERR_AUTH, 5=SE_ERR_NOTFOUND, 6=SE_ERR_MEMORY
static void at_err_code(int code) {
    char buf[8];
    buf[0] = 'E'; buf[1] = 'R'; buf[2] = 'R'; buf[3] = ':';
    buf[4] = (char)('0' + (code % 10));
    buf[5] = '\r'; buf[6] = '\n'; buf[7] = '\0';
    at_puts(buf);
}

// ─── Command handlers ────────────────────────────────────────────────

// AT+RAND:<len>  →  RND:<hex_len_bytes>\r\n
// len: 1–64 bytes.
static void cmd_rand(const char *args) {
    unsigned int len = str_to_uint(args);
    if (len == 0 || len > 64) {
        at_err_code(1);   // SE_ERR_PARAM
        return;
    }
    uint8_t r[64];
    trng_bytes(r, len);
    at_puts("RND:");
    tx_hex(r, len);
    at_puts("\r\n");
}

// AT+SIGN:ECDSA:<slot>:<hash_hex64>  →  SIG:<der_hex>\r\n
// AT+SIGN:SCHNORR  →  ERR:5  (Phase 3 PQC, not yet available)
// hash_hex64: 64 hex chars = 32-byte pre-computed SHA-256 hash.
// The HAL always hashes on the host side before calling sign.
static void cmd_sign(const char *args) {
    // Expect "ECDSA:<slot>:<hash_hex>"
    if (str_ncmp(args, "ECDSA:", 6) != 0) {
        at_err_code(5);   // SE_ERR_NOTFOUND (SCHNORR deferred to Phase 3)
        return;
    }
    const char *p = args + 6;
    int slot = p[0] - '0';
    if (slot < 0 || slot > 3 || p[1] != ':') {
        at_err_code(1);
        return;
    }
    const char *hash_hex = p + 2;
    if (str_len(hash_hex) < 64) {
        at_err_code(1);
        return;
    }

    uint8_t hash[32];
    if (hex_decode(hash, 32, hash_hex, 64) != 32) {
        at_err_code(1);
        return;
    }

    uint8_t key[32];
    if (ks_get((uint8_t)slot, key) != KS_OK) {
        at_err_code(5);   // SE_ERR_NOTFOUND
        return;
    }

    uint8_t  der[72];
    uint32_t der_len;
    if (secp256k1_sign(key, hash, der, &der_len) != 0) {
        at_error_msg("signing failed");
        return;
    }

    at_puts("SIG:");
    tx_hex(der, der_len);
    at_puts("\r\n");
}

// AT+PUBKEY:<slot>  →  PUB:<hex33_compressed>\r\n
// Output is a 33-byte compressed public key (02/03 || Gx).
static void cmd_pubkey(const char *args) {
    int slot = args[0] - '0';
    if (slot < 0 || slot > 3) {
        at_err_code(1);
        return;
    }
    uint8_t key[32];
    if (ks_get((uint8_t)slot, key) != KS_OK) {
        at_err_code(5);   // SE_ERR_NOTFOUND
        return;
    }

    // secp256k1_pubkey returns 65-byte uncompressed key: 04 || Gx (32) || Gy (32)
    uint8_t pub65[65];
    if (secp256k1_pubkey(key, pub65) != 0) {
        at_error_msg("pubkey failed");
        return;
    }

    // Compress: 02 if Gy even, 03 if Gy odd, followed by 32-byte Gx.
    uint8_t pub33[33];
    pub33[0] = 0x02 | (pub65[64] & 0x01);
    memcpy(pub33 + 1, pub65 + 1, 32);

    at_puts("PUB:");
    tx_hex(pub33, 33);
    at_puts("\r\n");
}

// AT+STORE:<slot>:<hex64>  →  OK\r\n
// Stores a 32-byte secp256k1 private key in the given slot.
static void cmd_store(const char *args) {
    int slot = args[0] - '0';
    if (slot < 0 || slot > 3 || args[1] != ':') {
        at_error_msg("format: AT+STORE:<slot>:<hex64>");
        return;
    }
    const char *p = args + 2;
    if (str_len(p) < 64) {
        at_err_code(1);
        return;
    }
    uint8_t key[32];
    if (hex_decode(key, 32, p, 64) != 32) {
        at_err_code(1);
        return;
    }
    if (ks_store((uint8_t)slot, key) != KS_OK) {
        at_err_code(6);   // SE_ERR_MEMORY
        return;
    }
    at_ok();
}

// AT+DEL:<slot>  →  OK\r\n
static void cmd_del(const char *args) {
    int slot = args[0] - '0';
    if (slot < 0 || slot > 3) {
        at_err_code(1);
        return;
    }
    ks_delete((uint8_t)slot);
    at_ok();
}

// AT+TEST  →  OK\r\n
// Runs SHA-256 and ECDSA self-tests.
static void cmd_test(void) {
    // SHA-256("") = e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
    static const uint8_t sha_empty_ref[32] = {
        0xe3,0xb0,0xc4,0x42,0x98,0xfc,0x1c,0x14,
        0x9a,0xfb,0xf4,0xc8,0x99,0x6f,0xb9,0x24,
        0x27,0xae,0x41,0xe4,0x64,0x9b,0x93,0x4c,
        0xa4,0x95,0x99,0x1b,0x78,0x52,0xb8,0x55
    };
    uint8_t sha_out[32];
    sha256((const uint8_t *)"", 0, sha_out);
    for (int i = 0; i < 32; i++) {
        if (sha_out[i] != sha_empty_ref[i]) {
            at_error_msg("SHA-256 test failed");
            return;
        }
    }

    // ECDSA: pubkey from private key 0x00..01 must be generator G (uncompressed)
    static const uint8_t g_priv[32] = {
        0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0,
        0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,1
    };
    static const uint8_t g_pub_ref[65] = {
        0x04,
        0x79,0xBE,0x66,0x7E,0xF9,0xDC,0xBB,0xAC,
        0x55,0xA0,0x62,0x95,0xCE,0x87,0x0B,0x07,
        0x02,0x9B,0xFC,0xDB,0x2D,0xCE,0x28,0xD9,
        0x59,0xF2,0x81,0x5B,0x16,0xF8,0x17,0x98,
        0x48,0x3A,0xDA,0x77,0x26,0xA3,0xC4,0x65,
        0x5D,0xA4,0xFB,0xFC,0x0E,0x11,0x08,0xA8,
        0xFD,0x17,0xB4,0x48,0xA6,0x85,0x54,0x19,
        0x9C,0x47,0xD0,0x8F,0xFB,0x10,0xD4,0xB8
    };
    uint8_t g_pub[65];
    if (secp256k1_pubkey(g_priv, g_pub) != 0) {
        at_error_msg("ECDSA pubkey failed");
        return;
    }
    for (int i = 0; i < 65; i++) {
        if (g_pub[i] != g_pub_ref[i]) {
            at_error_msg("ECDSA G mismatch");
            return;
        }
    }
    at_ok();
}

// AT+INFO  →  INFO:TernaryCore-SE:2.0.0\r\n
static void cmd_info(void) {
    at_puts("INFO:TernaryCore-SE:2.0.0\r\n");
}

// Stub: unimplemented commands (Phase 3)  →  ERR:5\r\n
static void cmd_not_impl(void) {
    at_err_code(5);   // SE_ERR_NOTFOUND
}

// ─── AT-command dispatcher ───────────────────────────────────────────

static int cmd_is(const char *s) {
    int len = 0;
    while (s[len]) len++;
    if (str_ncmp(cmd_buf, s, len) != 0) return 0;
    return cmd_buf[len] == '\0';
}

static int cmd_starts(const char *s) {
    int len = 0;
    while (s[len]) len++;
    return str_ncmp(cmd_buf, s, len) == 0;
}

static void cmd_dispatch(void) {
    cmd_buf[cmd_pos] = '\0';

    if      (cmd_starts("AT+RAND:"))           { cmd_rand(cmd_buf + 8); }
    else if (cmd_starts("AT+SIGN:"))           { cmd_sign(cmd_buf + 8); }
    else if (cmd_starts("AT+PUBKEY:"))         { cmd_pubkey(cmd_buf + 10); }
    else if (cmd_starts("AT+STORE:"))          { cmd_store(cmd_buf + 9); }
    else if (cmd_starts("AT+DEL:"))            { cmd_del(cmd_buf + 7); }
    else if (cmd_is("AT+TEST"))                { cmd_test(); }
    else if (cmd_is("AT+INFO"))                { cmd_info(); }
    else if (cmd_starts("AT+CTR:") ||
             cmd_starts("AT+READ:"))            { cmd_not_impl(); }
    else                                        { at_err_code(1); }
}

// ─── Main ────────────────────────────────────────────────────────────

void main(void) {
    uart_puts(UART0_BASE, "TernaryCore-SE booting...\r\n");
    uart_puts(UART1_BASE, "TernaryCore-SE ready\r\n");

    trng_init(0xDEADBEEF);  // Phase 3: seed from hardware TRNG / ring oscillator
    ks_init();

    cmd_pos = 0;
    while (1) {
        if (!uart_rx_ready(UART1_BASE)) continue;

        char c = uart_getc(UART1_BASE);

        if (c == '\r' || c == '\n') {
            if (cmd_pos > 0) {
                cmd_dispatch();
                cmd_pos = 0;
            }
        } else if ((uint8_t)c >= 0x20 && (uint8_t)c <= 0x7E) {
            if (cmd_pos < CMD_BUF_SZ - 1)
                cmd_buf[cmd_pos++] = c;
        }
    }
}
