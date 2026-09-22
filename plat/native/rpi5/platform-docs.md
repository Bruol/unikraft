# Platform docs

This document condenses Lorin Urbantat's Raspberry Pi 5 platform report into
an implementation reference. It describes the current source and separates
the report's hardware results from functionality that remains untested.
Build, flashing, and debugging commands are in the [platform README](README.md).

## Scope and firmware contract

The platform runs Unikraft directly on the Raspberry Pi 5's BCM2712 using one
AArch64 core. Firmware loads the raw image at physical address `0x80000` and
passes the flattened device tree address in `x0`. The image is linked at that
address; entry checks it, and the build rejects static PIE.

The implementation reuses Unikraft's boot, allocator, console, FDT, GICv2,
and native paging interfaces. It follows the common Arm boot structure more
closely than the older external Raspberry Pi 3 platform. The Pi 5 needs a
different peripheral path because its UART and header GPIO reside in RP1,
a PCIe endpoint configured by the firmware.

The boot configuration enables AArch64 execution, RP1 UART, and the debug
interface. `pciex4_reset=0` preserves the firmware's internal PCIe setup.
The platform assumes RP1 is accessible at CPU address `0x1c00000000`; it does
not enumerate PCIe, configure the root complex, or repair the firmware BAR.
The UART clock, baud divisors, and pin routing also come from firmware.

## Boot sequence

1. `entry64.S` preserves the DTB pointer. Entry from EL2 configures EL1 access
   to the physical counter and timer and returns to EL1.
2. Entry checks the load address, installs the exception vector table, and
   parks secondary cores. A debug build can stop in an early spin loop.
3. The boot CPU selects a 4 KiB stack and calls `rpi5_start_mmu`. A small
   assembly FDT parser constructs the initial address space before BSS and
   the normal C boot environment are ready.
4. Entry enables translation and caches, clears BSS, initializes the polling
   UART and per-CPU base, and constructs Unikraft boot information.
5. `setup.c` registers the console, reserves page zero, and calls
   `uk_boot_early_init()` to coalesce memory descriptors.
6. `ukplat_mem_init()` installs managed paging when enabled. The platform
   reapplies device memory attributes, initializes GPIO, probes the GIC,
   initializes the boot CPU, and calls `uk_boot_entry()`.

Coalescing runs before paging marks free memory as unmapped. GPIO access runs
after the managed device mappings have been installed. The early console
keeps failures in later initialization visible.

## Memory and paging

The firmware DTB can describe RAM in several tuples. The evaluated 4 GiB
board reports `[0, 0x3fc00000)` and `[0x40000000, 0x100000000)`, with a hole
between them. The platform must handle both banks without allocating the
hole or treating only the first tuple as usable memory.

The assembly parser validates FDT bounds and memory tuples, then rounds RAM
outwards to 1 GiB blocks for the bootstrap identity map. It uses 4 KiB
translation tables and 48-bit address geometry. A direct-map window starting
at `0x0000ff8000000000` lets native paging access physical frames while it
constructs managed tables. The bootstrap direct map is coarse and is not an
allocator's description of usable RAM.

| Address region | Purpose and attributes |
| --- | --- |
| DT-reported RAM | Bootstrap identity mapping as Normal WBWA, rounded to 1 GiB blocks. |
| Physical 64–128 GiB | BCM2712 peripheral aperture, identity mapped as Device-nGnRnE and execute-never. |
| Direct-map window | Bootstrap alias of physical 0–512 GiB used during page-table construction. |
| Physical page zero | Reserved from allocation to avoid a valid allocation being confused with `NULL`. |
| Loaded kernel | Reserved by linker/build boot information. |

The second FDT pass in `bootinfo_fdt.c` builds precise allocation descriptors.
It requires a RAM tuple containing the entire image, rejects partial image
overlaps and overflowing ranges, and reuses common helpers for the DTB,
initrd, and command line. The coarse bootstrap mapping does not make holes
available for allocation.

With `LIBUKPAGING`, Unikraft replaces the bootstrap table with a managed one.
The platform unmaps and remaps device descriptors because the generic Arm64
attribute replacement retains the initial memory-type bits. RAM remains
Normal WBWA and peripheral accesses use Device-nGnRnE. Without paging, the
bootstrap mappings remain active.

Managed paging supports additional mappings, permission changes, translation,
and unmapping. It does not relocate the kernel or provide address-space
layout randomization.

## Console, interrupts, and timer

`pl011.c` implements polling input/output at RP1 offset `0x30000`. It preserves
the firmware's clock and baud configuration, enables transmission and
reception, and registers standard and emergency console streams through
`libukconsole`. UART interrupts are not implemented.

Unikraft's GICv2 driver discovers the DTB's GIC-400-compatible controller.
`time.c` selects timer interrupt tuple 1, the non-secure physical-timer PPI.
The timer implementation uses `CNTPCT_EL0`, `CNTP_CVAL_EL0`, and `CNTP_CTL_EL0`.
It programs an absolute deadline, unmasks the timer, and sleeps with `wfi`.
The interrupt is masked again after waking to avoid repeated interrupts from
an expired deadline.

