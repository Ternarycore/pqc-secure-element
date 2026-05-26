// startup.S — Minimal crt0 for PicoRV32 bare-metal
// SPDX-License-Identifier: CERN-OHL-S-2.0

.section .text.startup
.globl _start
_start:
    // Set stack pointer to top of PSRAM (0x10000000 + 64KB)
    lui sp, %hi(0x10010000)
    addi sp, sp, %lo(0x10010000)

    // Clear .bss
    lui t0, %hi(__bss_start)
    addi t0, t0, %lo(__bss_start)
    lui t1, %hi(__bss_end)
    addi t1, t1, %lo(__bss_end)
1:
    bge t0, t1, 2f
    sw zero, 0(t0)
    addi t0, t0, 4
    j 1b
2:

    // Jump to main
    jal zero, main

.section .text.trap
.globl trap_entry
trap_entry:
    // Simple trap handler: infinite loop
    j trap_entry
