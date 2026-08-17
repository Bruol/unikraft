/* SPDX-License-Identifier: BSD-3-Clause */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#define GIB (UINT64_C(1024) * 1024 * 1024)
#define TARGET_BYTES (UINT64_C(4) * GIB)
#define MIN_EXPECTED_BYTES (UINT64_C(4075) * 1024 * 1024)
#define CHUNK_BYTES ((UINT64_C(4) * 1024 * 1024) - 64)
#define CHUNK_COUNT ((TARGET_BYTES + CHUNK_BYTES - 1) / CHUNK_BYTES)

static void *chunks[CHUNK_COUNT];

static uint64_t pattern(uint64_t offset)
{
	return UINT64_C(0x9e3779b97f4a7c15) ^
	       (offset * UINT64_C(0xd6e8feb86659fd93));
}

int main(void)
{
	uint64_t allocated = 0;
	uint64_t checked = 0;
	size_t count = 0;
	size_t errors = 0;
	size_t i;

	for (count = 0; count < CHUNK_COUNT; count++) {
		size_t bytes = (size_t)CHUNK_BYTES;
		uint64_t *words;
		size_t j;

		if (TARGET_BYTES - allocated < bytes)
			bytes = (size_t)(TARGET_BYTES - allocated);
		chunks[count] = malloc(bytes);
		if (!chunks[count])
			break;
		words = chunks[count];
		for (j = 0; j < bytes / sizeof(*words); j++)
			words[j] = pattern(allocated + j * sizeof(*words));
		allocated += bytes;
	}

	for (i = 0; i < count; i++) {
		size_t bytes = (size_t)CHUNK_BYTES;
		const uint64_t *words = chunks[i];
		size_t j;

		if (allocated - checked < bytes)
			bytes = (size_t)(allocated - checked);
		for (j = 0; j < bytes / sizeof(*words); j++)
			if (words[j] != pattern(checked + j * sizeof(*words)))
				errors++;
		checked += bytes;
	}

	for (i = 0; i < count; i++)
		free(chunks[i]);

	printf("rpi5-memtest: %lu chunks, %lu bytes, %lu errors\n",
	       (unsigned long)count, (unsigned long)allocated,
	       (unsigned long)errors);
	if (errors || allocated < MIN_EXPECTED_BYTES)
		return 1;
	puts("rpi5-memtest: PASS");
	return 0;
}