The timer implementation is adapted from Unikraft's common Arm code. Sharing
physical versus virtual timer selection with that implementation remains an
upstream integration task.

## GPIO and PCIe dependency

`rpi5_gpio.c` exposes direction, read, write, and pull control for GPIO 0–27.
The RP1 GPIO, RIO, and pad blocks use offsets `0xd0000`, `0xe0000`, and
`0xf0000` from the fixed RP1 base. Accesses use ordered MMIO and a spinlock
around register updates. Direction and output value are separate operations.

Initialization assumes the firmware mapping exists; it does not probe or
repair the PCIe configuration. The GPIO API is platform-local. MMIO mappings
alone do not provide general PCIe device support, DMA, or device interrupts.

## Debugging and warm reload

Normal builds boot without debugger intervention. The debug defconfig enables
the early spin loop and a resident trampoline. This separates everyday boot
from the memory reservations needed by the development workflow.

A warm reload must deal with dirty data caches, old instructions, and stale
translations before replacing the image. `reload64.S` runs at the fixed
identity-mapped address `0x200000`, cleans and invalidates data caches by
set/way, invalidates instruction and translation state, and disables EL1
MMU and caches. GDB stops it at `0x200400` and verifies `SCTLR_EL1.M/C/I` are
clear before loading the replacement.

The helper accepts a missing resident signature only for a cold EL2 target.
It rejects a warm EL1 target without the trampoline. The debug linker checks
image reservations; the helper checks the captured DTB fits `0x14000` bytes
before placing it at `0x10000000`. Captured DTBs are board-specific local
artifacts. They must come from the firmware handoff for the board being used.

## Reported hardware evaluation

The report evaluated a 4 GiB Raspberry Pi 5 using a CMSIS-DAP probe and serial
console. These are historical functional results, not performance guarantees
or a claim that every later source revision has been retested on hardware.

| Test | Reported result | What it establishes |
| --- | --- | --- |
| C and C++ hello world | Both printed the message and returned zero. | Boot, console, and application entry for the tested programs. |
| Memory allocation | Allocation and signature verification across both RAM banks. | The exercised memory is accessible and allocatable. The current test requires at least 4,075 MiB. |
| Dynamic paging | A page at 2 TiB passed read-only, read/write, translation, and unmap checks. | Runtime page-table operations and no-fault recovery for that page. |
| Scheduler timer | 1,000 sequential 10 ms sleeps completed in about 10.1 seconds without early wake-ups or clock regression. | Timer-driven scheduling works in the tested configuration. |
| GPIO23 | Ten LED blinks; development also used an ESP32 to observe pin levels. | Basic output on the exercised pin. |
| Warm reload | Two consecutive replacements reached the cache-off park and completed the timer test. | Repeatable reload under the tested single-core conditions. |

The timer test has no upper latency bound and does not measure jitter or
clock accuracy. The C++ smoke test calls a C console function and does not
establish support for a complete C++ runtime. Memory-test thresholds depend
on board capacity and the space occupied by the image and reservations.

## Limitations and upstream integration

Only one core runs. Secondary-core startup, per-core timer/GIC setup,
inter-processor interrupts, and multicore reload are absent. Static PIE and
runtime relocation are unsupported. Firmware releases, other RAM capacities,
and other board revisions were not covered by the report's evaluation.

Ethernet, Wi-Fi, and general PCIe devices are unsupported. RP1 Ethernet needs
MAC/PHY drivers, DMA and interrupt support, and a `uknetdev` adapter. Wi-Fi
uses SDIO and needs its own host/device support. Full PCIe initialization
would remove the dependency on the preserved firmware configuration.

Before upstream submission, agree with maintainers on the placement under
`plat/native`, shared physical-timer selection, and the exception assembly
currently built from `plat/kvm/arm`. The local FDT adapter also includes common
C code with renamed symbols to replace its single-bank discovery; a shared
multi-bank helper would avoid that coupling. These changes need regression
validation on affected Arm platforms.

Prepare a focused, signed-off commit series and decide whether GPIO and the
GDB reload workflow should be separate follow-ups. Keep workstation settings,
local journals, and captured firmware trees outside the submission. Record
fresh cold-boot, paging, timer, and debug-reload results for the final revision.

## Source map

| File | Responsibility |
| --- | --- |
| `entry64.S`, `link64.lds.S` | Firmware entry, fixed image layout, optional debug reservations. |
| `pagetable64.S` | Bounded early FDT parsing and bootstrap translation tables. |
| `bootinfo_fdt.c`, `memory.c` | Memory descriptors and managed device mappings. |
| `setup.c` | Platform initialization order and transfer to common boot. |
| `pl011.c`, `rpi5_gpio.c` | RP1 console and basic GPIO. |
| `time.c`, `generic_timer.c` | Physical-timer discovery, timekeeping, and scheduler wake-ups. |
| `reload64.S` | Cache-safe debug reload trampoline. |
| `Config.uk`, `Makefile.uk`, `Linker.uk` | Platform configuration, compilation, and image generation. |
