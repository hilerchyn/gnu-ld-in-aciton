SECTIONS
{
    .plugin_registry :
    {
        __plugin_start = .;

        *(EXCLUDE_FILE(plugin_b.o) .plugin.*)

        __plugin_end = .;
    }
}

INSERT BEFORE .text;

