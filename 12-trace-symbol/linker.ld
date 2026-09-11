ENTRY(_start)

MEMORY
{
	ROM (rx) : ORIGIN = 0x00400000, LENGTH = 64K
}

PHDRS
{
	text PT_LOAD FLAGS(5);
}

SECTIONS
{
	.text :
	{
		_stext = .;

		*(.text)
		*(.text.*)

		_etext = .;
	} > ROM :text

	.rodata :
	{
		*(.rodata)
		*(.rodata.*)
	} > ROM :text

	.data :
	{
		*(.data)
		*(.data.*)
	} > ROM :text

	.bss :
	{
		*(.bss)
		*(.bss.*)
		*(COMMON)
	} > ROM :text
}

