struct command
{
	const char *name;
	int (*handler)(void);
};

static int command_hello(void)
{
	return 10;
}

static const struct command hello_command
        __attribute__((section(".command_table")))
	= {
		"hello",
		command_hello
	};
