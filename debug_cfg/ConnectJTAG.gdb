file build/unikraft/app_rpi5-arm64.dbg
target extended-remote :3333
set $rpi5_dtb_addr = 0x10000000

python
class Rpi5Reload(gdb.Command):
    """Safely return a warm Pi 5 target to MMU/cache-off state and reload it."""

    def __init__(self):
        super(Rpi5Reload, self).__init__("rpi5_reload", gdb.COMMAND_USER)

    def invoke(self, arg, from_tty):
        del arg, from_tty
        resident = bytes(gdb.selected_inferior().read_memory(0x200000, 8))
        if resident == b"\xdf\x4f\x03\xd5\x9f\x3f\x03\xd5":
            gdb.write("Normalizing target through the resident reload trampoline.\n")
            park = int(gdb.parse_and_eval("&rpi5_reload_park"))
            bp = gdb.Breakpoint("*%#x" % park, gdb.BP_HARDWARE_BREAKPOINT,
                                temporary=True, internal=True)
            gdb.execute("set $pc = rpi5_reload_trampoline")
            gdb.execute("continue")
            if int(gdb.parse_and_eval("$pc")) != park:
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
b rpi5_pl011_init
