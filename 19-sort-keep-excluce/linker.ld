ENTRY(_start)

MEMORY
{
	ROM (rx) : ORIGIN = 0x00400000, LENGTH = 64K
}

SECTIONS
{
	.text :
	{
		*(SORT(.text.*))
		*(.text)
	} > ROM

	.isr_vector :
	{
		KEEP (*(.isr_vector))
	} > ROM
}
