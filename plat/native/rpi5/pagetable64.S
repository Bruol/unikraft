/* SPDX-License-Identifier: BSD-3-Clause */
/* Copyright (c) 2026, Lorin Urbantat. */

#include <uk/asm.h>
#include <uk/asm/lcpu.h>

/*
 * Early identity map for BCM2712 / Raspberry Pi 5
 * ------------------------------------------------
 * This code runs at EL1 before BSS, libfdt, the allocator, or the normal
 * Unikraft memory-region machinery is available.  It therefore performs the
 * minimum FDT parsing needed to discover RAM and builds the bootstrap map in
 * statically allocated .data pages.
 *
 * With a 48-bit VA and 4 KiB granule, translation starts at level 0.  The
 * symbol names follow Unikraft's historical page-table naming convention:
 *
 *   arm64_bpt_l3_pt0[0] -> arm64_bpt_l2_pt0
 *   arm64_bpt_l2_pt0[i] -> 1 GiB identity-mapped block i
 *
 * DT-reported RAM becomes Normal WBWA memory.  L2 indices 64..127, the
 * BCM2712 CPU physical aperture at 64..128 GiB, are always Device-nGnRnE and
 * execute-never.  Everything else remains invalid.
 */

#define FDT_MAGIC               0xd00dfeed
#define FDT_BEGIN_NODE          1
#define FDT_END_NODE            2
#define FDT_PROP                3
#define FDT_NOP                 4
#define FDT_END                 9

#define BLOCK_SIZE              0x40000000
#define PTE_TABLE               0x3
#define PTE_AF                  (1 << 10)
#define PTE_SH_INNER            (3 << 8)
#define PTE_ATTR_NORMAL         (NORMAL_WB << 2)
#define PTE_ATTR_DEVICE         (DEVICE_nGnRnE << 2)
#define PTE_PXN                 (1 << 53)
#define PTE_UXN                 (1 << 54)
#define PTE_NORMAL              (1 | PTE_AF | PTE_SH_INNER | PTE_ATTR_NORMAL)
#define PTE_DEVICE              (1 | PTE_AF | PTE_ATTR_DEVICE | PTE_PXN | PTE_UXN)
#define MAX_RAM_RANGES          16

/* FDT scalar fields are stored in big-endian byte order. */
.macro load_be32 dst, addr
	ldr	w\dst, [\addr]
	rev	w\dst, w\dst
.endm

/*
 * Compare an FDT string byte-by-byte.  Before translation is enabled the
 * architecture may treat accesses as Device memory, where an unaligned word
 * or doubleword load faults regardless of SCTLR_EL1.A.  FDT strings are packed
 * and have no natural-alignment guarantee, so ldrb is intentional here.
 */
.macro match_bytes out, ptr, literal, count
	ldr	x16, =\literal
	mov	x17, #0
	mov	\out, #1
.Lmatch_loop\@:	ldrb	w6, [\ptr, x17]
	ldrb	w7, [x16, x17]
	cmp	w6, w7
	b.ne	.Lmatch_no\@
	add	x17, x17, #1
	cmp	x17, #\count
	b.lo	.Lmatch_loop\@
	b	.Lmatch_done\@
.Lmatch_no\@:	mov	\out, #0
.Lmatch_done\@:
.endm

/*
 * x0: physical address of the firmware FDT
 *
 * Returns with VA=PA translation plus instruction/data caches enabled.  x19
 * keeps the caller's LR because the parser calls local helper routines; x20
 * keeps the FDT address live throughout table construction.
 */
ENTRY(rpi5_start_mmu)
	/*
	 * Firmware must hand off with stage-1 translation and the data cache
	 * disabled.  Do not try to repair an unknown live cache hierarchy here:
	 * x0=11 identifies this contract violation to an attached debugger.
	 */
	mrs	x1, sctlr_el1
	tbnz	x1, #0, rpi5_mmu_bad_entry_state
	tbnz	x1, #2, rpi5_mmu_bad_entry_state

	mov	x19, x30
	mov	x20, x0

	/* Clear bootstrap/direct-map tables and all exported boot metadata. */
	ldr	x0, =arm64_bpt_l3_pt0
	mov	x1, #(12288 + 16 + MAX_RAM_RANGES * 16)
