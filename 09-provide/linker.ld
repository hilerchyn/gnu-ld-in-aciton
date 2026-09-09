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
}

SECTIONS
{
	.text :
	{
		PROVIDE_HIDDEN(image_start = .);

		*(.text)
		*(.text.*)

		PROVIDE_HIDDEN(image_end = .);

	} > ROM :text

}

PROVIDE(__ram_start = ORIGIN(RAM));
PROVIDE(__ram_end   = ORIGIN(RAM) + LENGTH(RAM));
PROVIDE(__stack_top = ORIGIN(RAM) + LENGTH(RAM));

