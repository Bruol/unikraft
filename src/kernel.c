

void kernel_main(uint64_t boot_x0)
{
    pl011_init();
    rpi5_ukplat_entry(boot_x0);
}
