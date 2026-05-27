// keystore.c — Volatile SRAM key store implementation
// SPDX-License-Identifier: CERN-OHL-S-2.0
#include "keystore.h"
#include <string.h>

static uint8_t  g_keys[KS_SLOTS][KS_KEY_BYTES];
static uint8_t  g_occupied[KS_SLOTS];

void ks_init(void) {
    memset(g_keys,     0, sizeof(g_keys));
    memset(g_occupied, 0, sizeof(g_occupied));
}

ks_err_t ks_store(uint8_t slot, const uint8_t key[KS_KEY_BYTES]) {
    if (slot >= KS_SLOTS) return KS_ERR_SLOT;
    memcpy(g_keys[slot], key, KS_KEY_BYTES);
    g_occupied[slot] = 1;
    return KS_OK;
}

ks_err_t ks_delete(uint8_t slot) {
    if (slot >= KS_SLOTS) return KS_ERR_SLOT;
    memset(g_keys[slot], 0, KS_KEY_BYTES);
    g_occupied[slot] = 0;
    return KS_OK;
}

ks_err_t ks_get(uint8_t slot, uint8_t key_out[KS_KEY_BYTES]) {
    if (slot >= KS_SLOTS) return KS_ERR_SLOT;
    if (!g_occupied[slot]) return KS_ERR_EMPTY;
    memcpy(key_out, g_keys[slot], KS_KEY_BYTES);
    return KS_OK;
}

int ks_occupied(uint8_t slot) {
    if (slot >= KS_SLOTS) return 0;
    return g_occupied[slot];
}
