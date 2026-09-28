ENTRY(_start)

MEMORY
{
    ROM (rx) : ORIGIN = 0x00400000, LENGTH = 64K
    RAM (rw) : ORIGIN = 0x00600000, LENGTH = 64K
}

SECTIONS
{
    .text :
    {
        __text_start = .;

        *(.text)
        *(.text.*)

        __text_end = .;
    } > ROM

    .data :
    {
        __data_start = .;

        *(.data)
        *(.data.*)

        __data_end = .;
    } > RAM

    __firmware_magic = 0x46574D47;
}

