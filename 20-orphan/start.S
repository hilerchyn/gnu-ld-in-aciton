.global _start

.text

_start:
    call main
    hlt

.section .note.GNU-stack,"",@progbits

