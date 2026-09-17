int global_data = 123;

extern char __ram_end[];

int main(void)
{
	volatile char *p = __ram_end;

	return p != 0;
}

