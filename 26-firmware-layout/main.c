extern int counter;

extern int magic;

extern char message[];
extern const char version[];

extern int bss_buffer[];

int main(void)
{
	counter++;
	magic++;

	bss_buffer[0] = counter;

	return message[0] + version[0];
}
