volatile int global_data = 123;

volatile int global_bss;

int main(void)
{
    global_bss = global_data + 1;

    return global_bss;
}

