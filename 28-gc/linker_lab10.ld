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
        *(.text)
        *(.text.*)
    } > ROM

    .rodata :
    {
        *(.rodata)
        *(.rodata.*)
    } > ROM

    .factory_data :
    {
        *(.factory_data)
    } > ROM

    .firmware_header :
    {
	__firmware_header_start = .;

        KEEP(*(.firmware_header))

	__firmware_header_end = .;
    } > ROM

    .data :
    {
        *(.data)
        *(.data.*)
    } > RAM

    .bss :
    {
        *(.bss)
        *(.bss.*)
        *(COMMON)
    } > RAM
}

