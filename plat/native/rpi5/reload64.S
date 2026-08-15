/* SPDX-License-Identifier: BSD-3-Clause */
/* Copyright (c) 2026, Lorin Urbantat. */

#include <uk/asm.h>
#include <uk/config.h>

#if CONFIG_RPI5_EARLY_GDB_SPINLOOP

/*
 * Resident warm-reload trampoline.
 *
 * The linker fixes this code at 0x200000.  The bootstrap page tables identity
 * map that address as Normal memory, so the instruction immediately after
 * disabling translation is fetched from the same physical address.  This
 * routine deliberately uses neither the stack nor writable memory: GDB calls
 * the copy belonging to the currently running image, then replaces the ELF.
 */
.section .rpi5_reload, "ax"
.balign 64
.global rpi5_reload_trampoline
.type rpi5_reload_trampoline, %function
rpi5_reload_trampoline:
	/* No exception or debug interrupt may run through a stale vector table. */
	msr	daifset, #0xf
	dsb	sy
	mrs	x13, sctlr_el1
	tbz	x13, #2, 6f

	/*
	 * Clean and invalidate every data/unified cache level by set/way.  CLIDR
	 * has a three-bit cache type per level; types 2, 3, and 4 have data.
	 * CCSIDR fields are NumSets-1, Associativity-1, and log2(line)-4.
	 */
	mrs	x0, clidr_el1
	mrs	x15, id_aa64mmfr2_el1
	ubfx	x15, x15, #20, #4		/* CCIDX */
	mov	x1, #0			/* cache level */
1:	add	x12, x1, x1, lsl #1
	lsr	x2, x0, x12
	and	x2, x2, #7
	cmp	x2, #2
	b.lo	5f

	lsl	x3, x1, #1
	msr	csselr_el1, x3		/* select data/unified cache */
	isb
	mrs	x4, ccsidr_el1
	and	x5, x4, #7
	add	x5, x5, #4			/* line position */
	cbnz	x15, 7f
	ubfx	x6, x4, #3, #10		/* last way */
	ubfx	x8, x4, #13, #15		/* last set */
	b	8f
7:	ubfx	x6, x4, #3, #21		/* CCIDX last way */
	lsr	x8, x4, #32			/* CCIDX last set */
8:	clz	w7, w6			/* way position in set/way operand */
2:	mov	x9, x6
3:	lsl	x10, x9, x7
	lsl	x11, x8, x5
	orr	x10, x10, x11
	orr	x10, x10, x3
	dc	cisw, x10
	subs	x9, x9, #1
	b.pl	3b
	subs	x8, x8, #1
	b.pl	2b
5:	add	x1, x1, #1
	cmp	x1, #7
	b.lo	1b
	dsb	sy

	/* A cold firmware entry has no dirty data cache to walk. */
6:
	/* Remove every stale instruction and translation before changing SCTLR. */
	ic	iallu
	tlbi	vmalle1
	dsb	sy
	isb
	/* Let OpenOCD's hardware breakpoint stop the otherwise non-returning park. */
	mov	x14, #(1 << 15)
	msr	mdscr_el1, x14
	isb

	/* M, C, and I are bits 0, 2, and 12.  VA=PA across this transition. */
	mrs	x0, sctlr_el1
	bic	x0, x0, #(1 << 0)
	bic	x0, x0, #(1 << 2)
	bic	x0, x0, #(1 << 12)
	msr	sctlr_el1, x0
	isb

	/*
	 * Debug AP writes are not coherent with every cache level on BCM2712.
	 * With C and M now off, invalidate the fixed image reservation and DTB by
	 * physical address (VA=PA). Dirty state was already cleaned by set/way.
	 */
	ldr	x2, =0x80000
	ldr	x3, =0x300000
9:	dc	ivac, x2
	add	x2, x2, #64
	cmp	x2, x3
	b.lo	9b
	ldr	x2, =0x10000000
	ldr	x3, =0x10014000
10:	dc	ivac, x2
	add	x2, x2, #64
	cmp	x2, x3
	b.lo	10b
	dsb	sy

	/* Leave no translation or instruction-cache state for the next image. */
	tlbi	vmalle1
	ic	iallu
	dsb	sy
	isb
	b	rpi5_reload_park

.size rpi5_reload_trampoline, . - rpi5_reload_trampoline

/*
 * This label lives in a separate linker-fixed section.  GDB must stop the
 * resident (old) image before loading the incoming image, so its address is a
 * reload ABI constant and must not depend on either image's code size.
 */
.section .rpi5_reload_park, "ax"
.global rpi5_reload_park
.type rpi5_reload_park, %function
rpi5_reload_park:
	wfe
	b	rpi5_reload_park
.size rpi5_reload_park, . - rpi5_reload_park
#endif
