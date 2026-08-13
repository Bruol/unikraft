#ifndef __RPI5_PL011_H__
#define __RPI5_PL011_H__

#include <uk/arch/types.h>

#define RPI5_MMIO_BASE		0x1c00000000UL
#define RPI5_PL011_BASE		(RPI5_MMIO_BASE + 0x30000UL)

#define PL011_DR		0x00
#define PL011_FR		0x18
#define PL011_LCRH		0x2c
#define PL011_CR		0x30

#define PL011_FR_RXFE		(1U << 4)
#define PL011_FR_TXFF		(1U << 5)

#define PL011_LCRH_WLEN_8BIT	(3U << 5)

#define PL011_CR_RXE		(1U << 9)
#define PL011_CR_TXE		(1U << 8)
#define PL011_CR_UARTEN		(1U << 0)

void rpi5_pl011_init(void);
void rpi5_pl011_putc(__u8 c);
void rpi5_pl011_puts(const char *str);
int rpi5_pl011_rx_ready(void);
__u8 rpi5_pl011_getc(void);
void rpi5_pl011_put_hex64(__u64 val);
void rpi5_pl011_dump_mem(__u64 addr, __u32 len);
void rpi5_pl011_console_init(void);

#endif /* __RPI5_PL011_H__ */
