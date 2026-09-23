.global _start

.extern main

.extern __data_load_start
.extern __data_start
.extern __data_size

.text

_start:
    lea __data_start(%rip), %rdi
    lea __data_load_start(%rip), %rsi
    move $__data_size, %rdx

    call memcpy_simple

    call main

    hlt

memcpy_simple:

    test %rdx, %rdx
    je .done

.loop:

    movb (%rsi), %al
    movb %al,    (%rdi)

    inc %rsi
    inc %rdi
    dec %rdx


    jne .loop

.done:

    ret
