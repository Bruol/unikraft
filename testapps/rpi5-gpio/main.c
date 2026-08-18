/* SPDX-License-Identifier: BSD-3-Clause */

#include <stdbool.h>
#include <uk/plat/time.h>
#include <uk/print.h>
#include <uk/sched.h>

#include "rpi5_gpio.h"

#define GPIO_TEST_PIN 23U
#define NSEC_PER_MSEC 1000000ULL

static void wait_msec(__u64 msec)
{
	const __nsec deadline = ukplat_monotonic_clock() + msec * NSEC_PER_MSEC;

	while (ukplat_monotonic_clock() < deadline)
		uk_sched_yield();
}

int main(void)
{
	int rc;

	rc = rpi5_gpio_direction(GPIO_TEST_PIN, RPI5_GPIO_DIRECTION_OUTPUT);
	if (rc)
		return rc;
	rc = rpi5_gpio_set(GPIO_TEST_PIN, false);
	if (rc)
		return rc;
	uk_pr_info("rpi5-gpio-test: GPIO %u LOW\n", GPIO_TEST_PIN);
	wait_msec(50);

	for (int i = 0; i <= 10; i++) {

		rc = rpi5_gpio_set(GPIO_TEST_PIN, true);
		if (rc)
			return rc;
		uk_pr_info("rpi5-gpio-test: GPIO %u HIGH\n", GPIO_TEST_PIN);
		wait_msec(2000);

		rc = rpi5_gpio_set(GPIO_TEST_PIN, false);
		if (rc)
			return rc;
		uk_pr_info("rpi5-gpio-test: GPIO %u LOW again\n",
			   GPIO_TEST_PIN);
		wait_msec(2000);
	}
}
