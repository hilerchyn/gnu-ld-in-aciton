ENTRY(_start)

MEMORY
{
        ROM (rx) : ORIGIN = 0x00400000, LENGTH = 64K
        RAM (rw) : ORIGIN = 0x00600000, LENGTH = 64K
}

PHDRS
{
        text PT_LOAD FLAGS(5);
        data PT_LOAD FLAGS(6);
}

SECTIONS
{
        .text :
        {
                *(.text .text.*)
        } > ROM :text

        .rodata :
        {
                *(.rodata .rodata.*)
        } > ROM :text

        .eh_frame :
        {
                *(.eh_frame)
        } > ROM :text

        .data : AT(ALIGN(LOADADDR(.rodata) + SIZEOF(.rodata) + SIZEOF(.eh_frame), CONSTANT(MAXPAGESIZE)))
        {
                __data_start = .;
                *(.data .data.*)
                __data_end = .;
        } > RAM :data

        __data_load_start = LOADADDR(.data);
        __data_size       = SIZEOF(.data);

        .bss (NOLOAD) : AT(ADDR(.bss) - ADDR(.data) + LOADADDR(.data))
        {
                __bss_start = .;
                *(.bss .bss.*)
                *(COMMON)
                __bss_end = .;
        } > RAM :data

        /DISCARD/ :
        {
                *(.comment)
                *(.note*)
        }
}
