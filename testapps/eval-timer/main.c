/* SPDX-License-Identifier: BSD-3-Clause */

#include <stdio.h>
#include <uk/arch/time.h>
#include <uk/plat/time.h>
#include <uk/sched.h>

#define ITERATIONS 1000U
#define INTERVAL_NS ukarch_time_msec_to_nsec(10)

int main(void)
{
	unsigned int i;

	for (i = 0; i < ITERATIONS; i++) {
		const __nsec before = ukplat_monotonic_clock();
		__nsec after;

		uk_sched_thread_sleep(INTERVAL_NS);
		after = ukplat_monotonic_clock();
		if (after < before || after - before < INTERVAL_NS) {
			printf("rpi5-timer-test: FAIL at %u\n", i);
			return 1;
		}
	}

	puts("rpi5-timer-test: PASS (1000 x 10 ms)");
	return 0;
}
