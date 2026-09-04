ENTRY(_start)

MEMORY
{
    ROM (rx)  : ORIGIN = 0x00400000, LENGTH = 64K
    RAM (rwx) : ORIGIN = 0x00600000, LENGTH = 64K
}

SECTIONS
{
    .text :
        ALIGN(16) 
    {
        _stext = .;
        *(.text)
        _etext = .;
    } > ROM

    .rodata :
        ALIGN(8) 
    {
        *(.rodata)
    } > ROM

    .data :
        ALIGN(8) 
    {
        _sdata = .;
        *(.data)
        _edata = .;
    } > RAM AT > ROM

    _sidata = LOADADDR(.data);

    .bss :
        ALIGN(8) 
    {
        _sbss = .;
        *(.bss)
        *(COMMON)
        _ebss = .;
    } > RAM
}

