

static struct ukplat_bootinfo bootinfo;

static uint32_t be32_to_cpu(uint32_t val)
{
    return ((val & 0x000000ffU) << 24) |
           ((val & 0x0000ff00U) << 8) |
           ((val & 0x00ff0000U) >> 8) |
           ((val & 0xff000000U) >> 24);
}

static uint64_t be64_to_cpu(uint64_t val)
{
    uint64_t hi = be32_to_cpu((uint32_t)(val >> 32));
    uint64_t lo = be32_to_cpu((uint32_t)val);

    return (lo << 32) | hi;
}

static void uart_put_hex_nibble(uint8_t val)
{
    val &= 0xf;
    pl011_putc(val < 10 ? ('0' + val) : ('a' + val - 10));
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

static uint32_t align4(uint32_t val)
{
    return (val + 3U) & ~3U;
}

static int str_eq(const char *a, const char *b)
{
    while (*a && *b && *a == *b)
    {
        a++;
        b++;
    }

    return *a == '\0' && *b == '\0';
}

static int bytes_eq_str(const char *bytes, uint32_t len, const char *str)
{
    uint32_t i = 0;

    while (i < len && str[i] && bytes[i] == str[i])
    {
        i++;
    }

    return i < len && bytes[i] == '\0' && str[i] == '\0';
}

static int str_starts_with(const char *str, const char *prefix)
{
    while (*prefix != '\0')
    {
        if (*str != *prefix)
        {
            return 0;
        }
        str++;
        prefix++;
    }

    return 1;
}

static uint32_t fdt32(const uint8_t *base, uint32_t off)
{
    const uint32_t *val = (const uint32_t *)(base + off);

    return be32_to_cpu(*val);
}

static uint64_t read_cells(const uint8_t *prop, uint32_t cells)
{
    uint64_t val = 0;

    for (uint32_t i = 0; i < cells; i++)
    {
        val = (val << 32) | be32_to_cpu(((const uint32_t *)prop)[i]);
    }

    return val;
}

struct ukplat_bootinfo *ukplat_bootinfo_get(void)
{
    return &bootinfo;
}

int ukplat_bootinfo_fdt_setup(uint64_t dtb_addr)
{
    const uint8_t *fdt = (const uint8_t *)dtb_addr;
    uint32_t totalsize;
    uint32_t off_dt_struct;
    uint32_t off_dt_strings;
    uint32_t off;
    uint32_t depth = 0;
    uint32_t root_addr_cells = 2;
    uint32_t root_size_cells = 1;
    int in_memory = 0;
    int in_chosen = 0;
    int memory_node_seen = 0;

    pl011_puts("\r\nrpi5: _start -> rpi5_ukplat_entry\r\n");
    pl011_puts("rpi5: firmware x0/dtb = 0x");
    uart_put_hex64(dtb_addr);
    pl011_puts("\r\n");

    if (dtb_addr == 0)
    {
        pl011_puts("rpi5: missing DTB pointer\r\n");
        return -1;
    }

    if (fdt32(fdt, 0) != FDT_MAGIC)
    {
        pl011_puts("rpi5: bad DTB magic\r\n");
        return -1;
    }

    totalsize = fdt32(fdt, 4);
    off_dt_struct = fdt32(fdt, 8);
    off_dt_strings = fdt32(fdt, 12);

    bootinfo.dtb = dtb_addr;
    bootinfo.dtb_size = totalsize;

    off = off_dt_struct;
    while (off < totalsize)
    {
        uint32_t token = fdt32(fdt, off);
        off += 4;

        if (token == FDT_BEGIN_NODE)
        {
            const char *name = (const char *)(fdt + off);
            uint32_t name_len = 0;

            while (off + name_len < totalsize && name[name_len] != '\0')
            {
                name_len++;
            }
            off += align4(name_len + 1);

            in_memory = 0;
            in_chosen = 0;
            if (depth == 1 && memory_node_seen == 0 &&
                (bytes_eq_str(name, name_len + 1, "memory") ||
                 str_starts_with(name, "memory@")))
            {
                in_memory = 1;
                memory_node_seen = 1;
            }
            else if (depth == 1 && str_eq(name, "chosen"))
            {
                in_chosen = 1;
            }

            depth++;
        }
        else if (token == FDT_END_NODE)
        {
            if (depth > 0)
            {
                depth--;
            }
            in_memory = 0;
            in_chosen = 0;
        }
        else if (token == FDT_PROP)
        {
            uint32_t len = fdt32(fdt, off);
            uint32_t nameoff = fdt32(fdt, off + 4);
            const char *prop_name = (const char *)(fdt + off_dt_strings + nameoff);
            const uint8_t *prop = fdt + off + 8;

            off += 8 + align4(len);

            if (depth == 1 && str_eq(prop_name, "
            {
                root_addr_cells = be32_to_cpu(*(const uint32_t *)prop);
            }
            else if (depth == 1 && str_eq(prop_name, "
            {
                root_size_cells = be32_to_cpu(*(const uint32_t *)prop);
            }
            else if (in_memory && str_eq(prop_name, "reg") &&
                     len >= 4 * (root_addr_cells + root_size_cells))
            {
                bootinfo.mem_base = read_cells(prop, root_addr_cells);
                bootinfo.mem_size = read_cells(prop + 4 * root_addr_cells,
                                               root_size_cells);
            }
            else if (in_chosen && str_eq(prop_name, "bootargs") && len > 0)
            {
                bootinfo.cmdline = (uint64_t)prop;
                bootinfo.cmdline_len = len;
            }
            else if (in_chosen && str_eq(prop_name, "linux,initrd-start"))
            {
                if (len == 4)
                {
                    bootinfo.initrd_start = be32_to_cpu(*(const uint32_t *)prop);
                }
                else if (len >= 8)
                {
                    bootinfo.initrd_start = be64_to_cpu(*(const uint64_t *)prop);
                }
            }
            else if (in_chosen && str_eq(prop_name, "linux,initrd-end"))
            {
                if (len == 4)
                {
                    bootinfo.initrd_end = be32_to_cpu(*(const uint32_t *)prop);
                }
                else if (len >= 8)
                {
                    bootinfo.initrd_end = be64_to_cpu(*(const uint64_t *)prop);
                }
            }
        }
        else if (token == FDT_NOP)
        {
            continue;
        }
        else if (token == FDT_END)
        {
            break;
        }
        else
        {
            pl011_puts("rpi5: unknown DTB structure token\r\n");
            return -1;
        }
    }

    if (bootinfo.mem_size == 0)
    {
        pl011_puts("rpi5: no usable /memory/reg found\r\n");
        return -1;
    }

    return 0;
}

static void uk_boot_early_init(struct ukplat_bootinfo *bi)
{
    pl011_puts("rpi5: uk_boot_early_init stub\r\n");
    pl011_puts("  dtb size: ");
    uart_put_dec32(bi->dtb_size);
    pl011_puts(" bytes\r\n");
    pl011_puts("  memory: 0x");
    uart_put_hex64(bi->mem_base);
    pl011_puts(" + 0x");
    uart_put_hex64(bi->mem_size);
    pl011_puts("\r\n");

    if (bi->cmdline != 0)
    {
        const char *cmdline = (const char *)bi->cmdline;

        pl011_puts("  bootargs: ");
        for (uint32_t i = 0; i < bi->cmdline_len && i < 160; i++)
        {
            if (cmdline[i] == '\0')
            {
                break;
            }
            pl011_putc((uint8_t)cmdline[i]);
        }
        pl011_puts("\r\n");
    }
}

static void uk_boot_entry(void)
{
    pl011_puts("rpi5: uk_boot_entry stub reached\r\n");
    for (;;)
    {
        asm volatile("wfe");
    }
}

void rpi5_ukplat_entry(uint64_t dtb_addr)
{
    struct ukplat_bootinfo *bi;

    if (ukplat_bootinfo_fdt_setup(dtb_addr) != 0)
    {
        pl011_puts("rpi5: bootinfo setup failed\r\n");
        for (;;)
        {
            asm volatile("wfe");
        }
    }

    bi = ukplat_bootinfo_get();
    uk_boot_early_init(bi);
    uk_boot_entry();
}
