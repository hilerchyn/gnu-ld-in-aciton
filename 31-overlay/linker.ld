ENTRY(_start)

MEMORY
{
    ROM (rx) :
        ORIGIN = 0x00400000,
        LENGTH = 64K

    RAM (rwx) :
        ORIGIN = 0x00600000,
        LENGTH = 64K
}

SECTIONS
{
    .text :
    {
        *(.text)
        *(.text.*)
    } > ROM

    .ov_a :
    {
        *(.ov_a)
    } > RAM AT > ROM

    .ov_b :
    {
        *(.ov_b)
    } > RAM AT > ROM

    .ov_c :
    {
        *(.ov_c)
    } > RAM AT > ROM
}

