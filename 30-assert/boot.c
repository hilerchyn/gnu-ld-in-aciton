__attribute__((section(".boot")))
int boot_log(void)
{
	return 100;
}

__attribute__((section(".boot")))
int boot_init(void)
{
	return boot_log();
}
