

typedef unsigned int uint32_t;
typedef unsigned long uint64_t;

struct ukplat_bootinfo
{
    uint64_t dtb;
    uint32_t dtb_size;
    uint64_t mem_base;
    uint64_t mem_size;
    uint64_t cmdline;
    uint32_t cmdline_len;
    uint64_t initrd_start;
    uint64_t initrd_end;
};

int ukplat_bootinfo_fdt_setup(uint64_t dtb_addr);
struct ukplat_bootinfo *ukplat_bootinfo_get(void);

void rpi5_ukplat_entry(uint64_t dtb_addr);
