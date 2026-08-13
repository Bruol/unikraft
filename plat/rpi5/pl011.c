#include "pl011.h"

#include <uk/config.h>

#if CONFIG_LIBUKCONSOLE
#include <uk/console/driver.h>
#endif

static __u32 pl011_read32(__u64 off)
{
	return *(volatile __u32 *)(RPI5_PL011_BASE + off);
}

static void pl011_write32(__u64 off, __u32 val)
{
	*(volatile __u32 *)(RPI5_PL011_BASE + off) = val;
}

void rpi5_pl011_init(void)
{
	pl011_write32(PL011_CR, 0);
	pl011_write32(PL011_LCRH, PL011_LCRH_WLEN_8BIT);
	pl011_write32(PL011_CR, PL011_CR_UARTEN | PL011_CR_TXE | PL011_CR_RXE);
}

void rpi5_pl011_putc(__u8 c)
{
	while (pl011_read32(PL011_FR) & PL011_FR_TXFF)
		;

	pl011_write32(PL011_DR, c);
}

void rpi5_pl011_puts(const char *str)
{
	while (*str)
		rpi5_pl011_putc((__u8)*str++);
}

int rpi5_pl011_rx_ready(void)
{
	return !(pl011_read32(PL011_FR) & PL011_FR_RXFE);
}

__u8 rpi5_pl011_getc(void)
{
	while (!rpi5_pl011_rx_ready())
		;

	return (__u8)(pl011_read32(PL011_DR) & 0xff);
}

static void rpi5_pl011_put_hex_nibble(__u8 val)
{
	val &= 0xf;
	rpi5_pl011_putc(val < 10 ? ('0' + val) : ('a' + val - 10));
}

void rpi5_pl011_put_hex64(__u64 val)
{
	int shift;

	for (shift = 60; shift >= 0; shift -= 4)
		rpi5_pl011_put_hex_nibble((__u8)(val >> shift));
}

static void rpi5_pl011_put_hex8(__u8 val)
{
	rpi5_pl011_put_hex_nibble((__u8)(val >> 4));
	rpi5_pl011_put_hex_nibble(val);
}

void rpi5_pl011_dump_mem(__u64 addr, __u32 len)
{
	volatile const __u8 *ptr = (volatile const __u8 *)addr;
	__u32 i;

	rpi5_pl011_puts("rpi5: dtb data:");
	for (i = 0; i < len; i++)
	{
		if ((i & 0xf) == 0)
		{
			rpi5_pl011_puts("\r\n  ");
			rpi5_pl011_put_hex64(addr + i);
			rpi5_pl011_puts(": ");
		}

		rpi5_pl011_put_hex8(ptr[i]);
		rpi5_pl011_putc(' ');
	}
	rpi5_pl011_puts("\r\n");
}

#if CONFIG_LIBUKCONSOLE
static __ssz rpi5_pl011_console_out(struct uk_console *dev __unused,
									const char *buf, __sz len)
{
	__sz i;

	for (i = 0; i < len; i++)
		rpi5_pl011_putc((__u8)buf[i]);

	return (__ssz)len;
}

static __ssz rpi5_pl011_console_in(struct uk_console *dev __unused,
								   char *buf, __sz len)
{
	__sz i;

	for (i = 0; i < len && rpi5_pl011_rx_ready(); i++)
		buf[i] = (char)rpi5_pl011_getc();

	return (__ssz)i;
}

static const struct uk_console_ops rpi5_pl011_console_ops = {
	.out = rpi5_pl011_console_out,
	.in = rpi5_pl011_console_in,
	.emerg_out = rpi5_pl011_console_out,
};

static struct uk_console rpi5_pl011_console;

void rpi5_pl011_console_init(void)
{
	uk_console_init(&rpi5_pl011_console, "rpi5-pl011",
					&rpi5_pl011_console_ops,
					UK_CONSOLE_FLAG_STDOUT |
						UK_CONSOLE_FLAG_STDIN |
						UK_CONSOLE_FLAG_EMERG_STDOUT,
					UK_CONSOLE_CLASS_UART);
	uk_console_register(&rpi5_pl011_console);
}

#else
void rpi5_pl011_console_init(void)
{
}
#endif
