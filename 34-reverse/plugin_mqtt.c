typedef void (*plugin_fn)(void);

static void mqtt_init(void)
{
}

__attribute__((section(".plugin.200"), used))
plugin_fn mqtt_plugin = mqtt_init;

