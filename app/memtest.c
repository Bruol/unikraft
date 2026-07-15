#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#define GIB (UINT64_C(1024) * 1024 * 1024)
#define TARGET_BYTES (UINT64_C(4) * GIB)
#define CHUNK_BYTES ((UINT64_C(4) * 1024 * 1024) - 64)
#define CHUNK_COUNT ((TARGET_BYTES + CHUNK_BYTES - 1) / CHUNK_BYTES)

static void *chunks[CHUNK_COUNT];

static uint64_t memtest_pattern(uint64_t byte_offset)
{
	return UINT64_C(0x9e3779b97f4a7c15) ^
	       (byte_offset * UINT64_C(0xd6e8feb86659fd93));
}

int main(int argc, char *argv[])
{
	uint64_t allocated = 0;
	uint64_t checked = 0;
	size_t chunk_count = 0;
	size_t errors = 0;
	size_t i;

	(void)argc;
	(void)argv;

	printf("rpi5-memtest: allocating and filling 4 GiB\n");
	for (chunk_count = 0; chunk_count < CHUNK_COUNT; chunk_count++) {
		uint64_t *words;
		size_t chunk_bytes = (size_t)CHUNK_BYTES;
		size_t words_in_chunk;
		size_t j;

		if (TARGET_BYTES - allocated < chunk_bytes)
			chunk_bytes = (size_t)(TARGET_BYTES - allocated);
		chunks[chunk_count] = malloc(chunk_bytes);
		if (!chunks[chunk_count])
			break;

		words = chunks[chunk_count];
		words_in_chunk = chunk_bytes / sizeof(*words);
		for (j = 0; j < words_in_chunk; j++)
			words[j] = memtest_pattern(allocated +
						   j * sizeof(*words));
		allocated += chunk_bytes;
		if (!(chunk_count % 64))
			printf("rpi5-memtest: filled %lu MiB\n",
			       (unsigned long)(allocated / (1024 * 1024)));
	}

	printf("rpi5-memtest: verifying %lu MiB in %lu chunks\n",
	       (unsigned long)(allocated / (1024 * 1024)),
	       (unsigned long)chunk_count);
	for (i = 0; i < chunk_count; i++) {
		const uint64_t *words = chunks[i];
		size_t chunk_bytes = (size_t)CHUNK_BYTES;
		size_t words_in_chunk;
		size_t j;

		if (allocated - checked < chunk_bytes)
			chunk_bytes = (size_t)(allocated - checked);
		words_in_chunk = chunk_bytes / sizeof(*words);
		for (j = 0; j < words_in_chunk; j++) {
			const uint64_t expected = memtest_pattern(checked +
							    j * sizeof(*words));

			if (words[j] != expected) {
				if (errors < 16)
					printf("rpi5-memtest: corruption at 0x%lx: "
					       "got 0x%lx expected 0x%lx\n",
					       (unsigned long)(checked +
							       j * sizeof(*words)),
					       (unsigned long)words[j],
					       (unsigned long)expected);
				errors++;
			}
		}
		checked += chunk_bytes;
	}

	for (i = 0; i < chunk_count; i++)
		free(chunks[i]);

	if (allocated != TARGET_BYTES) {
		printf("rpi5-memtest: PASS, verified all %lu allocatable MiB "
		       "(%lu MiB physical target includes firmware/runtime "
		       "reservations)\n",
		       (unsigned long)(allocated / (1024 * 1024)),
		       (unsigned long)(TARGET_BYTES / (1024 * 1024)));
		return 0;
	}
	if (errors) {
		printf("rpi5-memtest: FAILED with %lu corrupt words\n",
		       (unsigned long)errors);
		return 1;
	}

	printf("rpi5-memtest: PASS, 4 GiB verified\n");
	return 0;
}
