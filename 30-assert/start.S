.global _start

.extern app_main

.text

_start:
    call app_main

.hang:
    hlt
    jmp .hang

