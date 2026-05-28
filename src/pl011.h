

//

typedef unsigned char uint8_t;
typedef unsigned short uint16_t;
typedef unsigned int uint32_t;
typedef unsigned long uint64_t;

// static for now for raspi5

void pl011_init();
void pl011_putc(const uint8_t c);
void pl011_puts(const char *str);
int pl011_rx_ready();
uint8_t pl011_getc();
