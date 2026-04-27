#!/usr/bin/env bash
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
session="${RPI5_TMUX_SESSION:-rpi5-debug}"
gdb_bin="${RPI5_GDB:-gdb}"

openocd_cmd="cd '$repo_root' && openocd -f debug_cfg/cmsis-dap.cfg -f debug_cfg/openocd_raspi5.cfg"
gdb_cmd="cd '$repo_root' && make && $gdb_bin -q -ex 'set confirm off' -ex 'target extended-remote :3333' -ex 'file build/kernel.elf' -ex 'load' -ex 'tbreak src/start.S:19' -ex 'continue' -ex 'set \$x0 = 0' -ex 'break kernel_main'"

if tmux has-session -t "$session" 2>/dev/null; then
    tmux kill-session -t "$session"
fi

tmux new-session -d -s "$session" -n openocd "$openocd_cmd"
tmux new-window -t "$session:" -n gdb "$gdb_cmd"
tmux select-window -t "$session:gdb"
tmux attach-session -t "$session"
