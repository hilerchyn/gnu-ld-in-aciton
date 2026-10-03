SECTIONS
{
    .plugin_registry :
    {
        . = ALIGN(16);

        __plugin_registry_start = .;

        KEEP(
            *(
                SORT_BY_NAME(
                    EXCLUDE_FILE(plugin_disabled.o)
                    .plugin.*
                )
            )
        )

        __plugin_registry_end = .;
    }
}

INSERT BEFORE .text;

