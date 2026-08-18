/* SPDX-License-Identifier: BSD-3-Clause */

#include <errno.h>
#include <stdbool.h>
#include <uk/spinlock.h>
#include <uk/print.h>
#include "pl011.h"
#include "rpi5_gpio.h"

#define RP1_GPIO_COUNT 28U
#define RP1_FUNCSEL_GPIO 5U
#define RP1_SET_OFFSET 0x2000U
#define RP1_CLR_OFFSET 0x3000U
#define RP1_GPIO_CTRL 0x0004U
#define RP1_GPIO_CTRL_FUNCSEL_MASK 0x0000001fU
#define RP1_GPIO_CTRL_OUTOVER_MASK 0x00003000U
#define RP1_GPIO_CTRL_OEOVER_MASK 0x0000c000U
#define RP1_RIO_OUT 0x0000U
#define RP1_RIO_OE 0x0004U
#define RP1_RIO_IN 0x0008U
#define RP1_PAD_BASE 0x0004U
#define RP1_PAD_PULL_SHIFT 2U
#define RP1_PAD_PULL_MASK (0x3U << RP1_PAD_PULL_SHIFT)
#define RP1_PAD_IN_ENABLE (1U << 6)
#define RP1_PAD_OUT_DISABLE (1U << 7)

#define RP1_GPIO_REGION 0x000d0000U
#define RP1_RIO_REGION 0x000e0000U
#define RP1_PADS_REGION 0x000f0000U
#define RP1_GPIO_BASE \
	((volatile __u8 *)(__uptr)(RPI5_MMIO_BASE + RP1_GPIO_REGION))
#define RP1_RIO_BASE \
	((volatile __u8 *)(__uptr)(RPI5_MMIO_BASE + RP1_RIO_REGION))
#define RP1_PADS_BASE \
	((volatile __u8 *)(__uptr)(RPI5_MMIO_BASE + RP1_PADS_REGION))

struct rpi5_gpio_state {
	struct uk_spinlock lock;
	bool ready;
};

static struct rpi5_gpio_state rpi5_gpio;

static inline __u32 rpi5_read(volatile __u8 *base, __u32 offset)
{
	__u32 value = *(volatile __u32 *)(base + offset);
	__atomic_thread_fence(__ATOMIC_SEQ_CST);
	return value;
}

static inline void rpi5_write(volatile __u8 *base, __u32 offset, __u32 value)
{
	__atomic_thread_fence(__ATOMIC_SEQ_CST);
	*(volatile __u32 *)(base + offset) = value;
	__atomic_thread_fence(__ATOMIC_SEQ_CST);
}

static int rpi5_gpio_check(unsigned int gpio)
{
	if (!rpi5_gpio.ready)
		return -ENODEV;
	return gpio < RP1_GPIO_COUNT ? 0 : -EINVAL;
}

static void rpi5_gpio_select_gpio(unsigned int gpio)
{
	const __u32 offset = gpio * 8 + RP1_GPIO_CTRL;
	__u32 ctrl = rpi5_read(RP1_GPIO_BASE, offset);

	ctrl &= ~(RP1_GPIO_CTRL_FUNCSEL_MASK | RP1_GPIO_CTRL_OUTOVER_MASK |
		  RP1_GPIO_CTRL_OEOVER_MASK);
	ctrl |= RP1_FUNCSEL_GPIO;
	rpi5_write(RP1_GPIO_BASE, offset, ctrl);
}

int rpi5_gpio_init(void)
{
	rpi5_gpio.ready = true;
	ukarch_spin_init(&rpi5_gpio.lock);
	uk_pr_info("rpi5: RP1 GPIO using fixed firmware BAR\n");
	return 0;
}

int rpi5_gpio_direction(unsigned int gpio, enum rpi5_gpio_direction direction)
{
	int rc = rpi5_gpio_check(gpio);
	if (rc)
		return rc;
	if (direction > RPI5_GPIO_DIRECTION_OUTPUT)
		return -EINVAL;
	ukarch_spin_lock(&rpi5_gpio.lock);
	if (direction == RPI5_GPIO_DIRECTION_INPUT) {
		rpi5_write(RP1_RIO_BASE, RP1_RIO_OE + RP1_CLR_OFFSET,
			   1U << gpio);
		rpi5_write(RP1_PADS_BASE, RP1_PAD_BASE + gpio * 4,
			   rpi5_read(RP1_PADS_BASE, RP1_PAD_BASE + gpio * 4) |
			       RP1_PAD_IN_ENABLE | RP1_PAD_OUT_DISABLE);
	} else {
		rpi5_write(RP1_RIO_BASE, RP1_RIO_OE + RP1_SET_OFFSET,
			   1U << gpio);
		rpi5_write(RP1_PADS_BASE, RP1_PAD_BASE + gpio * 4,
			   (rpi5_read(RP1_PADS_BASE, RP1_PAD_BASE + gpio * 4) |
			    RP1_PAD_IN_ENABLE) &
			       ~RP1_PAD_OUT_DISABLE);
	}
	rpi5_gpio_select_gpio(gpio);
	ukarch_spin_unlock(&rpi5_gpio.lock);
	return 0;
}

int rpi5_gpio_get(unsigned int gpio, bool *value)
{
	int rc = rpi5_gpio_check(gpio);
	if (rc)
		return rc;
	if (!value)
		return -EINVAL;
	*value = !!(rpi5_read(RP1_RIO_BASE, RP1_RIO_IN) & (1U << gpio));
	return 0;
}

int rpi5_gpio_set(unsigned int gpio, bool value)
{
	int rc = rpi5_gpio_check(gpio);
	if (rc)
		return rc;
	ukarch_spin_lock(&rpi5_gpio.lock);
	rpi5_write(RP1_RIO_BASE,
		   RP1_RIO_OUT + (value ? RP1_SET_OFFSET : RP1_CLR_OFFSET),
		   1U << gpio);
	ukarch_spin_unlock(&rpi5_gpio.lock);
	return 0;
}

int rpi5_gpio_set_pull(unsigned int gpio, enum rpi5_gpio_pull pull)
{
	__u32 value;
	int rc = rpi5_gpio_check(gpio);
	if (rc || pull > RPI5_GPIO_PULL_UP)
		return rc ? rc : -EINVAL;
	ukarch_spin_lock(&rpi5_gpio.lock);
	value = rpi5_read(RP1_PADS_BASE, RP1_PAD_BASE + gpio * 4) &
		~RP1_PAD_PULL_MASK;
	value |= (__u32)pull << RP1_PAD_PULL_SHIFT;
	rpi5_write(RP1_PADS_BASE, RP1_PAD_BASE + gpio * 4, value);
	ukarch_spin_unlock(&rpi5_gpio.lock);
	return 0;
}
