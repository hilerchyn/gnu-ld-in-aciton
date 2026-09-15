#include <stddef.h>

extern char __load_start_overlay_a[];
extern char __load_stop_overlay_a[];

extern char __load_start_overlay_b[];
extern char __load_stop_overlay_b[];

extern char __load_start_overlay_c[];
extern char __load_stop_overlay_c[];

#define OVERLAY_RAM ((char *)0x00602000)

static void copy_overlay(
		char *src,
		char *dst,
		size_t size
	)
{
	while (size--)
		*dst++ = *src++;
}

void load_overlay_a(void)
{
	copy_overlay(
			__load_start_overlay_a,
			OVERLAY_RAM,
			__load_stop_overlay_a - __load_start_overlay_a
		);
}

void load_overlay_b(void)
{
	copy_overlay(
			__load_start_overlay_b,
			OVERLAY_RAM,
			__load_stop_overlay_b - __load_start_overlay_b
		);
}

void load_overlay_c(void)
{
	copy_overlay(
			__load_start_overlay_c,
			OVERLAY_RAM,
			__load_stop_overlay_c - __load_start_overlay_c
		);
}
