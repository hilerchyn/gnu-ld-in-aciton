ENTRY(_start)

SECTIONS
{
    . = 0x00400000;

    .text :
    {
        _stext = .;
        *(.text)
        _etext = .;
    }

    .rodata :
    {
        *(.rodata)
    }

    . = 0x00600000;

    .data :
    {
        _sdata = .;
        *(.data)
        _edata = .;
    }

    .bss :
    {
        _sbss = .;
        *(.bss)
        *(COMMON)
        _ebss = .;
    }

    _sidata = LOADADDR(.data);
}

