#include <uk/boot.h>
#include <uk/intctlr.h>
#include <uk/lcpu.h>
#include <uk/plat/common/bootinfo.h>
#include <uk/plat/common/memory.h>
#include <uk/plat/memory.h>
#include <uk/print.h>

#include "pl011.h"

static int rpi5_bootinfo_reserve_null_page(struct ukplat_bootinfo *bi)
{
	/*
	 * The DTB reports RAM starting at physical address zero, so the common
	 * FDT setup initially creates a FREE region beginning at 0x0. The common
	 * memregion allocator returns the allocated physical address as a pointer;
	 * allocating from 0x0 would therefore return NULL, which callers interpret
	 * as an allocation failure even though the region was consumed.
	 *
	 * Reserve only the first page to remove that ambiguity while retaining the
	 * rest of the low RAM. This descriptor initially overlaps the start of the
	 * FREE descriptor. The common coalescer gives RESERVED regions priority and
	 * trims the FREE descriptor from [0, ...] to [__PAGE_SIZE, ...].
	 */
	const struct ukplat_memregion_desc null_page = {
		.pbase = 0,
		.vbase = 0,
		.len = __PAGE_SIZE,
		.pg_count = 1,
		.type = UKPLAT_MEMRT_RESERVED,
	};
	int rc;

	rc = ukplat_memregion_list_insert(&bi->mrds, &null_page);
	if (rc < 0)
		return rc;
	ukplat_memregion_list_coalesce(&bi->mrds);
	return 0;
}

void rpi5_ukplat_entry(void)
{
	struct ukplat_bootinfo *bi;
	int rc;

	rpi5_pl011_puts("rpi5: rpi5_ukplat_entry()\r\n");
	rpi5_pl011_console_init();
	uk_pr_info("rpi5: PL011 console registered\n");

	bi = ukplat_bootinfo_get();
	if (!bi)
	{
		rpi5_pl011_puts("rpi5: bootinfo missing\r\n");
		UK_CRASH("rpi5: bootinfo missing after DTB setup\n");
	}

	rc = rpi5_bootinfo_reserve_null_page(bi);
	if (rc)
		UK_CRASH("rpi5: could not reserve the null page: %d\n", rc);

	rc = ukplat_mem_init();
	if (rc)
		UK_CRASH("rpi5: common memory initialization failed: %d\n", rc);

	rpi5_pl011_puts("rpi5: probing interrupt controller\r\n");
	rc = uk_intctlr_probe();
	if (rc)
	{
		rpi5_pl011_puts("rpi5: interrupt controller probe failed\r\n");
		UK_CRASH("rpi5: interrupt controller probe failed: %d\n", rc);
	}

	rpi5_pl011_puts("rpi5: initializing boot CPU\r\n");
	rc = uk_lcpu_init(uk_lcpu_get_bsp());
	if (rc)
	{
		rpi5_pl011_puts("rpi5: boot CPU init failed\r\n");
		UK_CRASH("rpi5: boot CPU init failed: %d\n", rc);
	}

	rpi5_pl011_puts("rpi5: calling uk_boot_early_init()\r\n");
	uk_pr_info("rpi5: DTB bootinfo populated, entering uk_boot_entry()\n");
	uk_boot_early_init(bi);
	rpi5_pl011_puts("rpi5: calling uk_boot_entry()\r\n");
	uk_boot_entry();
}
