/* SPDX-License-Identifier: BSD-3-Clause */
/*
 * Authors: Wei Chen <wei.chen@arm.com>
 *          Lorin Urbantat
 *
 * Copyright (c) 2018, Wei Chen. All rights reserved.
 * Copyright (c) 2026, Lorin Urbantat.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. Neither the name of the copyright holder nor the names of its
 *    contributors may be used to endorse or promote products derived from
 *    this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */

#include <uk/asm.h>
#include <uk/asm/lcpu.h>
#include <uk/config.h>
#include <uk/plat/common/sections.h>
#include <uk/reloc.h>

#define BOOTSTACK_SIZE 4096
.section .bss
.balign 16
.space BOOTSTACK_SIZE
bootstack_top:

.text
ENTRY(_librpi5plat_entry)
	mov	x20, x0 // preserve dtb addr
	// Drop to EL1 if in EL2 otherwise branch to 5.
	mrs	x1, CurrentEL
	cmp	x1, #0x8
	b.ne	5f

	ldr	x1, =(1 << 31)
	msr	hcr_el2, x1
	mrs	x1, cnthctl_el2
	orr	x1, x1, #3
	msr	cnthctl_el2, x1
	msr	cntvoff_el2, xzr
	ldr	x1, =0x3c5
	msr	spsr_el2, x1
	adr	x1, 5f
	msr	elr_el2, x1
	eret

5:
	// Load vector table in exceptions.S.
	ldr	x1, =vector_table
	msr	VBAR_EL1, x1
	isb

	// Disable other cores.
	mrs	x1, mpidr_el1
	and	x1, x1, #0xff
	cbz	x1, 1f
0:
	wfe
	b	0b
1:



	// Early debug stop: attach GDB, then clear x2 or rpi5_gdb_spin_flag.
	ldr	x3, =rpi5_gdb_spin_flag
4:
	ldr	x2, [x3]
	nop
	cbnz	x2, 4b


	ldr	x1, =bootstack_top
	mov	sp, x1

	ldr	x1, =__bss_start
	ldr	x2, =_end
	mov	x3, xzr
2:
	cmp	x1, x2
	b.hs	3f
	str	x3, [x1], #8
	b	2b
3:
	// Print early debug info.
	bl	rpi5_pl011_init
	ldr	x0, =rpi5_msg_entry
	bl	rpi5_pl011_puts
	ldr	x0, =rpi5_msg_dtb
	bl	rpi5_pl011_puts
	mov	x0, x20
	bl	rpi5_pl011_put_hex64
	ldr	x0, =rpi5_msg_crlf
	bl	rpi5_pl011_puts
	mov	x0, x20
	mov	x1, #64
	bl	rpi5_pl011_dump_mem

	ldr	x0, =rpi5_msg_reloc
	bl	rpi5_pl011_puts
	mov	x0, xzr
	mov	x1, xzr
	bl	do_uk_reloc



	ldr	x0, =rpi5_msg_pcpu
	bl	rpi5_pl011_puts
	ldr	x1, =_uk_pcpuvar_base
	msr	tpidr_el1, x1

	// Set up FDT bootinfo and enter Unikraft.
	ldr	x0, =rpi5_msg_fdt
	bl	rpi5_pl011_puts
	mov	x0, x20
	bl	ukplat_bootinfo_fdt_setup
	ldr	x0, =rpi5_msg_setup
	bl	rpi5_pl011_puts
	b	rpi5_ukplat_entry
END(_librpi5plat_entry)

.section .rodata
rpi5_msg_entry:
	.asciz "\r\nrpi5: unikraft entry\r\n"
rpi5_msg_dtb:
	.asciz "rpi5: x0/dtb = 0x"
rpi5_msg_crlf:
	.asciz "\r\n"
rpi5_msg_reloc:
	.asciz "rpi5: reloc\r\n"
rpi5_msg_pcpu:
	.asciz "rpi5: pcpuvar\r\n"
rpi5_msg_fdt:
	.asciz "rpi5: fdt bootinfo setup\r\n"
rpi5_msg_setup:
	.asciz "rpi5: handoff to ukplat setup\r\n"

.section .data
.global rpi5_gdb_spin_flag
rpi5_gdb_spin_flag:
	.quad 1
