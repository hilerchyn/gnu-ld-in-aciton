int used_data = 100;

int unused_data = 200;

__attribute__((section(".factory_data")))
const unsigned char factory_data[] =
{
    0x11,
    0x22,
    0x33,
    0x44,
    0x55,
    0x66,
    0x77,
    0x88
};

__attribute__((section(".firmware_header")))
const unsigned int firmware_magic = 0x46574D47;

