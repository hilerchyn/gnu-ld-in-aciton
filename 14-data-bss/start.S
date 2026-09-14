.global _start

.extern copy_data
.extern clear_bss
.extern main

_start:
    call copy_data
    call clear_bss
    call main

    mov %eax, %edi
    mov $60,  %eax
    syscall

.section .note.GNU-stack,"",@progbits


