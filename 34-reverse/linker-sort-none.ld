SECTIONS
{
    .raw_registry :
    {
        __raw_start = .;

        *(SORT_NONE(.my_init.*))

        __raw_end = .;
    }
}

INSERT BEFORE .text;

