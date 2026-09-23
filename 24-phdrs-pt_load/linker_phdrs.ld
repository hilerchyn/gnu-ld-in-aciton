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
	bss  PT_LOAD FLAGS(6);
}

SECTIONS
{
	.text :
	{
		*(.text)
		*(.text.*)
	} > ROM :text

	.rodata :
	{
		*(.rodata)
		*(.rodata.*)
	} > ROM :text

	.data :
	{
		__data_start = .;

		*(.data)
		*(.data.*)

		__data_end = .;
	} > RAM AT > ROM :data

	__data_load_start = LOADADDR(.data);
	__data_size = SIZEOF(.data);

	.bss :
	{
		__bss_start = .;

		*(.bss)
		*(.bss.*)
		*(COMMON)

		__bss_end = .;
	} > RAM :bss


	__bss_size = SIZEOF(.bss);
}


