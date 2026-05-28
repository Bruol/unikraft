FIRMWARE_VERSION ?= master
UK_BASE ?= $(abspath ../unikraft)
UK_MAKE ?= gmake
UK_APP := $(abspath app)
UK_PLAT := $(abspath .)
UK_BUILD_DIR := $(abspath build/unikraft)
UK_CONFIG := $(UK_APP)/.config
UK_DEFCONFIG := $(abspath configs/rpi5_defconfig)
UK_MAKE_ARGS := -C $(UK_BASE) A=$(UK_APP) P=$(UK_PLAT) O=$(UK_BUILD_DIR) C=$(UK_CONFIG) UK_CFLAGS=-std=gnu11

BUILD_DIR := build
FIRMWARE_BASE_URL := https://raw.githubusercontent.com/raspberrypi/firmware/$(FIRMWARE_VERSION)/boot
BOOT_STAGING := $(BUILD_DIR)/bootfs
FIRMWARE_DIR := $(BUILD_DIR)/firmware
IMAGE_MOUNT := $(BUILD_DIR)/mnt
BOOT_IMAGE := $(BUILD_DIR)/rpi5-boot.img
BOOT_IMAGE_TMP := $(BOOT_IMAGE).dmg
BOOT_IMAGE_SIZE_MB ?= 64
CONFIG_TXT := $(BOOT_STAGING)/config.txt
BOOT_FILES := $(FIRMWARE_DIR)/start4.elf $(FIRMWARE_DIR)/fixup4.dat $(FIRMWARE_DIR)/bcm2712-rpi-5-b.dtb

.PHONY: all unikraft-build-dir unikraft-config unikraft clean firmware bootfs usb-image flash-usb

all: unikraft

unikraft-build-dir:
	mkdir -p $(UK_BUILD_DIR)

unikraft-config: unikraft-build-dir
	$(UK_MAKE) $(UK_MAKE_ARGS) DEFCONFIG=$(UK_DEFCONFIG) defconfig

unikraft: unikraft-config
	$(UK_MAKE) $(UK_MAKE_ARGS)

clean:
	rm -rf $(BUILD_DIR) $(UK_CONFIG)

flash-usb: unikraft
	./scripts/flash_rpi5_usb.sh --kernel $(UK_BUILD_DIR)/kernel_2712.img --device $(DEVICE)
