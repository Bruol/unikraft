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

static void uart_reply_loop(void)
{
    char input[128];
    uint16_t len = 0;

    pl011_puts("UART reply loop ready\r\n> ");
    for (;;)
    {
        if (!pl011_rx_ready())
        {
            continue;
        }

        uint8_t c = pl011_getc();

        if (c == '\r' || c == '\n')
        {
            input[len] = '\0';

            pl011_puts("\r\nYou said: ");
            pl011_puts(input);
            pl011_puts("\r\n> ");

            len = 0;
        }
        else if (c == '\b' || c == 0x7f)
        {
            if (len > 0)
            {
                len--;
                pl011_puts("\b \b");
            }
        }
        else
        {
            if (len < sizeof(input) - 1)
            {
                input[len++] = (char)c;
                pl011_putc(c);
            }
        }
    }
}

void kernel_main(void)
{

    pl011_init();
    uart_reply_loop();
}
