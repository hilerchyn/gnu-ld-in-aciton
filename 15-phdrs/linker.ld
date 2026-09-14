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
		*(.rodata)
		*(.rodata.*)
	} > ROM

	.data :
	{
		_sdata = .;

		*(.data)
		*(.data.*)

		_edata = .;
	} > RAM AT > ROM

	_data_load = LOADADDR(.data);

	.bss :
	{
		_sbss = .;

		*(.bss)
		*(.bss.*)
		*(COMMON)

		_ebss = .;
	} > RAM
}


