# Raspberry Pi 5

This platform builds a fixed-address ARM64 Unikraft image for Raspberry Pi 5
firmware boot. Applications remain external to the kernel tree; the default
development workflow uses the official catalog's `native/helloworld-c` app.

## Build

Clone the catalog beside the Unikraft checkout, then use the platform wrapper:

```sh
git clone https://github.com/unikraft/catalog.git ../catalog
make -f Makefile.rpi5 configure
make -f Makefile.rpi5 verify
```

Set explicit locations if needed:

```sh
make -f Makefile.rpi5 \
  UK_BASE="$PWD" \
  UK_APP=/path/to/catalog/native/helloworld-c \
  verify
```

Outputs are deterministic under `build/rpi5`:

- `kernel_2712.img`: Raspberry Pi firmware image
- `kernel_2712.dbg`: debug ELF used by the GDB helper
- `*_rpi5-arm64.sym`: ordered symbol map
- `compile_commands.json`: compilation database

The linker rejects an image larger than the reserved `[0x80000,0x300000)`
warm-reload range.

## Flash

Pass a whole USB device, not a partition. This erases the selected device:

```sh
make -f Makefile.rpi5 flash-usb DEVICE=/dev/disk4
```

## UART and GDB

Observe UART output at 115200 baud, for example:

```sh
tio /dev/cu.usbmodem102 -b 115200
```

Start OpenOCD:

```sh
sudo openocd --file debug_cfg/cmsis-dap.cfg \
  --file debug_cfg/openocd_raspi5.cfg
```

Build and connect GDB in another terminal:

```sh
make -f Makefile.rpi5 && gdb -q -x debug_cfg/ConnectJTAG.gdb
```

The `rpi5_reload` command uses the resident trampoline at `0x200000`, reaches
the cache/MMU-off park at `0x200400`, and reloads the debug ELF and DTB without
a power cycle. It rejects oversized DTBs before changing target state.

## Hardware behavior

The firmware DTB supplies memory ranges, GIC-400 data, and ARM architectural
timer data. The platform discovers enabled RAM tuples, preserves reservations
and holes, initializes GICv2, and uses the non-secure physical timer registers
and timer interrupt tuple 1.

Historical hardware validation covered split-bank 4 GiB memory, 1,000
sequential 10 ms sleeps, and repeated warm GDB reloads. Repeat those checks
with external test applications after changing memory, interrupt, timer, MMU,
or reload code.
