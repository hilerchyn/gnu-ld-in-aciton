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
        *(.text)
    } > ROM

    .rodata :
    {
        *(.rodata)
    } > ROM

    .data :
    {
        *(.data)
    } > RAM AT > ROM

    .bss :
    {
        *(.bss)
        *(COMMON)
    } > RAM
}

