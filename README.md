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


## Resources:

- https://macoy.me/blog/programming/RaspberryPi5Debugging
- https://github.com/rsta2/circle
- https://github.com/Utsav-Agarwal/HobOS/
- https://main.lv/writeup/raspberry5_baremetal_uart.md