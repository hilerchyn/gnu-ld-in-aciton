
ENTRY(_start)

MEMORY
{
    ROM (rx) : ORIGIN = 0x00400000, LENGTH = 64K
}

SECTIONS
{
    .text :
    {
        *(.text)
        *(.text.*)

	FILL(0xFF)

	. = ALIGN(0x100);

	BYTE(0x12);
    } > ROM


    .rodata :
    {
        *(.rodata)
        *(.rodata.*)
    } > ROM
}

