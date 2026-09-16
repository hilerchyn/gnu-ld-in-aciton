char huge_buffer[5];

int initialized_value = 0x12345678;

int zero_value;

int main(void)
{
	huge_buffer[0] = 1;

	return initialized_value + zero_value;
}

