/* SPDX-License-Identifier: BSD-3-Clause */
/* Copyright (c) 2022, Unikraft GmbH and The Unikraft Authors.
 * Copyright (c) 2026, Lorin Urbantat.
 * Licensed under the BSD-3-Clause License (the "License").
 * You may not use this file except in compliance with the License.
 */

#include <uk/plat/common/bootinfo.h>

#define RPI5_MEMRF_UNMAP 0x0010

struct ukplat_memregion_desc bpt_unmap_mrd = {
	.pbase = 0,
	.vbase = 0,
	.pg_off = 0,
	/* All valid DT RAM must remain below the fixed 64-GiB device aperture. */
	.len = 0x1000000000UL,
	.pg_count = 0x1000000UL,
	.type = 0,
	.flags = RPI5_MEMRF_UNMAP,
};

int _ukplat_mem_mappings_init(void)
{
	/*
	 * The common memory code calls this hook after installing the platform
	 * allocator so platforms can create mappings that require allocations.
	 * RPi 5 has no such deferred mappings: rpi5_start_mmu() builds the
	 * complete bootstrap RAM and Device identity map before entering C.
	 * Therefore there is nothing to allocate or map at this stage.
	 */
	return 0;
}
