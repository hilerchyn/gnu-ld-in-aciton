int global_data = 123;

int global_bss;

const char message[] = "Hello ld";

int main(void)
{
    global_bss = global_data;

    return global_bss;
}

