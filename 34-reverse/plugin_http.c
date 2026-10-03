typedef void (*plugin_fn)(void);

static void http_init(void)
{
}

__attribute__((section(".plugin.100"), used))
plugin_fn http_plugin = http_init;

