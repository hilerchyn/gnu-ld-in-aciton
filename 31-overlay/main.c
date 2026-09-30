#include <stddef.h>
#include <string.h>

typedef void (*overlay_entry_t)(void);

extern char __load_start_ov_a;
extern char __load_stop_ov_a;

#define OVERLAY_RAM ((void *)0x00600000)

void load_overlay_a(void)
{
    size_t size =
        &__load_stop_ov_a -
        &__load_start_ov_a;

    memcpy(
        OVERLAY_RAM,
        &__load_start_ov_a,
        size
    );
}

void run_overlay_a(void)
{
    load_overlay_a();

    overlay_entry_t fn =
        (overlay_entry_t)OVERLAY_RAM;

    fn();
}

int main(void)
{
    run_overlay_a();

    return 0;
}

