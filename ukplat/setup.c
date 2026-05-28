#include <uk/boot.h>
#include <uk/intctlr.h>
#include <uk/lcpu.h>
#include <uk/plat/common/bootinfo.h>
#include <uk/plat/common/memory.h>
#include <uk/print.h>

#include "pl011.h"

static void rpi5_bootinfo_drop_null_free_region(struct ukplat_bootinfo *bi)
{
	struct ukplat_memregion_desc *mrd;
	__u32 i;

	for (i = 0; i < bi->mrds.count; i++)
	{
		mrd = &bi->mrds.mrds[i];
		if (mrd->type == UKPLAT_MEMRT_FREE && mrd->vbase == 0)
		{
			rpi5_pl011_puts("rpi5: dropping low free memory region at 0x0\r\n");
			ukplat_memregion_list_delete(&bi->mrds, i);
			i--;
		}
	}
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

	rpi5_bootinfo_drop_null_free_region(bi);

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
