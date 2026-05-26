// main.c — TernaryCore Secure Element firmware skeleton
// Runs on PicoRV32 (bare-metal, no OS)
// TODO (US-005): AT-command UART interface + Kyber call stubs

#include <stdint.h>

#define UART_BASE  0x02000000
#define ACCEL_BASE 0x03000000

volatile uint32_t * const uart_data = (uint32_t *)(UART_BASE + 0x00);
volatile uint32_t * const uart_stat = (uint32_t *)(UART_BASE + 0x04);

void uart_putc(char c) {
    while (*uart_stat & 0x1) {}
    *uart_data = (uint32_t)c;
}

void uart_puts(const char *s) {
    while (*s) uart_putc(*s++);
}

void main(void) {
    uart_puts("TernaryCore-SE booting...\r\n");
    while (1) {}
}
