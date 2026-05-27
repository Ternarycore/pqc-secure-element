// periph.h — Memory-mapped peripheral addresses
// SPDX-License-Identifier: CERN-OHL-S-2.0
#pragma once
#include <stdint.h>

// UART0 — BL702 USB debug console (0x02000000)
#define UART0_BASE   0x02000000UL
// UART1 — ESP32-S3 AT-command link (0x04000000)
#define UART1_BASE   0x04000000UL
// Accel — Ternary poly-mul (0x03000000)
#define ACCEL_BASE   0x03000000UL

// Register offsets (shared layout for both UARTs)
#define UART_TX_DATA 0x00   // W: byte to transmit
#define UART_TX_STAT 0x04   // R: bit0 = busy
#define UART_RX_DATA 0x08   // R: received byte (clears rx_ready)
#define UART_RX_STAT 0x0C   // R: bit0 = data_ready

// Accel register offsets
#define ACCEL_CTRL      0x00   // [0]=start, [1]=reset, [31]=done
#define ACCEL_COEFF_IDX 0x04   // coefficient index (0–255)
#define ACCEL_COEFF_A   0x08   // write coeff_a
#define ACCEL_COEFF_B   0x0C   // write coeff_b
#define ACCEL_RESULT    0x10   // read result

static inline volatile uint32_t *uart_reg(uint32_t base, uint32_t off) {
    return (volatile uint32_t *)(base + off);
}

static inline void uart_putc(uint32_t base, char c) {
    while (*uart_reg(base, UART_TX_STAT) & 1) {}
    *uart_reg(base, UART_TX_DATA) = (uint8_t)c;
}

static inline void uart_puts(uint32_t base, const char *s) {
    while (*s) uart_putc(base, *s++);
}

// Returns 1 if a byte is available, 0 otherwise.
static inline int uart_rx_ready(uint32_t base) {
    return (int)(*uart_reg(base, UART_RX_STAT) & 1);
}

// Blocking read — waits until a byte arrives.
static inline char uart_getc(uint32_t base) {
    while (!uart_rx_ready(base)) {}
    return (char)(*uart_reg(base, UART_RX_DATA) & 0xFF);
}
