/* SPDX-License-Identifier: BSD-3-Clause */
/* Copyright (c) 2022, Unikraft GmbH and The Unikraft Authors.
 * Copyright (c) 2026, Lorin Urbantat.
 * Licensed under the BSD-3-Clause License (the "License").
 * You may not use this file except in compliance with the License.
 */

#include <uk/plat/common/bootinfo.h>
#if CONFIG_LIBUKPAGING
#include <uk/paging.h>
#include <uk/plat/native/page.h>
#endif

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

#if CONFIG_LIBUKPAGING
int rpi5_paging_remap_device_memory(void)
{
	struct ukplat_memregion_desc *mrd;
	struct uk_pagetable *pt = uk_paging_pt_get_active();
	const unsigned long attr = UK_PAGING_PAGE_ATTR_PROT_RW |
		UK_PLAT_NATIVE_PAGE_ATTR_TYPE_DEVICE_nGnRnE;
	int rc;

	ukplat_memregion_foreach(&mrd, UKPLAT_MEMRT_DEVICE, 0, 0) {
		/*
		 * ARM64's generic attribute replacement retains template memory
		 * type bits. Recreate these mappings locally so Device-nGnRnE
		 * replaces the initial Normal-WB type without changing other
		 * platforms.
		 */
		rc = uk_paging_page_unmap(pt, mrd->vbase, mrd->pg_count,
					  UK_PAGING_PAGE_FLAG_KEEP_FRAMES);
		if (unlikely(rc))
			return rc;
		rc = uk_paging_page_map(pt, mrd->vbase, mrd->pbase,
					mrd->pg_count, attr, 0);
		if (unlikely(rc))
			return rc;
	}
	return 0;
}
#endif
