typedef void (*init_func)(void);

void init_c(void){}

__attribute__((section(".init_array.200")))
init_func init_c_entry = init_c;

