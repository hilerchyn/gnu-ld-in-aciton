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
        *(.text)
    } > ROM :text

    .rodata :
    {
        *(.rodata)
    } > ROM :text

    .foo :
    {
        foo_start = .;

        *(.foo)

        foo_end = .;
    } > ROM :text

    .bar :
    {
        bar_start = .;

        *(.bar)

        bar_end = .;
    } > ROM :text

    .data :
    {
        _sdata = .;

        *(.data)

        _edata = .;
    } > RAM AT > ROM :data

    .bss :
    {
        _sbss = .;

        *(.bss)
        *(COMMON)

        _ebss = .;
    } > RAM :data
}

