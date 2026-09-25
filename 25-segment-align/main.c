extern int counter;
extern int magic;
extern char message[];

int main(void)
{
	counter++;
	magic++;

	return message[0];
}
