extern int boot_init(void);

__attribute__((section(".app")))
int app_task(void)
{
	return 10;
}

__attribute__((section(".app")))
int app_main(void)
{
	return boot_init();
}
