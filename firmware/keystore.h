// keystore.h — Volatile 4-slot SRAM key store
// SPDX-License-Identifier: CERN-OHL-S-2.0
//
// Keys are 32 bytes (256-bit private keys for secp256k1).
// Storage is SRAM-only — contents are lost on power cycle.
// Phase 3 will add encrypted flash persistence.
#pragma once
#include <stdint.h>
#include <stddef.h>

#define KS_SLOTS      4
#define KS_KEY_BYTES  32

typedef enum {
    KS_OK         = 0,
    KS_ERR_SLOT   = 1,   // invalid slot number
    KS_ERR_EMPTY  = 2,   // slot not provisioned
} ks_err_t;

void     ks_init(void);
ks_err_t ks_store(uint8_t slot, const uint8_t key[KS_KEY_BYTES]);
ks_err_t ks_delete(uint8_t slot);
ks_err_t ks_get(uint8_t slot, uint8_t key_out[KS_KEY_BYTES]);
int      ks_occupied(uint8_t slot);
