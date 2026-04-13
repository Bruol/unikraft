ENTRY(_start)

SECTIONS
{
    . = 0x80000;

    .text : ALIGN(16) {
        KEEP(*(.text._start))
        *(.text*)
        *(.rodata*)
    }

    .data : ALIGN(16) {
        *(.data*)
    }

    .bss (NOLOAD) : ALIGN(16) {
        __bss_start = .;
        *(.bss*)
        *(COMMON)
        __bss_end = .;
    }

    . = ALIGN(16);
    . += 0x4000;
    __stack_top = .;
}
