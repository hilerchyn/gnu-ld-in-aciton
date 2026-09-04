.global _start

.extern main

.extern _sidata
.extern _sdata
.extern _edata
.extern _sbss
.extern _ebss

_start:

    # --------------------------------
    # 1. copy .data
    # --------------------------------

    lea _sidata(%rip), %rsi
    lea _sdata(%rip), %rdi
    lea _edata(%rip), %rcx

    sub %rdi, %rcx

    # rcx = .data size
    # 如果 size == 0，则跳过

    test %rcx, %rcx
    jz .bss_init

.data_copy:
    mov (%rsi), %rax
    mov %rax, (%rdi)

    add $8, %rsi
    add $8, %rdi

    sub $8, %rcx
    jnz .data_copy

.bss_init:

    # --------------------------------
    # 2. clear .bss
    # --------------------------------

    lea _sbss(%rip), %rdi
    lea _ebss(%rip), %rcx

    sub %rdi, %rcx

    xor %rax, %rax

    test %rcx, %rcx
    jz .call_main

.bss_zero:
    mov %rax, (%rdi)

    add $8, %rdi
    sub $8, %rcx

    jnz .bss_zero

.call_main:

    # --------------------------------
    # 3. main()
    # --------------------------------

    call main

    # --------------------------------
    # 4. Linux exit
    # --------------------------------

    mov %eax, %edi
    mov $60, %eax
    syscall

.section .note.GNU-stack,"",@progbits

