typedef void (*plugin_fn)(void);

static void debug_init(void)
{
}

__attribute__((section(".plugin.300"), used))
plugin_fn debug_plugin = debug_init;

