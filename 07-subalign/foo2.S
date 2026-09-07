.section .foo,"a",@progbits
.p2align 4

foo2_begin:
    .byte 0x21
    .byte 0x22
    .byte 0x23
    .byte 0x24
foo2_end:

.section .note.GNU-stack,"",@progbits

