// secp256k1.h — Minimal secp256k1 ECDSA (sign + pubkey derive)
// SPDX-License-Identifier: CERN-OHL-S-2.0
#pragma once
#include <stdint.h>

// All byte arrays are big-endian (matches Bitcoin / BIP standards).

// Derive 64-byte uncompressed public key (04 || X || Y) from 32-byte private key.
// Returns 0 on success, -1 on invalid key.
int secp256k1_pubkey(const uint8_t priv[32], uint8_t pub[65]);

// Sign a 32-byte hash with a 32-byte private key.
// Outputs DER-encoded signature into sig_out (max 72 bytes).
// sig_len set to actual DER length.
// Returns 0 on success, -1 on error.
int secp256k1_sign(const uint8_t priv[32],
                   const uint8_t hash[32],
                   uint8_t sig_out[72],
                   uint32_t *sig_len);
