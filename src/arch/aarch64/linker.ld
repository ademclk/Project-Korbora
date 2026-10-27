/* Link layout for QEMU virt (aarch64). RAM begins at 0x4000_0000. */
ENTRY(_start)

MEMORY {
    RAM (rwx) : ORIGIN = 0x40080000, LENGTH = 126M
}

SECTIONS {
    .text : ALIGN(4K) {
        __image_start = .;
        KEEP(*(.text.boot))
        *(.text .text.*)
    } > RAM

    .rodata : ALIGN(4K) {
        *(.rodata .rodata.*)
    } > RAM

    .data : ALIGN(4K) {
        *(.data .data.*)
        __image_end = .;
    } > RAM

    .bss (NOLOAD) : ALIGN(4K) {
        __bss_start = .;
        *(.bss .bss.*)
        *(COMMON)
        __bss_end = .;
    } > RAM

    .stack (NOLOAD) : ALIGN(16) {
        . += 64K;
        __stack_top = .;
    } > RAM

    . = ALIGN(4K);
    __heap_start = .;
    __heap_end = ORIGIN(RAM) + LENGTH(RAM);

    /DISCARD/ : { *(.comment) *(.eh_frame*) }
}
