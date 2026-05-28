#include <uk/arch/types.h>
#include <uk/plat/time.h>
#include <uk/plat/common/_time.h>

unsigned long sched_have_pending_events;

void ukplat_time_init(void)
{
}

__u32 ukplat_time_get_irq(void)
{
	return 0;
}

__nsec ukplat_monotonic_clock(void)
{
	return 0;
}

void time_block_until(__snsec until)
{
	(void)until;
}
