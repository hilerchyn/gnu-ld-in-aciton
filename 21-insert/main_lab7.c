extern const unsigned int metadata[];


int main(void)
{
	return metadata[0] != 0x12345678;
}
