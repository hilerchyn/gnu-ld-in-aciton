__attribute__((section(".my_code")))
void orphan_function(void){}

__attribute__((section(".my_data")))
int orphan_data = 123;

__attribute__((section(".my_bss")))
int orphan_bss;

