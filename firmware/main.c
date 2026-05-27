// main.c — TernaryCore Secure Element AT-command firmware (Phase 2)
// RISC-V RV32IM bare-metal, PicoRV32 on Tang Nano 9k.
// AT-commands arrive on UART1 (ESP32-S3 link), responses sent on UART1.
// Boot banner printed on UART0 (debug console).
//
// Commands: AT+RAND  AT+SIGN:<hex>  AT+PUBKEY  AT+STORE:<s>,<hex>
//            AT+DEL:<s>  AT+TEST  AT+INFO

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

static void at_error(void) {
    at_puts("ERROR\r\n");
}

static void at_error_msg(const char *msg) {
    at_puts("ERROR:");
    at_puts(msg);
    at_puts("\r\n");
}

// ─── Command handlers ────────────────────────────────────────────────

static void cmd_rand(void) {
    uint8_t r[32];
    trng_bytes(r, 32);
    for (int i = 0; i < 32; i++) {
        uart_putc(UART1_BASE, hex_digit(r[i] >> 4));
        uart_putc(UART1_BASE, hex_digit(r[i] & 0xF));
    }
    at_puts("\r\n");
    at_ok();
}

static void cmd_sign(const char *hex_msg) {
    uint8_t key[32];
    if (ks_get(0, key) != KS_OK) {
        at_error_msg("no key loaded (use AT+STORE)");
        return;
    }

    uint8_t msg[128];
    int     msg_len = 0;
    while (*hex_msg == ' ' || *hex_msg == '\t') hex_msg++;
    while (*hex_msg && *hex_msg != '\r' && *hex_msg != '\n' && msg_len < 128) {
        int hi = hex_val(hex_msg[0]);
        int lo = hex_val(hex_msg[1]);
        if (hi < 0 || lo < 0) { at_error_msg("invalid hex"); return; }
        msg[msg_len++] = (uint8_t)((hi << 4) | lo);
        hex_msg += 2;
    }
    if (msg_len == 0) { at_error_msg("empty message"); return; }

    uint8_t hash[32];
    sha256(msg, (size_t)msg_len, hash);

    uint8_t  der[72];
    uint32_t der_len;
    if (secp256k1_sign(key, hash, der, &der_len) != 0) {
        at_error_msg("signing failed");
        return;
    }
    for (uint32_t i = 0; i < der_len; i++) {
        uart_putc(UART1_BASE, hex_digit(der[i] >> 4));
        uart_putc(UART1_BASE, hex_digit(der[i] & 0xF));
    }
    at_puts("\r\n");
    at_ok();
}

static void cmd_pubkey(void) {
    uint8_t key[32];
    if (ks_get(0, key) != KS_OK) {
        at_error_msg("no key loaded (use AT+STORE)");
        return;
    }
    uint8_t pub[65];
    if (secp256k1_pubkey(key, pub) != 0) {
        at_error_msg("pubkey derivation failed");
        return;
    }
    for (int i = 0; i < 65; i++) {
        uart_putc(UART1_BASE, hex_digit(pub[i] >> 4));
        uart_putc(UART1_BASE, hex_digit(pub[i] & 0xF));
    }
    at_puts("\r\n");
    at_ok();
}

static void cmd_store(const char *args) {
    int slot = args[0] - '0';
    if (slot < 0 || slot > 3 || args[1] != ',') {
        at_error_msg("format: AT+STORE:<slot>,<hex64>");
        return;
    }
    const char *p = args + 2;
    uint8_t key[32];
    for (int i = 0; i < 32; i++) {
        int hi = hex_val(p[0]);
        int lo = hex_val(p[1]);
        if (hi < 0 || lo < 0) { at_error_msg("invalid hex key"); return; }
        key[i] = (uint8_t)((hi << 4) | lo);
        p += 2;
    }
    if (ks_store((uint8_t)slot, key) != KS_OK) {
        at_error_msg("store failed");
        return;
    }
    at_ok();
}

static void cmd_del(const char *args) {
    int slot = args[0] - '0';
    if (slot < 0 || slot > 3) { at_error_msg("invalid slot"); return; }
    ks_delete((uint8_t)slot);
    at_ok();
}

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

    // ECDSA: pubkey from private key 0x00..01 must be generator G
    static const uint8_t g_priv[32] = {
        0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0,
        0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,1
    };
    // G (uncompressed): 04 || Gx || Gy
    static const uint8_t g_pub_ref[65] = {
        0x04,
        0x79,0xBE,0x66,0x7E,0xF9,0xDC,0xBB,0xAC,
        0x55,0xA0,0x62,0x95,0xCE,0x87,0x0B,0x07,
        0x02,0x9B,0xFC,0xDB,0x2D,0xCE,0x28,0xD9,
        0x59,0xF2,0x81,0x5B,0x16,0xF8,0x17,0x98,
        0x48,0x3A,0xDA,0x77,0x26,0xA3,0xC4,0x65,
        0x5D,0xA4,0xFB,0xFC,0x0E,0x11,0x08,0xA8,
        0xFD,0x17,0xB4,0x48,0xA6,0x85,0x54,0x19,
        0x9C,0x47,0xD0,0x0F,0xFB,0x10,0xD4,0xB8
    };
    uint8_t g_pub[65];
    if (secp256k1_pubkey(g_priv, g_pub) != 0) {
        at_error_msg("ECDSA pubkey test failed");
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

static void cmd_info(void) {
    at_puts("TernaryCore-SE\r\n");
    at_puts("Phase 2 — secp256k1 ECDSA\r\n");
    at_puts("Keys: ");
    for (int i = 0; i < KS_SLOTS; i++) {
        if (i > 0) uart_putc(UART1_BASE, ',');
        uart_putc(UART1_BASE, '0' + (char)i);
        uart_putc(UART1_BASE, ks_occupied((uint8_t)i) ? '+' : '-');
    }
    at_puts("\r\n");
    at_puts("Cmds:AT+RAND,AT+SIGN,AT+PUBKEY,AT+STORE,AT+DEL,AT+TEST,AT+INFO\r\n");
    at_ok();
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

    if (cmd_is("AT+RAND"))                    { cmd_rand(); }
    else if (cmd_starts("AT+SIGN:"))          { cmd_sign(cmd_buf + 8); }
    else if (cmd_is("AT+PUBKEY"))             { cmd_pubkey(); }
    else if (cmd_starts("AT+STORE:"))         { cmd_store(cmd_buf + 9); }
    else if (cmd_starts("AT+DEL:"))           { cmd_del(cmd_buf + 7); }
    else if (cmd_is("AT+TEST"))               { cmd_test(); }
    else if (cmd_is("AT+INFO"))               { cmd_info(); }
    else                                       { at_error(); }
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
