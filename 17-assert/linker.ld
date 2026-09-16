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

__stack_size = 8K;

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
		_srodata = .;

		*(.rodata)
		*(.rodata.*)

		_erodata = .;
	} > ROM :text

	.data :
	{
		_sdata = .;

		*(.data)
		*(.data.*)

		_edata = .;
	} > RAM AT > ROM :data

	_data_load = LOADADDR(.data)
	_data_load_end = LOADADDR(.data) + SIZEOF(.data);

	.bss :
	{
		_sbss = .;

		*(.bss)
		*(.bss.*)
		*(COMMON)

		_ebss = .;
	} > RAM :data

	. = ALIGN(16);

	__overlay_start = .;

	OVERLAY :
	{
		.overlay_a
		{
			*(.overlay_a)
		}

		.overlay_b
		{
			*(.overlay_b)
		}

		.overlay_c
		{
			*(.overlay_c)
		}
	} > RAM AT > ROM :data

	__overlay_end = .;

	__stack_top = ORIGIN(RAM) + LENGTH(RAM);
	__stack_start = __stack_top - __stack_size;

}

ASSERT(
        SIZEOF(.text) <= LENGTH(ROM),
	"ERROR: .text exceeds ROM"
)


