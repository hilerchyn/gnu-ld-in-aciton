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
	} > ROM

	.custom :
	{
		*(.foo)
		*(.bar)
		*(.baz)
	} > ROM
}

