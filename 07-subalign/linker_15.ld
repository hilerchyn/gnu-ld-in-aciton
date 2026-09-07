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
        *(.text)
    } > ROM :text

    .foo :
    SUBALIGN(1)
    {
        foo_start = . ;

	*(.foo)

	foo_end = . ;
    } > ROM :text
}
