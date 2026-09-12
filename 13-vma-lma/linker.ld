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
		_stext = .;

		*(*.text)
		*(*.text.*)

		_etext = .;
	} > ROM :text


	.rodata :
	{
		*(.rodata)
		*(.rodata.*)
	} > ROM :text

	.data :
	{
		_sdata = .;

		*(.data)
		*(.data.*)

		_edata = .;
	} > RAM AT > ROM :data

}
