#ifndef __PL011_H
#define __PL011_H

// #include <stdint.h>

typedef unsigned char uint8_t;
typedef unsigned short uint16_t;
typedef unsigned int uint32_t;
typedef unsigned long uint64_t;

// static for now for raspi5
#define MMIO_BASE 0x1c00000000UL
#define PL011_REG_OFFSET MMIO_BASE + 0x30000

#define PL011_DR 0x00 /* Data read or written from the interface. */

#define PL011_FR 0x18    /* Flag register (Read only). */
#define PL011_IBRD 0x24  /* Integer baud rate divisor register. */
#define PL011_FBRD 0x28  /* Fractional baud rate divisor register. */
#define PL011_LCRH 0x2c  /* Line control register. */
#define PL011_CR 0x30    /* Control register. */
#define PL011_IFLS 0x34  /* Interrupt fifo level select. */
#define PL011_IMSC 0x38  /* Interrupt mask. */
#define PL011_RIS 0x3c   /* Raw interrupt status. */
#define PL011_MIS 0x40   /* Masked interrupt status. */
#define PL011_ICR 0x44   /* Interrupt clear register. */
#define PL011_DMACR 0x48 /* DMA control register. */

#define PL011_FR_RXFE (1 << 4) /* RX FIFO Empty */
#define PL011_FR_TXFF (1 << 5) /* TX FIFO full */

#define PL011_LCRH_WLEN_8BIT (3 << 5) /* 8bit */

#define PL011_CR_CTSEN (1 << 15) /* CTS hardware flow control enable */
#define PL011_CR_RTSEN (1 << 14) /* RTS hardware flow control enable */
#define PL011_CR_RTS (1 << 11)   /* Request to send */
#define PL011_CR_DTR (1 << 10)   /* Data transmit ready. */
#define PL011_CR_RXE (1 << 9)    /* Receive enable */
#define PL011_CR_TXE (1 << 8)    /* Transmit enable */
#define PL011_CR_LBE (1 << 7)    /* Loopback enable */
#define PL011_CR_UARTEN (1 << 0) /* UART Enable */

#define pl011_read8(offset) (*(volatile uint8_t *)(PL011_REG_OFFSET + offset))
#define pl011_write8(offset, val) (*(volatile uint8_t *)(PL011_REG_OFFSET + offset)) = val
#define pl011_read32(offset) (*(volatile uint32_t *)(PL011_REG_OFFSET + offset))
#define pl011_write32(offset, val) (*(volatile uint32_t *)(PL011_REG_OFFSET + offset)) = val

void pl011_init();
void pl011_putc(const uint8_t c);
void pl011_puts(const char *str);
int pl011_rx_ready();
uint8_t pl011_getc();
#endif
