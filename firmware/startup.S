// startup.S — crt0 for PicoRV32 bare-metal (Phase 2)
// SPDX-License-Identifier: CERN-OHL-S-2.0

.section .text.startup
.globl _start
_start:
    // Stack pointer: top of 8 KB SRAM (0x10000000 + 8192 - 4)
    li   sp, 0x10001FFC

    // Copy .data section from ROM load address (_etext) to RAM (_data_start.._data_end)
    la   t0, _etext
    la   t1, _data_start
    la   t2, _data_end
.Lcopy_data:
    bge  t1, t2, .Lcopy_done
    lw   t3, 0(t0)
    sw   t3, 0(t1)
    addi t0, t0, 4
    addi t1, t1, 4
    j    .Lcopy_data
.Lcopy_done:

    // Zero .bss
    la   t0, __bss_start
    la   t1, __bss_end
.Lzero_bss:
    bge  t0, t1, .Lbss_done
    sw   zero, 0(t0)
    addi t0, t0, 4
    j    .Lzero_bss
.Lbss_done:

    call main

    // main() should never return — spin here if it does
.Lhalt:
    j .Lhalt

.section .text.trap
.globl trap_entry
trap_entry:
    j trap_entry
