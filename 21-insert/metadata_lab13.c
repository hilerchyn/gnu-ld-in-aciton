#include <stdint.h>

struct firmware_info
{
	uint32_t magic;
	uint32_t version;
	uint32_t build_id;
	uint32_t image_size;
};


__attribute__((section(".firmware_info")))
const struct firmware_info firmware_info =
{
	.magic = 0x46574D47,
	.version = 0x00010000,
	.build_id = 0x20260920,
	.image_size = 0
};

