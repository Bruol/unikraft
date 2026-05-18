#include "dtb.h"
#include "pl011.h"

static uint32_t be32_to_cpu(uint32_t val)
{
    return ((val & 0x000000ffU) << 24) |
           ((val & 0x0000ff00U) << 8) |
           ((val & 0x00ff0000U) >> 8) |
           ((val & 0xff000000U) >> 24);
}

static void uart_put_hex_nibble(uint8_t val)
{
    val &= 0xf;
    pl011_putc(val < 10 ? ('0' + val) : ('a' + val - 10));
}

static void uart_put_hex8(uint8_t val)
{
    uart_put_hex_nibble(val >> 4);
    uart_put_hex_nibble(val);
}

static void uart_put_hex32(uint32_t val)
{
    for (int shift = 28; shift >= 0; shift -= 4)
    {
        uart_put_hex_nibble((uint8_t)(val >> shift));
    }
}

static void uart_put_hex64(uint64_t val)
{
    for (int shift = 60; shift >= 0; shift -= 4)
    {
        uart_put_hex_nibble((uint8_t)(val >> shift));
    }
}

static void uart_put_dec32(uint32_t val)
{
    char buf[10];
    int pos = 0;

    if (val == 0)
    {
        pl011_putc('0');
        return;
    }

    while (val > 0 && pos < (int)sizeof(buf))
    {
        buf[pos++] = (char)('0' + (val % 10));
        val /= 10;
    }

    while (pos > 0)
    {
        pl011_putc(buf[--pos]);
    }
}

static void uart_dump_bytes(const volatile uint8_t *data, uint32_t len)
{
    for (uint32_t off = 0; off < len; off++)
    {
        if ((off & 0xf) == 0)
        {
            pl011_puts("\r\n  +0x");
            uart_put_hex32(off);
            pl011_puts(": ");
        }

        uart_put_hex8(data[off]);
        pl011_putc(' ');
    }

    pl011_puts("\r\n");
}

void dtb_print_from_addr(uint64_t dtb_addr)
{
    volatile uint32_t *fdt32 = (volatile uint32_t *)dtb_addr;
    volatile uint8_t *fdt8 = (volatile uint8_t *)dtb_addr;
    uint32_t magic;
    uint32_t totalsize;

    pl011_puts("\r\nboot x0: 0x");
    uart_put_hex64(dtb_addr);
    pl011_puts("\r\n");

    if (dtb_addr == 0)
    {
        pl011_puts("boot x0 is null; no DTB pointer found there.\r\n");
        return;
    }

    magic = be32_to_cpu(fdt32[0]);
    totalsize = be32_to_cpu(fdt32[1]);

    pl011_puts("fdt magic: 0x");
    uart_put_hex32(magic);
    pl011_puts("\r\nfdt totalsize: ");
    uart_put_dec32(totalsize);
    pl011_puts(" bytes\r\n");

    if (magic != 0xd00dfeedU)
    {
        pl011_puts("x0 does not point at a valid DTB header.\r\n");
        return;
    }

    pl011_puts("x0 points at a valid DTB header. First 256 DTB bytes:");
    uart_dump_bytes(fdt8, 256);
}
