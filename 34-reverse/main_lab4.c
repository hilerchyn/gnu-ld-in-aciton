#include <stdio.h>

extern const char mqtt_plugin[];
extern const char http_plugin[];
extern const char debug_plugin[];
extern const char disabled_plugin[];

int main(void)
{
    printf("%s %s %s %s\n", mqtt_plugin, http_plugin, debug_plugin, disabled_plugin);
    return 0;
}


