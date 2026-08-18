# RP1 GPIO PCIe firmware handoff

The platform assumes the Raspberry Pi firmware configures and preserves the RP1
PCIe link and BAR before entering Unikraft, as requested by `pciex4_reset=0`.
The fixed RP1 BAR CPU base is `0x1c00000000`, shared with the PL011 path. The
GPIO, RIO, and pads regions are accessed at offsets `0xd0000`, `0xe0000`, and
`0xf0000` from that base.

During initial bring-up, runtime discovery was tested and found that the loaded
DT `ranges` translated to an inactive CPU window (`0xdeaddead`), while the live
firmware BAR was accessible through the fixed `0x1c...` window. The final GPIO
implementation therefore follows the same fixed firmware contract as PL011 and
does not configure or discover the BCM2712 root complex at runtime.

The Raspberry Pi RP1 GPIO reference implementation assumes this same kind of
already-configured PCIe handoff; it only programs the RP1 GPIO, RIO, and pad
registers after receiving a mapped RP1 base.



# Write that UART uses standart PL011 driver
