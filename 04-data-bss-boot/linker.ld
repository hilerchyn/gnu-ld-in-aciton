ENTRY(_start)

MEMORY
{
    ROM (rx)  : ORIGIN = 0x00400000, LENGTH = 64K
    RAM (rwx) : ORIGIN = 0x00600000, LENGTH = 64K
}

SECTIONS
{
    .text :
    {
        _stext = .;

        *(.text)

        _etext = .;
    } > ROM

    .rodata :
    {
        *(.rodata)
    } > ROM

    .data :
    {
        _sdata = .;

        *(.data)

        _edata = .;
    } > RAM AT > ROM

    _sidata = LOADADDR(.data);

    .bss :
    {
        _sbss = .;

        *(.bss)
        *(COMMON)

        _ebss = .;
    } > RAM
}
