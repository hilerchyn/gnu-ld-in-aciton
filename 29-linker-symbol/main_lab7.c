extern char __text_start[];

int main(void)
{
	return (int)(long)__text_start;
}
