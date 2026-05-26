/* link.ld — Linker script for PicoRV32 + TernaryCore Secure Element
 * ROM: 0x00000000 (4 KB)
 * RAM: 0x10000000 (64 KB PSRAM)
 */

OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    ROM (rx)  : ORIGIN = 0x00000000, LENGTH = 4096
    RAM (rwx) : ORIGIN = 0x10000000, LENGTH = 65536
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

    _stack_top = ORIGIN(RAM) + LENGTH(RAM);
}
