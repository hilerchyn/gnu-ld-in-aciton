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
}
