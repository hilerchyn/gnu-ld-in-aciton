SECTIONS
{
    .my_registry :
    {
        __my_registry_start = .;

        *(REVERSE(.my_init.*))

        __my_registry_end = .;
    }
}

INSERT BEFORE .text;

