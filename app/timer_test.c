#include <stdio.h>

#include <uk/arch/time.h>
#include <uk/plat/time.h>
#include <uk/sched.h>

#define TIMER_TEST_ITERATIONS 1000U
#define TIMER_TEST_INTERVAL_NS ukarch_time_msec_to_nsec(10)

int main(void)
{
	__nsec before;
	__nsec after;
	unsigned int i;

	before = ukplat_monotonic_clock();
	after = ukplat_monotonic_clock();
	if (after < before) {
		printf("rpi5-timer-test: counter regressed\n");
		return 1;
	}

	printf("rpi5-timer-test: running %u sequential 10 ms sleeps\n",
	       TIMER_TEST_ITERATIONS);
	for (i = 0; i < TIMER_TEST_ITERATIONS; i++) {
		before = ukplat_monotonic_clock();
		uk_sched_thread_sleep(TIMER_TEST_INTERVAL_NS);
		after = ukplat_monotonic_clock();
		if (after < before || after - before < TIMER_TEST_INTERVAL_NS) {
			printf("rpi5-timer-test: early/regressed wake at %u "
			       "(%llu ns)\n", i,
			       (unsigned long long)(after - before));
			return 1;
		}
		if ((i + 1U) % 100U == 0U)
			printf("rpi5-timer-test: completed %u sleeps\n", i + 1U);
	}

	printf("rpi5-timer-test: PASS\n");
	return 0;
}
