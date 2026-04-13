## Debugging:

connect the UART port on the raspi to the D port on the probe and run this command to start openocd

```bash
sudo openocd --file debug_cfg/cmsis-dap.cfg --file debug_cfg/openocd_raspi5.cfg
```

to connect gdb run:

```bash
gdb --command=debug_cfg/ConnectJTAG.gdb build/kernel.elf
```