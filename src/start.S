.section .text._start, "ax"

.global _start
.type _start, %function

_start:
    mrs x1, mpidr_el1
    and x1, x1, #3
    cbz x1, 1f

secondary_core_hold:
    wfe
    b secondary_core_hold

1:
    // Early debug stop: attach GDB, then `set $x0 = 0` to continue.
    ldr x0, =1
2:
    nop
    cbnz x0, 2b

    ldr x1, =__stack_top
    mov sp, x1

    bl clear_bss
    bl kernel_main

halt:
    wfe
    b halt

.type clear_bss, %function
clear_bss:
    ldr x1, =__bss_start
    ldr x2, =__bss_end
    mov x3, #0
3:
    cmp x1, x2
    b.hs 4f
    str x3, [x1], #8
    b 3b
4:
    ret
