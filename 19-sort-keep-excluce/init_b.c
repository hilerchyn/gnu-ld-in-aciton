typedef void (*init_func)(void);

void init_b(void){}

__attribute__((section(".init_array.100")))
init_func init_b_entry = init_b;

