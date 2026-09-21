SECTIONS
{
	.firmware_info :
	{
		__firmware_info_start = .;

		KEEP(*(.firmware_info))

		__firmware_info_end = .;
	}
}

INSERT AFTER .text;

ASSERT(
        SIZEOF(.firmware_info) == 16,
	"ERROR: invalid firmware info size"
);

