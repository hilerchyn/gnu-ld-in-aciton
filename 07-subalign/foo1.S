.section .foo,"a",@progbits
.p2align 2

foo1_begin:
    .byte 0x11
    .byte 0x12
    .byte 0x13
    .byte 0x14
foo1_end:

.section .note.GNU-stack,"",@progbits
