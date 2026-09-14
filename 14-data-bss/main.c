int initialized_value = 0x12345678;

int zero_value;

int main(void)
{
	if (initialized_value != 0x12345678)
		return 1;

	if (zero_value != 0)
		return 2;

	return 0;
}
