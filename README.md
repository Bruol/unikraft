# plat-raspi5

This repo is intended to add rapberry pi 5 platform support to the [unikraft project](https://github.com/unikraft/unikraft)


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
gdb --command=debug_cfg/ConnectJTAG.gdb build/kernel.elf
```
