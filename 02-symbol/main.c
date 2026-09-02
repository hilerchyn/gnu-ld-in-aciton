int global_data = 123;

int global_bss;

int main(void)
{
    global_bss = global_data;

    return global_bss;
}
