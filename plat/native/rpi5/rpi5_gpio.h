/* SPDX-License-Identifier: BSD-3-Clause */

#ifndef __RPI5_GPIO_H__
#define __RPI5_GPIO_H__

#include <stdbool.h>

enum rpi5_gpio_pull {
	RPI5_GPIO_PULL_NONE = 0,
	RPI5_GPIO_PULL_DOWN,
	RPI5_GPIO_PULL_UP,
};

enum rpi5_gpio_direction {
	RPI5_GPIO_DIRECTION_INPUT = 0,
	RPI5_GPIO_DIRECTION_OUTPUT,
};

int rpi5_gpio_init(void);
int rpi5_gpio_direction(unsigned int gpio,
			 enum rpi5_gpio_direction direction);
int rpi5_gpio_get(unsigned int gpio, bool *value);
int rpi5_gpio_set(unsigned int gpio, bool value);
int rpi5_gpio_set_pull(unsigned int gpio, enum rpi5_gpio_pull pull);

#endif /* __RPI5_GPIO_H__ */
