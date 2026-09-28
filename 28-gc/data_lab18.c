struct driver
{
    const char *name;
    int id;
};

__attribute__((section(".driver_table")))
const struct driver driver_a =
{
    "driver_a",
    1
};

__attribute__((section(".driver_table")))
const struct driver driver_b =
{
    "driver_b",
    2
};

__attribute__((section(".driver_table")))
const struct driver driver_c =
{
    "driver_c",
    3
};

