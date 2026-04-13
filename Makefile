TARGET_TRIPLE ?= aarch64-none-elf
CROSS_COMPILE ?= aarch64-elf-
FIRMWARE_VERSION ?= master

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
OBJECTS  := $(BUILD_DIR)/start.o $(BUILD_DIR)/kernel.o
FIRMWARE_BASE_URL := https://raw.githubusercontent.com/raspberrypi/firmware/$(FIRMWARE_VERSION)/boot
BOOT_STAGING := $(BUILD_DIR)/bootfs
FIRMWARE_DIR := $(BUILD_DIR)/firmware
IMAGE_MOUNT := $(BUILD_DIR)/mnt
BOOT_IMAGE := $(BUILD_DIR)/rpi5-boot.img
BOOT_IMAGE_TMP := $(BOOT_IMAGE).dmg
BOOT_IMAGE_SIZE_MB ?= 64
CONFIG_TXT := $(BOOT_STAGING)/config.txt
BOOT_FILES := $(FIRMWARE_DIR)/start4.elf $(FIRMWARE_DIR)/fixup4.dat $(FIRMWARE_DIR)/bcm2712-rpi-5-b.dtb

CFLAGS  := -Wall -Wextra -ffreestanding -fno-builtin -fno-stack-protector -fno-pic -mgeneral-regs-only -O0 -g
ASFLAGS := -g
LDFLAGS := -T linker.ld -Map $(MAP)

.PHONY: all clean disasm firmware bootfs usb-image

all: $(IMG) $(LISTING)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(BUILD_DIR)/start.o: src/start.S | $(BUILD_DIR)
	$(AS) $(ASFLAGS) -c -o $@ $<

$(BUILD_DIR)/kernel.o: src/kernel.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) -c -o $@ $<

$(ELF): $(OBJECTS) linker.ld
	$(LD) $(LDFLAGS) -o $@ $(OBJECTS)

$(IMG): $(ELF)
	$(OBJCOPY) -O binary $< $@

$(LISTING): $(ELF)
	$(OBJDUMP) -d $< > $@

disasm: $(LISTING)

clean:
	rm -rf $(BUILD_DIR)
