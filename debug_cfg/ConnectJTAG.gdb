file build/unikraft/app_rpi5-arm64.dbg
target extended-remote :3333
set $rpi5_dtb_addr = 0x10000000
load
restore debug_cfg/bcm2712-rpi-5-b.dtb binary $rpi5_dtb_addr
set {unsigned long long}&rpi5_gdb_spin_flag = 0


b rpi5_pl011_init

set $pc = _librpi5plat_entry
set $x0 = $rpi5_dtb_addr

define rpi5_reload
  load
  restore debug_cfg/bcm2712-rpi-5-b.dtb binary $rpi5_dtb_addr
  set {unsigned long long}&rpi5_gdb_spin_flag = 0
  set $pc = _librpi5plat_entry
  set $x0 = $rpi5_dtb_addr
end

document rpi5_reload
Reload build/unikraft/app_rpi5-arm64.dbg, copy debug_cfg/bcm2712-rpi-5-b.dtb to $rpi5_dtb_addr, release the optional early spin loop, then restore pc and x0.
end
