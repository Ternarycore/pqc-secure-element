/* link.ld — PicoRV32 TernaryCore SE linker script (Phase 2)
 * ROM:  0x00000000  16 KB  (code + rodata + .data load image)
 * RAM:  0x10000000   8 KB  (data + bss + stack)
 * Stack grows down from 0x10001FFC (top of 8 KB SRAM).
 */

OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    ROM (rx)  : ORIGIN = 0x00000000, LENGTH = 16384
    RAM (rwx) : ORIGIN = 0x10000000, LENGTH = 8192
}

SECTIONS
{
    .text : {
        *(.text.startup)
        *(.text*)
    } > ROM

    .rodata : {
        *(.rodata*)
        *(.srodata*)
    } > ROM

    . = ALIGN(4);
    _etext = .;

    /* .data stored in ROM (AT _etext), copied to RAM by startup.S */
    .data : AT (_etext) {
        _data_start = .;
        *(.data*)
        *(.sdata*)
        . = ALIGN(4);
        _data_end = .;
    } > RAM

    .bss (NOLOAD) : {
        __bss_start = .;
        *(.bss*)
        *(.sbss*)
        *(COMMON)
        . = ALIGN(4);
        __bss_end = .;
    } > RAM

    _stack_top = 0x10001FFC;
}
