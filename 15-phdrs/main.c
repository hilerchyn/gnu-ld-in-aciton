const char message[] = "GNU ld";

int initialized_value = 0x12345678;

int zero_value;

int add(int a, int b)
{
	return a + b;
}

int main(void)
{
	int result = add(initialized_value, zero_value);

	if (message[0] != 'G')
		return 1;

	return result;
}

