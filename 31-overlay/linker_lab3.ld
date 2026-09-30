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

    OVERLAY 0x00600000 : AT(0x00401000) 
    {
        .ov_a
        {
	    __load_start_ov_a = .;
            *(.ov_a)
	    __load_stop_ov_a = .;
        }

        .ov_b
        {
	    __load_start_ov_b = .;
            *(.ov_b)
	    __load_stop_ov_b = .;
        }

        .ov_c
        {
	    __load_start_ov_c = .;
            *(.ov_c)
	    __load_stop_ov_c = .;
        }
    } > RAM
}

