static inline void cpu_wait_forever(void) {
    for (;;) {
        __asm__ volatile("wfe");
    }
}

void kernel_main(void) {
    volatile unsigned long boot_marker = 0x12345678UL;
    (void)boot_marker;

    cpu_wait_forever();
}
