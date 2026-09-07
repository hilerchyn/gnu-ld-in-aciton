.section .foo,"a",@progbits
.p2align 5

foo3_begin:
    .byte 0x31
    .byte 0x32
    .byte 0x33
    .byte 0x34
foo3_end:

.section .note.GNU-stack,"",@progbits
