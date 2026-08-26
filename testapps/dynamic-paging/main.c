/* SPDX-License-Identifier: BSD-3-Clause */

#include <stdint.h>
#include <stdio.h>
#include <uk/nofault.h>
#include <uk/paging.h>

#define TEST_VADDR ((__vaddr_t)0x20000000000ULL)
#define TEST_VALUE UINT64_C(0x0123456789abcdef)

static int test_fail(const char *operation, int rc)
{
	printf("FAIL: %s: %d\n", operation, rc);
	return 1;
}

int main(void)
{
	struct uk_pagetable *pt = uk_paging_pt_get_active();
	volatile uint64_t *page = (volatile uint64_t *)TEST_VADDR;
	__paddr_t paddr;
	__sz accessible;
	int rc;

	puts("Dynamic paging test");
	if (!pt)
		return test_fail("no active managed page table", -1);

	printf("Active page table: %p\n", pt);
	printf("TTBR0 physical base: 0x%lx\n",
	       (unsigned long)uk_paging_pt_read_base());

	accessible = uk_nofault_probe_r(TEST_VADDR, 1, 0);
	if (accessible)
		return test_fail("test virtual address is already mapped", -1);
	puts("PASS: test virtual address starts unmapped");

	rc = uk_paging_page_map(pt, TEST_VADDR, UK_PAGING_PADDR_ANY, 1,
				UK_PAGING_PAGE_ATTR_PROT_READ, 0);
	if (rc)
		return test_fail("map read-only page", rc);

	accessible = uk_nofault_probe_r(TEST_VADDR, 1, 0);
	if (accessible != 1) {
		test_fail("mapped page is not readable", -1);
		goto fail_unmap;
	}
	accessible = uk_nofault_probe_rw(TEST_VADDR, 1, 0);
	if (accessible) {
		test_fail("read-only page is writable", -1);
		goto fail_unmap;
	}
	puts("PASS: read-only permission works");

	rc = uk_paging_page_set_attr(pt, TEST_VADDR, 1,
				     UK_PAGING_PAGE_ATTR_PROT_RW, 0);
	if (rc) {
		test_fail("change page to read/write", rc);
		goto fail_unmap;
	}

	*page = TEST_VALUE;
	if (*page != TEST_VALUE) {
		test_fail("mapped-page value did not round-trip", -1);
		goto fail_unmap;
	}
	puts("PASS: write/read through the new mapping works");

	paddr = uk_paging_virt_to_phys(TEST_VADDR);
	if (paddr == UK_PAGING_PADDR_ANY) {
		test_fail("virtual-to-physical translation failed", -1);
		goto fail_unmap;
	}
	printf("PASS: VA 0x%lx maps to PA 0x%lx\n",
	       (unsigned long)TEST_VADDR, (unsigned long)paddr);

	rc = uk_paging_page_unmap(pt, TEST_VADDR, 1, 0);
	if (rc)
		return test_fail("unmap page", rc);

	accessible = uk_nofault_probe_r(TEST_VADDR, 1, 0);
	if (accessible)
		return test_fail("page remains accessible after unmap", -1);

	puts("PASS: unmap removed the translation");
	puts("PASS: dynamic paging test completed");
	return 0;

fail_unmap:
	rc = uk_paging_page_unmap(pt, TEST_VADDR, 1, 0);
	if (rc)
		test_fail("cleanup unmap", rc);
	return 1;
}