0:	str	xzr, [x0], #8
	subs	x1, x1, #8
	b.ne	0b

	/* Populate Normal RAM blocks and exported ranges from the firmware FDT. */
	bl	rpi5_mmu_parse_fdt

	/*
	 * Connect root entry 0 to the single L2 table. With a 48-bit VA and 4 KiB
	 * granule, this next-level table has 512 entries. Each entry maps a 1 GiB
	 * block, so root entry 0 covers the 0..512 GiB bootstrap address space.
	 * Every other root entry remains zero (invalid).
	 *
	 * rpi5_mmu_parse_fdt() has already populated the L2 indices selected by
	 * DT-reported RAM with Normal WBWA identity mappings.  Fill L2[64..127]
	 * with Device-nGnRnE, execute-never identity mappings for the fixed BCM2712
	 * CPU peripheral aperture:
	 *
	 *     physical base = L2 index << 30
	 *     L2[64]  =  64 GiB = 0x1000000000
	 *     L2[127] = 127 GiB = 0x1fc0000000
	 *
	 * The loop stops before index 128, so the mapped interval is exactly
	 * [64 GiB, 128 GiB).  Each descriptor is eight bytes, hence index << 3
	 * when storing it in the L2 table.
	 */
	ldr	x0, =arm64_bpt_l3_pt0
	ldr	x1, =arm64_bpt_l2_pt0
	orr	x2, x1, #PTE_TABLE
	str	x2, [x0]
	/* Paging uses this upper-half identity alias while constructing tables. */
	ldr	x1, =arm64_bpt_l2_directmap
	orr	x2, x1, #PTE_TABLE
	str	x2, [x0, #(511 * 8)]
	mov	x3, xzr
	ldr	x4, =PTE_NORMAL
92:	lsl	x5, x3, #30
	orr	x5, x5, x4
	str	x5, [x1, x3, lsl #3]
	add	x3, x3, #1
	cmp	x3, #512
	b.lo	92b
	ldr	x1, =arm64_bpt_l2_pt0
	mov	x3, #64
	ldr	x4, =PTE_DEVICE
91:	lsl	x5, x3, #30
	orr	x5, x5, x4
	str	x5, [x1, x3, lsl #3]
	add	x3, x3, #1
	cmp	x3, #128
	b.lo	91b

	/*
	 * Publish descriptors before TTBR0, invalidate stale EL1 translations, then
	 * program attributes and geometry before setting SCTLR_EL1.M/C/I. MAIR uses
	 * Unikraft's native ARM64 indexes (Device-nGnRnE 0, Normal WBWA 5).
	 * TCR selects a 48-bit VA/PA, 4 KiB granule, inner-shareable WBWA walks, and
	 * disables TTBR1 walks.  The SCTLR masks match Unikraft's KVM EL1 setup.
	 */
	dsb	sy
	ldr	x0, =arm64_bpt_l3_pt0
	msr	ttbr0_el1, x0
	msr	ttbr1_el1, xzr
	isb
	msr	mdscr_el1, xzr
	tlbi	vmalle1
	dsb	nsh
	ldr	x0, =MAIR_INIT_ATTR
	msr	mair_el1, x0
	ldr	x0, =TCR_INIT_FLAGS
	msr	tcr_el1, x0
	isb
	/* SWD/GDB may replace the image without invalidating stale I-cache lines. */
	ic	iallu
	dsb	sy
	isb
	mrs	x0, sctlr_el1
	ldr	x1, =SCTLR_CLEAR_BITS
	bic	x0, x0, x1
	ldr	x1, =SCTLR_SET_BITS
	orr	x0, x0, x1
	msr	sctlr_el1, x0
	isb
	mov	x30, x19
	ret
END(rpi5_start_mmu)

/*
 * Parse the FDT at x20 and populate the RAM entries in arm64_bpt_l2_pt0.
 *
 * This deliberately implements only the pre-MMU subset needed here: root
 * address/size cell widths plus direct-child device_type, status, and reg.
 * It returns only after at least one non-empty RAM tuple has been recorded.
 * All parser failures branch to the shared non-returning error path.
 */
ENTRY(rpi5_mmu_parse_fdt)
	mov	x21, x30

	/*
	 * Validate the header before following any offset.  x26 is the end of the
	 * complete blob, x22..x27 bounds the structure block, and x23..x24 bounds
	 * the strings block.  Adds uses the carry flag to reject pointer overflow.
	 */
	load_be32 1, x20
	ldr	w2, =FDT_MAGIC
	cmp	w1, w2
	b.ne	rpi5_mmu_bad_magic
	add	x9, x20, #4
	load_be32 2, x9		/* totalsize */
	cmp	x2, #40
	b.lo	rpi5_mmu_bad_header
	adds	x26, x20, x2
	b.cs	rpi5_mmu_bad_header
	add	x9, x20, #8
	load_be32 3, x9		/* off_dt_struct */
	add	x9, x20, #12
	load_be32 4, x9		/* off_dt_strings */
	add	x9, x20, #32
	load_be32 5, x9		/* size_dt_strings */
	add	x9, x20, #36
	load_be32 6, x9		/* size_dt_struct */
	cmp	x3, x2
	b.hs	rpi5_mmu_bad_header
	cmp	x4, x2
	b.hs	rpi5_mmu_bad_header
	adds	x22, x20, x3
	b.cs	rpi5_mmu_bad_header
	adds	x27, x22, x6
	b.cs	rpi5_mmu_bad_header
	cmp	x27, x26
	b.hi	rpi5_mmu_bad_header
	adds	x23, x20, x4
	b.cs	rpi5_mmu_bad_header
	adds	x24, x23, x5
	b.cs	rpi5_mmu_bad_header
	cmp	x24, x26
	b.hi	rpi5_mmu_bad_header

	/*
	 * The FDT specification defaults child addresses to two cells and sizes to
	 * one cell.  Root properties override these values, but this bootstrap only
	 * accepts widths that fit in a 64-bit physical address.
	 *
	 * Depth after BEGIN_NODE is 1 for the root and 2 for its direct children.
	 * x10..x13 accumulate the properties of one possible memory node and are
	 * committed only when that node closes, so property order is irrelevant.
	 */
	mov	w28, #2			/* #address-cells */
	mov	w29, #1			/* #size-cells */
	mov	w25, wzr		/* depth */
	mov	x10, xzr		/* current device_type == memory */
	mov	x11, xzr		/* current node disabled */
	mov	x12, xzr		/* current reg value */
	mov	x13, xzr		/* current reg length */

/* Every structure-token fetch and skip is checked against x27. */
1:	add	x9, x22, #4
	cmp	x9, x27
	b.hi	rpi5_mmu_bad_struct
	load_be32 1, x22
	add	x22, x22, #4
	cmp	w1, #FDT_BEGIN_NODE
	b.eq	2f
	cmp	w1, #FDT_END_NODE
	b.eq	3f
	cmp	w1, #FDT_PROP
	b.eq	4f
	cmp	w1, #FDT_NOP
	b.eq	1b
	cmp	w1, #FDT_END
	b.eq	9f
	b	rpi5_mmu_bad_struct

2:	/* Node names are NUL-terminated; the next token starts on a 4-byte boundary. */
	add	w25, w25, #1
	cmp	w25, #2
	b.ne	20f
	mov	x10, xzr
	mov	x11, xzr
	mov	x12, xzr
	mov	x13, xzr
20:	cmp	x22, x27
	b.hs	rpi5_mmu_bad_struct
	ldrb	w1, [x22], #1
	cbnz	w1, 20b
	add	x22, x22, #3
	and	x22, x22, #-4
	b	1b

3:	/* Commit an enabled direct child only if it is a complete memory node. */
	cmp	w25, #2
	b.ne	30f
	cbz	x10, 30f
	cbnz	x11, 30f
	cbz	x12, rpi5_mmu_bad_reg
	mov	x0, x12
	mov	x1, x13
	bl	rpi5_mmu_add_reg
30:	cbz	w25, rpi5_mmu_bad_struct
	sub	w25, w25, #1
	b	1b

4:	/* Property header and value must both fit the structure block. */
	add	x9, x22, #8
	cmp	x9, x27
	b.hi	rpi5_mmu_bad_struct
	load_be32 2, x22		/* len */
	add	x9, x22, #4
	load_be32 3, x9		/* nameoff */
	add	x22, x22, #8
	add	x9, x22, x2
	cmp	x9, x27
	b.hi	rpi5_mmu_bad_struct
	add	x14, x23, x3
	cmp	x14, x24
	b.hs	rpi5_mmu_bad_string
	add	x15, x14, #4
	cmp	x15, x24
	b.hi	rpi5_mmu_bad_string
	/*
	 * At depth 1 only the root cell widths matter.  At depth 2 collect
	 * device_type, status, and reg.  Unknown properties and deeper nodes are
	 * skipped, keeping this parser deliberately smaller than libfdt.
	 */
	cmp	w25, #1
	b.ne	40f
	add	x15, x14, #15
	cmp	x15, x24
	b.hi	41f
	match_bytes x15, x14, rpi5_prop_address_cells, 15
	cbz	x15, 41f
	cmp	x2, #4
	b.ne	rpi5_mmu_bad_cells
	load_be32 28, x22
	cmp	w28, #1
	b.lo	rpi5_mmu_bad_cells
	cmp	w28, #2
	b.hi	rpi5_mmu_bad_cells
	b	48f
41:	add	x15, x14, #12
	cmp	x15, x24
	b.hi	48f
	match_bytes x15, x14, rpi5_prop_size_cells, 12
	cbz	x15, 48f
	cmp	x2, #4
	b.ne	rpi5_mmu_bad_cells
	load_be32 29, x22
	cmp	w29, #1
	b.lo	rpi5_mmu_bad_cells
	cmp	w29, #2
	b.hi	rpi5_mmu_bad_cells
	b	48f
40:	cmp	w25, #2
	b.ne	48f
	add	x15, x14, #12
	cmp	x15, x24
	b.hi	42f
	match_bytes x15, x14, rpi5_prop_device_type, 12
	cbz	x15, 42f
	cmp	x2, #7
	b.lo	48f
	match_bytes x10, x22, rpi5_value_memory, 7
	b	48f
42:	add	x15, x14, #7
	cmp	x15, x24
	b.hi	43f
	match_bytes x15, x14, rpi5_prop_status, 7
	cbz	x15, 43f
	cmp	x2, #8
	b.lo	48f
	match_bytes x11, x22, rpi5_value_disabled, 8
	b	48f
43:	match_bytes x15, x14, rpi5_prop_reg, 4
	cbz	x15, 48f
	mov	x12, x22
	mov	x13, x2
48:	add	x22, x22, x2
	add	x22, x22, #3
	and	x22, x22, #-4
	b	1b

9:	/* FDT_END is valid only after every opened node has been closed. */
	cmp	w25, #0
	b.ne	rpi5_mmu_bad_struct
	bl	rpi5_mmu_build_ranges
	mov	x30, x21
	ret
END(rpi5_mmu_parse_fdt)

/*
 * Decode and map every tuple in one memory-node reg property.
 *
 * x0 = property value, x1 = byte length; w28/w29 are address/size cell counts.
 * A tuple [base, base + size) is rounded outward to 1 GiB.  Repeated writes
 * coalesce overlapping tuples naturally.  Any block in the fixed Device
 * aperture is rejected rather than allowing RAM and MMIO attributes to alias.
 */
rpi5_mmu_add_reg:
	mov	x15, x30
	add	w2, w28, w29
	lsl	w2, w2, #2
	cbz	w2, rpi5_mmu_bad_reg
	udiv	w3, w1, w2
	madd	w4, w3, w2, wzr
	cmp	w4, w1
	b.ne	rpi5_mmu_bad_reg
	cbz	w3, rpi5_mmu_bad_reg
50:	mov	x4, xzr
	mov	w5, w28
51:	load_be32 6, x0
	add	x0, x0, #4
	lsl	x4, x4, #32
	orr	x4, x4, x6
	subs	w5, w5, #1
	b.ne	51b
	mov	x5, xzr
	mov	w6, w29
52:	load_be32 7, x0
	add	x0, x0, #4
	lsl	x5, x5, #32
	orr	x5, x5, x7
	subs	w6, w6, #1
	b.ne	52b
	cbz	x5, 59f			/* zero-sized tuples are ignored */
	adds	x6, x4, x5
	b.cs	rpi5_mmu_bad_reg
	lsr	x7, x4, #30
	ldr	x8, =(BLOCK_SIZE - 1)
	adds	x8, x6, x8
	b.cs	rpi5_mmu_bad_reg
	lsr	x8, x8, #30
	cmp	x8, #512
	b.hi	rpi5_mmu_bad_reg
	cmp	x7, x8
	b.hs	rpi5_mmu_bad_reg
53:	cmp	x7, #64
	b.lo	54f
	cmp	x7, #128
	b.lo	rpi5_mmu_device_overlap
54:	ldr	x9, =arm64_bpt_l2_pt0
	lsl	x10, x7, #30
	ldr	x11, =PTE_NORMAL
	orr	x10, x10, x11
	str	x10, [x9, x7, lsl #3]
	add	x7, x7, #1
	cmp	x7, x8
	b.lo	53b
59:	subs	w3, w3, #1
	b.ne	50b
	mov	x30, x15
	ret

/* Export the mapped Normal block runs as sorted, coalesced [base, length] pairs. */
rpi5_mmu_build_ranges:
	mov	x0, x30
	ldr	x1, =arm64_bpt_l2_pt0
	ldr	x2, =rpi5_mmu_ranges
	mov	x3, xzr			/* L2 index */
	mov	x4, xzr			/* exported range count */
	ldr	x9, =0x705
	ldr	x10, =(PTE_NORMAL & 0x705)
60:	cmp	x3, #512
	b.hs	67f
	ldr	x5, [x1, x3, lsl #3]
	and	x5, x5, x9
	cmp	x5, x10
	b.ne	66f
	mov	x6, x3			/* first block in run */
61:	add	x3, x3, #1
	cmp	x3, #512
	b.hs	62f
	ldr	x5, [x1, x3, lsl #3]
	and	x5, x5, x9
	cmp	x5, x10
	b.eq	61b
62:	cmp	x4, #MAX_RAM_RANGES
	b.hs	rpi5_mmu_too_many_ranges
	lsl	x7, x6, #30
	sub	x8, x3, x6
	lsl	x8, x8, #30
	str	x7, [x2], #8
	str	x8, [x2], #8
	add	x4, x4, #1
	b	60b
66:	add	x3, x3, #1
	b	60b
67:	cbz	x4, rpi5_mmu_no_memory
	ldr	x5, =rpi5_mmu_range_count
	str	x4, [x5]
	mov	x30, x0
	ret

/*
 * Pre-UART failure ABI (x0 and rpi5_mmu_error):
 *   1 bad magic          2 invalid header/bounds   3 bad structure token
 *   4 bad string offset  5 unsupported cell width 6 malformed reg
 *   7 no RAM             8 RAM/Device overlap     9 metadata capacity
 *  11 MMU/data cache already on
 */
rpi5_mmu_bad_magic:       mov x0, #1; b rpi5_mmu_fail
rpi5_mmu_bad_header:      mov x0, #2; b rpi5_mmu_fail
rpi5_mmu_bad_struct:      mov x0, #3; b rpi5_mmu_fail
rpi5_mmu_bad_string:      mov x0, #4; b rpi5_mmu_fail
rpi5_mmu_bad_cells:       mov x0, #5; b rpi5_mmu_fail
rpi5_mmu_bad_reg:         mov x0, #6; b rpi5_mmu_fail
rpi5_mmu_no_memory:       mov x0, #7; b rpi5_mmu_fail
rpi5_mmu_device_overlap:  mov x0, #8; b rpi5_mmu_fail
rpi5_mmu_too_many_ranges: mov x0, #9; b rpi5_mmu_fail
.global rpi5_mmu_fail
rpi5_mmu_fail:
	ldr	x1, =rpi5_mmu_error
	str	x0, [x1]
	wfe
	b	rpi5_mmu_fail

.global rpi5_mmu_bad_entry_state
rpi5_mmu_bad_entry_state:
	/* Avoid memory accesses: with a live unknown MMU even .data may be unmapped. */
	mov	x0, #11
1:	wfe
	b	1b

.section .data.rpi5_mmu, "aw", %progbits
.balign 4096
/*
 * These pages must be PROGBITS/.data, not BSS: entry64 clears BSS only after
 * this routine returns.  Keeping the metadata adjacent lets one zeroing loop
 * make warm firmware boots deterministic.
 */
.global arm64_bpt_l3_pt0
arm64_bpt_l3_pt0:
	.space 4096
.global arm64_bpt_l2_pt0
arm64_bpt_l2_pt0:
	.space 4096
.global arm64_bpt_l2_directmap
arm64_bpt_l2_directmap:
	.space 4096
.global rpi5_mmu_range_count
rpi5_mmu_range_count:
	.quad 0
.global rpi5_mmu_ranges
rpi5_mmu_ranges:
	.space MAX_RAM_RANGES * 16
.global rpi5_mmu_error
rpi5_mmu_error:
	.quad 0

.section .rodata.rpi5_mmu, "a", %progbits
rpi5_prop_address_cells: .asciz "#address-cells"
rpi5_prop_size_cells:    .asciz "#size-cells"
rpi5_prop_device_type:   .asciz "device_type"
rpi5_prop_status:        .asciz "status"
rpi5_prop_reg:           .asciz "reg"
rpi5_value_memory:       .asciz "memory"
rpi5_value_disabled:     .ascii "disabled"
