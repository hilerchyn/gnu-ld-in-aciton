typedef void (*init_func)(void);

void init_a(void){}

__attribute__((section(".init_array.300")))
init_func init_a_entry = init_a;
