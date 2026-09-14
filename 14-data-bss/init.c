extern char _data_load[];
extern char _sdata[];
extern char _edata[];

extern char _sbss[];
extern char _ebss[];

void copy_data(void)
{
	char *src = _data_load;
	char *dst = _sdata;

	while (dst < _edata)
	{
		*dst++ = *src++;
	}
}

void clear_bss(void)
{
	char *p = _sbss;

	while (p < _ebss)
	{
		*p++ = 0;
	}
}
