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

PROVIDE(__heap_size  = 8K);
PROVIDE(__stack_size = 8K);

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

	_data_load     = LOADADDR(.data);
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

	__heap_start = .;
	__heap_end   = __heap_start + __heap_size;

	__stack_top = ORIGIN(RAM) +LENGTH(RAM);
	__stack_start = __stack_top - __stack_size;
}

PROVIDE(__ram_start = ORIGIN(RAM));
PROVIDE(__ram_end   = ORIGIN(RAM) + LENGTH(RAM));

ASSERT(
        __heap_end <= __stack_start,
	"ERROR: heap overlaps stack"
);

ASSERT(
        __stack_start >= ORIGIN(RAM),
	"ERROR: stack start exceeds RAM"
);

ASSERT(
        __stack_top <= ORIGIN(RAM) + LENGTH(RAM),
	"ERROR: stack top exceeds RAM"
);

ASSERT(
        _data_load_end <= ORIGIN(ROM) + LENGTH(ROM),
	"ERROR: .data image exceeds ROM"
);

