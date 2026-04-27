#include "pl011.h"

static inline void cpu_wait_forever(void)
{
    for (;;)
    {
        __asm__ volatile("wfe");
    }
}

// TODO: remove -- we dont need this as this is only for rpi5 but I though it was cool :)
int get_raspi_board()
{
    unsigned int reg;
    int ret = 0;

    /* read the system register */
#if __aarch64__
    asm volatile("mrs %x0, midr_el1" : "=r"(reg));
#else
    asm volatile("mrc p15,0,%0,c0,c0,0" : "=r"(reg));
#endif

    /* get the PartNum, detect board and MMIO base address */
    switch ((reg >> 4) & 0xFFF)
    {
    case 0xB76:
        ret = 1;
        break;
    case 0xC07:
        ret = 2;
        break;
    case 0xD03:
        ret = 3;
        break;
    case 0xD08:
        ret = 4;
        break;
    case 0xD0B:
        ret = 5;
    default:
        break;
    }
    return ret;
}

void kernel_main(void)
{
    volatile unsigned long boot_marker = 0x12345678UL;
    (void)boot_marker;

    pl011_init();
    pl011_puts("Raspberry Pi5 UART demo?!\r\n");
    while (1)
    {
        uint32_t rx_status = pl011_read32(PL011_FR);
        // empty? if not printout
        if (!(rx_status & PL011_FR_RXFE))
        {
            uint8_t c = pl011_read8(PL011_DR);
            if (c == 0xD)
            {
                pl011_puts("\r\n");
            }
            else
            {
                pl011_write8(PL011_DR, c);
            }
        }
    }
}
