extern char image_start[];
extern char image_end[];

extern char __ram_start[];
extern char __ram_end[];
extern char __stack_top[];


void *ram_lo = __ram_start;
void *ram_hi = __ram_end;
void *stack_top = __stack_top;

int main(void)
{
	long size = image_end - image_start;

	return size == 0;
}

