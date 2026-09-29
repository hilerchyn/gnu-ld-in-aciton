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

    .boot :
    {
        *(.boot)
    } > ROM

    .app :
    {
        *(.app)
    } > ROM
}

NOCROSSREFS(.boot .app);

