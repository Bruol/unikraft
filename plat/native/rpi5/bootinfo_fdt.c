/* SPDX-License-Identifier: BSD-3-Clause */

/* Keep the parent Unikraft tree untouched while reusing its non-RAM helpers. */
#define fdt_bootinfo_mem_mrd fdt_bootinfo_mem_mrd_single_bank
#define ukplat_bootinfo_fdt_setup ukplat_bootinfo_fdt_setup_single_bank
#include <bootinfo_fdt.c>
#undef ukplat_bootinfo_fdt_setup
#undef fdt_bootinfo_mem_mrd

static void rpi5_free_mrd(struct ukplat_bootinfo *bi, __u64 base, __u64 len)
{
	struct ukplat_memregion_desc mrd = {0};
	int rc;

	if (!len)
		return;
	mrd.pbase = UK_PAGING_PAGE_ALIGN_DOWN(base);
	mrd.vbase = UK_PAGING_PAGE_ALIGN_DOWN(base);
	mrd.pg_off = base - mrd.pbase;
	mrd.len = len;
	mrd.pg_count = UK_PAGING_PAGE_COUNT(mrd.pg_off + len);
	mrd.type = UKPLAT_MEMRT_FREE;
	mrd.flags = UKPLAT_MEMRF_READ | UKPLAT_MEMRF_WRITE;
	rc = ukplat_memregion_list_insert(&bi->mrds, &mrd);
	if (unlikely(rc < 0))
		ukplat_bootinfo_crash("Could not add free memory descriptor");
}

static __u64 rpi5_read_cells(const fdt32_t *cells, int count)
{
	__u64 value = 0;

	while (count--)
		value = (value << 32) | fdt32_to_cpu(*cells++);
	return value;
}

static int rpi5_node_enabled(const void *fdtp, int node)
{
	const char *status;
	int len;

	status = fdt_getprop(fdtp, node, "status", &len);
	if (!status && len == -FDT_ERR_NOTFOUND)
		return 1;
	if (unlikely(!status))
		ukplat_bootinfo_crash("Bad memory status property");
	return (len == (int)sizeof("okay") &&
		!memcmp(status, "okay", sizeof("okay"))) ||
	       (len == (int)sizeof("ok") &&
		!memcmp(status, "ok", sizeof("ok")));
}

static void rpi5_memory_mrds(struct ukplat_bootinfo *bi, void *fdtp)
{
	const fdt32_t *regs;
	const __u64 image_len = __END - __BASE_ADDR;
	__u64 base, size, end;
	int prop_len, tuple_len;
	int node = -1;
	int parent, naddr, nsize;
	int found = 0;
	int image_found = 0;

	while ((node = fdt_node_offset_by_prop_value(fdtp, node,
			"device_type", "memory", sizeof("memory"))) >= 0) {
		if (!rpi5_node_enabled(fdtp, node))
			continue;
		parent = fdt_parent_offset(fdtp, node);
		if (unlikely(parent < 0))
			ukplat_bootinfo_crash("Memory node has no parent");
		naddr = fdt_address_cells(fdtp, parent);
		nsize = fdt_size_cells(fdtp, parent);
		if (unlikely(naddr <= 0 || naddr > 2 ||
			     nsize <= 0 || nsize > 2))
			ukplat_bootinfo_crash("Bad memory cell width");
		tuple_len = sizeof(fdt32_t) * (naddr + nsize);
		regs = fdt_getprop(fdtp, node, "reg", &prop_len);
		if (unlikely(!regs || prop_len <= 0 || prop_len % tuple_len))
			ukplat_bootinfo_crash("Bad memory reg property");

		while (prop_len) {
			base = rpi5_read_cells(regs, naddr);
			regs += naddr;
			size = rpi5_read_cells(regs, nsize);
			regs += nsize;
			prop_len -= tuple_len;
			if (!size)
				continue;
			end = base + size;
			if (unlikely(end < base))
				ukplat_bootinfo_crash("Memory range overflows");
			found = 1;
			if (end > __BASE_ADDR && base < __END) {
				if (unlikely(!RANGE_CONTAIN(base, size,
							    __BASE_ADDR, image_len)))
					ukplat_bootinfo_crash("Memory tuple partially overlaps image");
				image_found = 1;
				rpi5_free_mrd(bi, base, __BASE_ADDR - base);
				rpi5_free_mrd(bi, __END, end - __END);
			} else {
				rpi5_free_mrd(bi, base, size);
			}
		}
	}
	if (unlikely(node != -FDT_ERR_NOTFOUND || !found || !image_found))
		ukplat_bootinfo_crash("Invalid DTB memory layout");
}

void ukplat_bootinfo_fdt_setup(void *fdtp)
{
	struct ukplat_bootinfo *bi = ukplat_bootinfo_get();

	if (unlikely(!bi || fdt_check_header(fdtp)))
		ukplat_bootinfo_crash("Invalid bootinfo or DTB");
	fdt_bootinfo_fdt_mrd(bi, fdtp);
	rpi5_memory_mrds(bi, fdtp);
	fdt_bootinfo_initrd_mrd(bi, fdtp);
	fdt_bootinfo_cmdl_init(bi, fdtp);
	bi->dtb = (__u64)fdtp;
}
