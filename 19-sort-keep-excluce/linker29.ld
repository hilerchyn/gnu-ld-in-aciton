ENTRY(_start)

MEMORY
{
	ROM (rx) : ORIGIN = 0x00400000, LENGTH = 64K
}

SECTIONS
{
	.text :
	{
		*(.text.*)
		*(.text)
	} > ROM

	.init_array :
	{
		KEEP (*(SORT(.init_array.*)))
		KEEP (*(.init_array))
	} > ROM
}
