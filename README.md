# plat-raspi5

This repo is intended to add rapberry pi 5 platform support to the [unikraft project](https://github.com/unikraft/unikraft)

## Things to write a tutorial about:

- connecting both uart and swd at the same time
- updating firmware over swd/openocd



## Flashing:

build the kernel:

```bash
make
```

flash a USB stick with:

```bash
make flash-usb DEVICE=/dev/disk4
```

or run the script directly:

```bash
./scripts/flash_rpi5_usb.sh --kernel build/kernel_2712.img --device /dev/disk4
```

this erases the target disk, so pass the whole USB device, not a partition.

you can also pass `build/kernel.elf` and the script will convert it automatically.

## Debugging:

connect the UART port on the raspi to the D port on the probe and run this command to start openocd

```bash
sudo openocd --file debug_cfg/cmsis-dap.cfg --file debug_cfg/openocd_raspi5.cfg
```

to connect gdb run:

```bash
make && gdb -q -ex 'set confirm off' -ex 'target extended-remote :3333' -ex 'file build/kernel.elf' -ex 'load' -ex 'tbreak src/start.S:19' -ex 'continue' -ex 'set $x0 = 0' -ex 'break kernel_main'
```

then run in gdb

```gdb
set $x0 = 0 
continue
```


## uart:
observe raspi usart using note the device name may be different on your system, check with `ls /dev/cu.*` and look for something like `cu.usbmodem102` or `cu.usbserial-0001`

```bash
tio /dev/cu.usbmodem102 -b 115200         
```

## Resources:



something that works extreamly well is setting up tmux with gdb and tio side by side and then giving coding agent access to tmux session and giving it an objective. this way it can iterate, test new code by running `make` in the tmux session, and then observe the results in gdb and tio to  verify if the changes had the intended effect. this works because of the ability to load new kernels using gdb's `load` command. Note you have to load the dtb into memory and set `x0` to its address before hitting the kernel entry point, otherwise the kernel will panic when it tries to parse the dtb. You can automate this in gdb with a helper script that you `source` after connecting, which sets up a breakpoint at the entry point, and then in the breakpoint handler it loads the dtb, sets `x0`, and continues.



- https://macoy.me/blog/programming/RaspberryPi5Debugging
- https://github.com/rsta2/circle
- https://github.com/Utsav-Agarwal/HobOS/
- https://main.lv/writeup/raspberry5_baremetal_uart.md


# write differences in rpi3 plat vs arm and why is the rpi5 implementation closer to arm then to rpi3
- in plat-raspi most values are hardcoded. DTB is not saved and ukplat_entry is called with empty args
- kvm/arm is far more general, has PIE and relocation logic. on raspi the firmware always loads the kernel at a set address so no relocation is needed. 
- uart is handled differntly in rpi3 platform. On rp1 you have to set up GPIO muxing for UART and configure much of the UART device such as baud rate etc. On rpi5 much of this is done by the firmware on the rp1.
- Also there are some differences in the mailbox interface between rpi3 and rpi5. 1) there are separate mailboxes for soc firmware and rp1. 2) fewer tags/properties work on rpi5 firmware.

