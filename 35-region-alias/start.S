.global _start

.section .text.start
_start:
    call main

1:
    jmp 1b

