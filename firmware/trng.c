// trng.c — xorshift128 PRNG seeded at boot
// SPDX-License-Identifier: CERN-OHL-S-2.0
//
// Not a true hardware RNG — suitable for nonce generation in Phase 2.
// Phase 3 will replace with a ring-oscillator based TRNG in RTL.
#include "trng.h"

static uint32_t s[4];

void trng_init(uint32_t seed) {
    // Splitmix64-style state initialisation from a single seed word.
    s[0] = seed + 0x9e3779b9u;
    s[1] = s[0] ^ (s[0] >> 16);
    s[2] = s[1] * 0x45d9f3bu;
    s[3] = s[2] ^ (s[2] >> 16);
    // Warm up
    for (int i = 0; i < 32; i++) trng_word();
}

uint32_t trng_word(void) {
    // xorshift128
    uint32_t t = s[3];
    t ^= t << 11;
    t ^= t >> 8;
    s[3] = s[2]; s[2] = s[1]; s[1] = s[0];
    t ^= s[0];
    t ^= s[0] >> 19;
    s[0] = t;
    return t;
}

void trng_bytes(uint8_t *buf, size_t len) {
    size_t i = 0;
    while (i < len) {
        uint32_t w = trng_word();
        for (int b = 0; b < 4 && i < len; b++, i++)
            buf[i] = (uint8_t)(w >> (b * 8));
    }
}
