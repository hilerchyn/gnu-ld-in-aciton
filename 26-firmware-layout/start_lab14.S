.global _start

.extern main

.extern __data_load_start
.extern __data_start
.extern __data_end

.text

_start:

    lea __data_load_start(%rip), %rsi
    lea __data_start(%rip),      %rdi
    lea __data_end(%rip),        %rcx

    sub  %rdi, %rcx

    test %rcx, %rcx
    je   .data_done

.data_copy:
    movb (%rsi), %al
    movb %al,    (%rdi)

    inc %rsi
    inc %rdi
    dec %rcx

    jne .data_copy

.data_done:
    call main

.hang:
    hlt
    jmp .hang
