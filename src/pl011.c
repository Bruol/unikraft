#include "pl011.h"

void pl011_init()
{
    // disable UART
    pl011_write32(PL011_CR, 0x0);
    // config uart
    pl011_write32(PL011_LCRH, PL011_LCRH_WLEN_8BIT);
    // enable UART
    pl011_write32(
        PL011_CR,
        PL011_CR_UARTEN | PL011_CR_TXE | PL011_CR_RXE);
}

void pl011_putc(const uint8_t c)
{
    while (pl011_read32(PL011_FR) & PL011_FR_TXFF)
        ;
    pl011_write32(PL011_DR, c);
}

void pl011_puts(const char *str)
{
    uint16_t cnt = 0;
    while (cnt < 256)
    {
        if (str[cnt] != 0)
        {
            pl011_putc(str[cnt]);
        }
        else
        {
            break;
        }
        cnt++;
    }
}
uint8_t pl011_getc()
{
    return pl011_read8(PL011_DR);
}