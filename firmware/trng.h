// trng.h — Lightweight LFSR-based TRNG
// SPDX-License-Identifier: CERN-OHL-S-2.0
#pragma once
#include <stdint.h>
#include <stddef.h>

void     trng_init(uint32_t seed);
uint32_t trng_word(void);
void     trng_bytes(uint8_t *buf, size_t len);
