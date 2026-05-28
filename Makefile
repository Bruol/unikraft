TARGET_TRIPLE ?= aarch64-none-elf
CROSS_COMPILE ?= aarch64-elf-
FIRMWARE_VERSION ?= master
UK_BASE ?= $(abspath ../unikraft)
UK_MAKE ?= gmake
UK_APP := $(abspath app)
UK_PLAT := $(abspath .)
UK_BUILD_DIR := $(abspath build/unikraft)
UK_CONFIG := $(UK_APP)/.config
UK_DEFCONFIG := $(abspath configs/rpi5_defconfig)
UK_MAKE_ARGS := -C $(UK_BASE) A=$(UK_APP) P=$(UK_PLAT) O=$(UK_BUILD_DIR) C=$(UK_CONFIG) UK_CFLAGS=-std=gnu11

CC      := clang --target=$(TARGET_TRIPLE)
AS      := clang --target=$(TARGET_TRIPLE)
LD      := $(CROSS_COMPILE)ld
OBJCOPY := $(CROSS_COMPILE)objcopy
OBJDUMP := $(CROSS_COMPILE)objdump

BUILD_DIR := build
ELF      := $(BUILD_DIR)/kernel.elf
IMG      := $(BUILD_DIR)/kernel_2712.img
MAP      := $(BUILD_DIR)/kernel.map
LISTING  := $(BUILD_DIR)/kernel.lst
SRCS     := $(shell find src -type f \( -name '*.c' -o -name '*.S' \) | sort)
OBJECTS  := $(patsubst src/%,$(BUILD_DIR)/%.o,$(SRCS))
DEPS     := $(OBJECTS:.o=.d)
FIRMWARE_BASE_URL := https://raw.githubusercontent.com/raspberrypi/firmware/$(FIRMWARE_VERSION)/boot
BOOT_STAGING := $(BUILD_DIR)/bootfs
FIRMWARE_DIR := $(BUILD_DIR)/firmware
IMAGE_MOUNT := $(BUILD_DIR)/mnt
BOOT_IMAGE := $(BUILD_DIR)/rpi5-boot.img
BOOT_IMAGE_TMP := $(BOOT_IMAGE).dmg
BOOT_IMAGE_SIZE_MB ?= 64
CONFIG_TXT := $(BOOT_STAGING)/config.txt
BOOT_FILES := $(FIRMWARE_DIR)/start4.elf $(FIRMWARE_DIR)/fixup4.dat $(FIRMWARE_DIR)/bcm2712-rpi-5-b.dtb

CFLAGS  := -Wall -Wextra -ffreestanding -fno-builtin -fno-stack-protector -fno-pic -mgeneral-regs-only -O0 -g -MMD -MP
ASFLAGS := -g -MMD -MP
LDFLAGS := -T linker.ld -Map $(MAP)

.PHONY: all baremetal unikraft-build-dir unikraft-config unikraft clean disasm firmware bootfs usb-image flash-usb flash-baremetal

all: unikraft

baremetal: $(IMG) $(LISTING)

unikraft-build-dir:
	mkdir -p $(UK_BUILD_DIR)

unikraft-config: unikraft-build-dir
	$(UK_MAKE) $(UK_MAKE_ARGS) DEFCONFIG=$(UK_DEFCONFIG) defconfig

unikraft: unikraft-config
	$(UK_MAKE) $(UK_MAKE_ARGS)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(BUILD_DIR)/%.S.o: src/%.S | $(BUILD_DIR)
	mkdir -p $(dir $@)
	$(AS) $(ASFLAGS) -c -o $@ $<

$(BUILD_DIR)/%.c.o: src/%.c | $(BUILD_DIR)
	mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c -o $@ $<

$(ELF): $(OBJECTS) linker.ld
	$(LD) $(LDFLAGS) -o $@ $(OBJECTS)

$(IMG): $(ELF)
	$(OBJCOPY) -O binary $< $@

$(LISTING): $(ELF)
	$(OBJDUMP) -d $< > $@

disasm: $(LISTING)

clean:
	rm -rf $(BUILD_DIR) $(UK_CONFIG)

flash-usb: unikraft
	./scripts/flash_rpi5_usb.sh --kernel $(UK_BUILD_DIR)/kernel_2712.img --device $(DEVICE)

flash-baremetal: $(IMG)
	./scripts/flash_rpi5_usb.sh --kernel $(IMG) --device $(DEVICE)

-include $(DEPS)
