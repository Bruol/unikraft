target extended-remote :3333
file build/kernel.elf
load

# This breakpoint is just past the early spin-loop.
b kernel_main

set $x0 = 0