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
        _stext = .;

        *(.text)
        *(.text.*)

        _etext = .;
    } > ROM

    .rodata :
    {
        _srodata = .;

        *(.rodata)
        *(.rodata.*)

        _erodata = .;
    } > ROM

    .data :
    {
        __data_start = .;

        *(.data)
        *(.data.*)

        __data_end = .;
    } > RAM AT > ROM

    __data_load_start = LOADADDR(.data);
    __data_size = SIZEOF(.data);

    .bss :
    {
        __bss_start = .;

        *(.bss)
        *(.bss.*)
        *(COMMON)

        __bss_end = .;
    } > RAM

    __bss_size = SIZEOF(.bss);

    ASSERT(
        __data_end <= ORIGIN(RAM) + LENGTH(RAM),
        "ERROR: .data exceeds RAM"
    );

    ASSERT(
        __bss_end <= ORIGIN(RAM) + LENGTH(RAM),
        "ERROR: .bss exceeds RAM"
    );

    ASSERT(
        LOADADDR(.data) + SIZEOF(.data)
            <= ORIGIN(ROM) + LENGTH(ROM),
        "ERROR: .data load image exceeds ROM"
    );
}
