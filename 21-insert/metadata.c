#include <stdint.h>

__attribute__((section(".my_metadata")))
const uint32_t metadata[] = 
{
	0x12345678,
	0xAABBCCDD,
	0x55667788,
	0xDEADBEFF
};

