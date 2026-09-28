int global_value = 1234;

extern char __text_start[];

int main(void)
{
	if (__text_start != 0) {}

	return global_value;
}
