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

