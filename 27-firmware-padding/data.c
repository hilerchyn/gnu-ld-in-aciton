int counter = 1234;

int magic = 0x12345678;

char message[] = "GNU LD LAB 27";

const char version[] = "VERSION-27";

__attribute__((section(".firmware_header")))
const unsigned int firmware_magic = 0x46574D47;

__attribute__((section(".firmware_header")))
const unsigned int firmware_version = 0x00010000;

