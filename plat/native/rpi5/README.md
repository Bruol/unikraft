# Raspberry Pi 5

This platform boots a single-core AArch64 Unikraft application directly from
Raspberry Pi 5 firmware. It supports a polling UART console, DT-based RAM
allocation, GICv2 interrupts, the physical architectural timer, managed paging,
and basic RP1 GPIO. See [Platform docs](platform-docs.md) for the design,
hardware assumptions, evaluation results, and limitations.

## Build and boot

Run commands from the repository root. Install GNU Make, an AArch64 ELF GCC
cross-toolchain, and Unikraft's normal build dependencies. On macOS, GNU Make
is usually named `gmake`; on Linux, pass `UK_MAKE=make` if needed. Select your
installed toolchain with `CROSS_COMPILE`, for example `aarch64-elf-`.

The included C smoke test needs no separate application checkout:

```sh
make -f Makefile.rpi5 verify -j4 \
  UK_APP="$PWD/testapps/hello-world" CROSS_COMPILE=aarch64-elf-
```

Without `UK_APP`, the wrapper uses `../catalog/native/helloworld-c` from a
sibling checkout of the Unikraft catalog. Any compatible external application
can be selected by its absolute path.

The build creates `build/rpi5/kernel_2712.img`, its debug ELF
`build/rpi5/kernel_2712.dbg`, an application symbol map, and
`build/rpi5/compile_commands.json`. The default configuration enables managed
paging and boots without waiting for a debugger.

To build the fixed bootstrap-map fallback:

```sh
make -f Makefile.rpi5 verify -j4 \
  UK_APP="$PWD/testapps/hello-world" \
  UK_DEFCONFIG="$PWD/rpi5_config/rpi5_nopaging_defconfig"
```

Use the flash helper to install the kernel and firmware on a USB disk. The
command erases the whole selected disk and asks for confirmation. Replace
`/dev/diskN` with the actual removable disk, or `/dev/sdX` on Linux:

```sh
make -f Makefile.rpi5 flash-usb \
  UK_APP="$PWD/testapps/hello-world" DEVICE=/dev/diskN
```

The helper downloads firmware from `raspberrypi/firmware`. Set
`FIRMWARE_VERSION` to a specific firmware commit for a reproducible image;
the default is `master`. Its boot configuration is [config.txt](config.txt).
The board's EEPROM boot order must permit USB boot.

Connect the Pi's GPIO14 TX to the serial adapter's RX, GPIO15 RX to its TX,
and a common ground. These are 3.3 V signals. Observe the console at
115200 baud, substituting the host's serial-device name:

```sh
tio /dev/cu.usbmodem102 -b 115200
```

A successful smoke test prints `Hello, World!` and returns zero.

## Hardware evaluation applications

Build each application by selecting its directory with `UK_APP`. These are
hardware tests; a successful build alone does not execute them.

| Application | Expected behavior |
| --- | --- |
| `testapps/hello-world` | Prints `Hello, World!` and returns zero. |
| `testapps/hello-world-cpp` | Exercises C++ compilation and C console linkage. |
| `testapps/eval-timer` | Completes 1,000 sleeps of 10 ms without early wake-ups or clock regression. |
| `testapps/eval-mem` | Allocates and verifies at least 4,075 MiB on the tested 4 GiB board. |
| `testapps/dynamic-paging` | Maps, protects, translates, and unmaps a page at 2 TiB. |
| `testapps/rpi5-gpio` | Toggles GPIO23 ten times, holding each level for two seconds. |

The default defconfig already enables paging and no-fault access for the
paging test. No application-specific defconfig is required:

```sh
make -f Makefile.rpi5 verify -j4 UK_APP="$PWD/testapps/dynamic-paging"
```

The memory test's capacity threshold is specific to the evaluated board and
image size. A failure to reach it does not by itself prove memory corruption.
For the GPIO test, connect an LED through a suitable series resistor between
GPIO23 and ground.

## UART, GDB, and warm reload

Use the separate debug defconfig to enable the early spin loop and resident
reload trampoline:

```sh
make -f Makefile.rpi5 verify -j4 \
  UK_APP="$PWD/testapps/hello-world" \
  UK_DEFCONFIG="$PWD/rpi5_config/rpi5_debug_defconfig"
```

Flash this configuration once using the same `UK_APP` and `UK_DEFCONFIG`
arguments. The debug image waits before MMU initialization. Connect a
CMSIS-DAP probe to the Pi debug port and start OpenOCD in another terminal:

```sh
openocd --file debug_cfg/cmsis-dap.cfg --file debug_cfg/openocd_raspi5.cfg
```

The reload helper needs a firmware-patched DTB captured from the target board
at `debug_cfg/bcm2712-rpi-5-b.dtb`. This is a local artifact, not a portable
board description bundled with the source. Capture it after a cold boot of
the debug image, while stopped in the early spin loop, using GDB with Python:

```sh
gdb -q build/rpi5/kernel_2712.dbg
```

```gdb
target extended-remote :3333
monitor halt
# Verify that the boot CPU is in the early spin loop before using x20.
x/4i $pc
python
import pathlib
import gdb
addr = int(gdb.parse_and_eval("$x20"))
inferior = gdb.selected_inferior()
header = bytes(inferior.read_memory(addr, 8))
if header[:4] != b"\xd0\x0d\xfe\xed":
    raise gdb.GdbError("x20 does not point to an FDT")
size = int.from_bytes(header[4:8], "big")
if not 40 <= size <= 0x14000:
    raise gdb.GdbError("DTB does not fit the reload reservation")
pathlib.Path("debug_cfg/bcm2712-rpi-5-b.dtb").write_bytes(
    bytes(inferior.read_memory(addr, size)))
end
detach
quit
```

After capture, and for subsequent sessions, start with:

```sh
gdb -q -x debug_cfg/ConnectJTAG.gdb
```

Run `continue` after loading. Rebuild with the debug defconfig for each warm
reload. The helper runs the old image's resident trampoline before loading
the replacement ELF and DTB. It rejects a warm target without the trampoline.
A normal, non-debug image requires a cold boot before this workflow can be
used again. The debug linker reserves the trampoline at `0x200000`, the park
at `0x200400`, and limits the image to the range ending at `0x300000`.
