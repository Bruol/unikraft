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
	.len = 0x2000000000UL,
	.pg_count = 0x2000000UL,
	.type = 0,
	.flags = RPI5_MEMRF_UNMAP,
};

int _ukplat_mem_mappings_init(void)
{
	return 0;
}
