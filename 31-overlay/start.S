.global _start

.extern main

.text

_start:
    call main

.hang:
    hlt
    jmp .hang

