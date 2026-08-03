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

## Timer and interrupt support

The Pi 5 firmware DTB describes a GIC-400 compatible interrupt controller and
an ARMv8 architectural timer. The platform selects Unikraft's GICv2 driver,
probes it before boot-CPU initialization, and uses the non-secure physical
timer registers (`CNTPCT_EL0`, `CNTP_CVAL_EL0`, and `CNTP_CTL_EL0`). From the
timer node it translates interrupt tuple 1, the physical-timer PPI, into a GIC
INTID and registers the timer handler.

During a scheduler sleep, the platform programs the absolute timer deadline,
unmasks its interrupt, and enters `wfi`. The interrupt wakes the CPU and is
masked again until the next sleep, preventing interrupt storms. The
platform-owned adaptations in `ukplat/time.c` and `ukplat/generic_timer.c`
avoid changes to `../unikraft`; hardware validation completed 1,000 sequential
10 ms sleeps without early wake-ups or interrupt storms.

## Debugging:

connect the UART port on the raspi to the D port on the probe and run this command to start openocd

```bash
sudo openocd --file debug_cfg/cmsis-dap.cfg --file debug_cfg/openocd_raspi5.cfg
```

to connect gdb and upload a new kernel run:

```bash
make && gdb -q -x debug_cfg/ConnectJTAG.gdb
```

The script's `rpi5_reload` command is safe to repeat after a kernel has enabled
the MMU and caches. It executes the resident trampoline at `0x200000` and
stops at the fixed reload-ABI park at `0x200400`, which
cleans and invalidates data caches by set/way, invalidates I-cache and TLBs,
disables `SCTLR_EL1.M/C/I` while executing in the identity map, and parks for
GDB. The script permits a missing resident signature only for a cold EL2
firmware halt; a warm EL1 target without the signature is rejected.

The link fails if the image exceeds the reserved `[0x80000,0x300000)` reload
range, and `rpi5_reload` rejects a DTB larger than its reserved `0x14000` bytes
before changing target state.

For consecutive-cycle validation, run the command above, `continue` to normal
shutdown, quit GDB, and repeat without power cycling. Each warm attach prints
`Normalizing target through the resident reload trampoline.` before loading
the ELF; failure to reach the cache-off park aborts the load.


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
