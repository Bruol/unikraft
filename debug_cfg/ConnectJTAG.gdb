file build/rpi5/kernel_2712.dbg
target extended-remote :3333
set $rpi5_dtb_addr = 0x10000000

python
from pathlib import Path

RPI5_RELOAD_ENTRY = 0x200000
RPI5_RELOAD_PARK = 0x200400
RPI5_DTB_MAX_SIZE = 0x14000

class Rpi5Reload(gdb.Command):
    """Safely return a warm Pi 5 target to MMU/cache-off state and reload it."""

    def __init__(self):
        super(Rpi5Reload, self).__init__("rpi5_reload", gdb.COMMAND_USER)

    def invoke(self, arg, from_tty):
        del arg, from_tty
        try:
            gdb.parse_and_eval("&rpi5_gdb_spin_flag")
            gdb.parse_and_eval("&rpi5_reload_trampoline")
        except gdb.error as exc:
            raise gdb.GdbError(
                "reload requires rpi5_config/rpi5_debug_defconfig") from exc

        dtb_path = Path("debug_cfg/bcm2712-rpi-5-b.dtb")
        try:
            dtb_size = dtb_path.stat().st_size
            with dtb_path.open("rb") as dtb_file:
                header = dtb_file.read(8)
        except OSError as exc:
            raise gdb.GdbError(
                "capture the target firmware DTB first; see "
                "plat/native/rpi5/README.md") from exc
        if not 40 <= dtb_size <= RPI5_DTB_MAX_SIZE:
            raise gdb.GdbError(
                "DTB is %#x bytes; expected 40..%#x bytes" %
                (dtb_size, RPI5_DTB_MAX_SIZE))
        if (header[:4] != b"\xd0\x0d\xfe\xed" or
                int.from_bytes(header[4:8], "big") != dtb_size):
            raise gdb.GdbError("invalid or truncated firmware DTB")

        resident = bytes(gdb.selected_inferior().read_memory(
            RPI5_RELOAD_ENTRY, 8))
        if resident == b"\xdf\x4f\x03\xd5\x9f\x3f\x03\xd5":
            gdb.write("Normalizing target through the resident reload trampoline.\n")
            bp = gdb.Breakpoint("*%#x" % RPI5_RELOAD_PARK,
                                gdb.BP_HARDWARE_BREAKPOINT,
                                temporary=True, internal=True)
            # OpenOCD ignores a raw numeric assignment to $pc on this target;
            # this symbol is linker-asserted at the resident ABI entry address.
            gdb.execute("set $pc = rpi5_reload_trampoline")
            gdb.execute("continue")
            if int(gdb.parse_and_eval("$pc")) != RPI5_RELOAD_PARK:
                raise gdb.GdbError("reload trampoline did not reach its cache-off park")
            sctlr = int(gdb.parse_and_eval("$x0"))
            if sctlr & ((1 << 0) | (1 << 2) | (1 << 12)):
                raise gdb.GdbError("reload trampoline left SCTLR_EL1.M/C/I enabled")
            if bp.is_valid():
                bp.delete()
        else:
            current_el = (int(gdb.parse_and_eval("$cpsr")) >> 2) & 3
            if current_el != 2:
                raise gdb.GdbError(
                    "no resident reload trampoline on a non-firmware target; "
                    "cold-boot this worktree image once")
            gdb.write("Cold EL2 firmware target; no teardown required.\n")

        gdb.execute("load")
        gdb.execute("restore debug_cfg/bcm2712-rpi-5-b.dtb binary $rpi5_dtb_addr")
        gdb.execute("set {unsigned long long}&rpi5_gdb_spin_flag = 0")
        gdb.execute("set $pc = _librpi5plat_entry")
        gdb.execute("set $x0 = $rpi5_dtb_addr")
        gdb.execute("set $x2 = 0")

Rpi5Reload()
end

document rpi5_reload
Run the fixed-address resident trampoline. It checks the live SCTLR state,
cleans/invalidates caches when needed, and returns to an identity-addressed
MMU-off state. Then load the ELF/DTB and set pc/x0 for the platform entry.
end

rpi5_reload
