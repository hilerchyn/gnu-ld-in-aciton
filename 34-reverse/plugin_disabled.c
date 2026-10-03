typedef void (*plugin_fn)(void);

static void disabled_init(void)
{
}

__attribute__((section(".plugin.999"), used))
plugin_fn disabled_plugin = disabled_init;

