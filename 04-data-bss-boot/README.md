# GNU ld 实战课程 · 实验 04

## 从 `_start` 到 `main`：手写 `.data` 拷贝与 `.bss` 清零

这一节开始进入 **真正的启动代码（startup code）**。

前面实验 03 我们已经让 linker 产生：

```text
.data
├── VMA → RAM
└── LMA → ROM
```

但这里有一个非常关键的问题：

> **`ld` 只负责“安排”和“记录”这些地址，它不会在程序启动时自动把 `.data` 从 ROM 拷贝到 RAM，也不会自动清零 `.bss`。**

真正执行这些动作的是：

```text
_start / Reset_Handler
        ↓
初始化 .data
        ↓
清零 .bss
        ↓
调用 main()
```

今天我们亲手把这条链路做出来。

---

# 一、今天实验完成后的完整启动流程

最终我们希望得到：

```text
                 linker.ld
                     │
          ┌──────────┼──────────┐
          │          │          │
          ▼          ▼          ▼
        .text      .data      .bss
          │          │          │
          │       LMA/VMA       │
          │          │          │
          ▼          ▼          ▼
         ROM        ROM        RAM
                    │
                    │ copy
                    ▼
                   RAM
                    │
                    │ zero
                    ▼
                  .bss
                    │
                    ▼
                  main()
```

其中：

```text
.data:
    ROM → RAM

.bss:
    RAM → 0
```

---

# 二、实验目录

继续沿用之前的目录：

```text
ld-lab/
├── main.c
├── start.S
└── linker.ld
```

这次把 `start.S` 改成真正的启动代码。

---

# 三、main.c

先写一个非常容易观察的程序：

```c
volatile int global_data = 123;

volatile int global_bss;

int main(void)
{
    global_bss = global_data + 1;

    return global_bss;
}
```

这里：

```text
global_data
      ↓
    .data

global_bss
      ↓
    .bss
```

我们最终希望：

```text
global_data = 123
global_bss  = 0       ← 启动时
```

然后：

```c
global_bss = global_data + 1;
```

执行后：

```text
global_bss = 124
```

最终：

```bash
./custom.elf
echo $?
```

得到：

```text
124
```

---

# 四、linker.ld：给启动代码提供“导航地图”

使用：

```ld
ENTRY(_start)

MEMORY
{
    ROM (rx)  : ORIGIN = 0x00400000, LENGTH = 64K
    RAM (rwx) : ORIGIN = 0x00600000, LENGTH = 64K
}

SECTIONS
{
    .text :
    {
        _stext = .;

        *(.text)

        _etext = .;
    } > ROM

    .rodata :
    {
        *(.rodata)
    } > ROM

    .data :
    {
        _sdata = .;

        *(.data)

        _edata = .;
    } > RAM AT > ROM

    _sidata = LOADADDR(.data);

    .bss :
    {
        _sbss = .;

        *(.bss)
        *(COMMON)

        _ebss = .;
    } > RAM
}
```

现在 linker 会产生：

```text
_sdata
_edata
_sidata

_sbss
_ebss
```

它们非常重要。

---

# 五、这几个符号到底是什么？

假设 linker 最终计算出来：

```text
_sidata = 0x00400080
_sdata  = 0x00600000
_edata  = 0x00600004

_sbss   = 0x00600004
_ebss   = 0x00600008
```

那么：

```text
ROM
0x00400080
     │
     │ .data 初始值
     │
     ▼
RAM
0x00600000
     │
     │ .data
     ▼
0x00600004
     │
     │ .bss
     ▼
0x00600008
```

因此：

```text
.data 长度：

_edata - _sdata
```

而：

```text
.bss 长度：

_ebss - _sbss
```

---

# 六、关键：start.S

这次不再简单地：

```asm
call main
```

而是：

```asm
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
```

不过这里有一个非常重要的实验性问题：

> 上面为了展示“copy/clear”的原理，直接按照 8 字节处理数据；真实 startup code 必须考虑 section 大小和对齐，否则如果 `.data` / `.bss` 不是 8 字节倍数就可能越界。

所以这次我们先让 linker **强制 8 字节对齐和 8 字节大小**。

---

# 七、让 linker 给我们一个干净的实验环境

修改：

```ld
.data ALIGN(8) :
{
    . = ALIGN(8);

    _sdata = .;

    *(.data)

    . = ALIGN(8);

    _edata = .;
} > RAM AT > ROM
```

`.bss`：

```ld
.bss ALIGN(8) :
{
    . = ALIGN(8);

    _sbss = .;

    *(.bss)
    *(COMMON)

    . = ALIGN(8);

    _ebss = .;
} > RAM
```

完整版本：

```ld
ENTRY(_start)

MEMORY
{
    ROM (rx)  : ORIGIN = 0x00400000, LENGTH = 64K
    RAM (rwx) : ORIGIN = 0x00600000, LENGTH = 64K
}

SECTIONS
{
    .text ALIGN(16) :
    {
        _stext = .;

        *(.text)

        _etext = .;
    } > ROM

    .rodata ALIGN(8) :
    {
        *(.rodata)
    } > ROM

    .data ALIGN(8) :
    {
        _sdata = .;

        *(.data)

        . = ALIGN(8);

        _edata = .;
    } > RAM AT > ROM

    _sidata = LOADADDR(.data);

    .bss ALIGN(8) :
    {
        _sbss = .;

        *(.bss)
        *(COMMON)

        . = ALIGN(8);

        _ebss = .;
    } > RAM
}
```

---

# 八、编译

执行：

```bash
rm -f *.o custom.elf custom.map
```

然后：

```bash
gcc -c main.c -o main.o
gcc -c start.S -o start.o
```

检查：

```bash
readelf -S main.o
```

重点：

```text
.text
.data
.bss
```

---

# 九、链接

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    -o custom.elf \
    -Map=custom.map
```

然后：

```bash
./custom.elf
echo $?
```

预期：

```text
124
```

---

# 十、现在开始真正分析 ELF

## 1. 看 Section

```bash
readelf -S custom.elf
```

重点找到：

```text
.text
.rodata
.data
.bss
```

---

## 2. 看 VMA/LMA

```bash
objdump -h custom.elf
```

重点看：

```text
.data
```

你应该看到类似：

```text
Idx Name      Size      VMA               LMA
...
.data         00000008  0000000000600000  00000000004000xx
```

这里：

```text
VMA = 0x00600000
LMA = 0x004000xx
```

这就是：

```text
ROM
0x004000xx
    │
    │ initial value
    ▼
RAM
0x00600000
```

---

# 十一、用 nm 看 linker 创建的符号

执行：

```bash
nm -n custom.elf
```

寻找：

```text
_sdata
_edata
_sidata
_sbss
_ebss
```

例如：

```text
00000000004000xx A _sidata
0000000000600000 D _sdata
0000000000600008 D _edata
0000000000600008 B _sbss
0000000000600010 B _ebss
```

这五个地址现在已经把整个启动过程描述出来了。

---

# 十二、用 `readelf -s` 再验证一次

执行：

```bash
readelf -s custom.elf | grep -E '_sdata|_edata|_sidata|_sbss|_ebss'
```

你会看到 linker script 定义的符号。

这一步非常重要，因为它让你看到：

```text
linker script
      ↓
symbol table
```

也就是说：

```ld
_sdata = .;
```

最终真的变成 ELF symbol。

---

# 十三、map 文件分析

执行：

```bash
grep -A 20 -B 5 "\.data" custom.map
```

你应该重点观察：

```text
.data
```

里面应该能看到：

```text
main.o
```

以及：

```text
global_data
```

然后：

```bash
grep -A 20 -B 5 "\.bss" custom.map
```

你会看到：

```text
.bss
    main.o
```

以及：

```text
global_bss
```

---

# 十四、把 map 文件和 nm 对起来

这是今天非常值得养成的习惯。

例如：

```text
map:

.data
0x00600000
    main.o(.data)
```

然后：

```bash
nm -n custom.elf
```

看到：

```text
00600000 D global_data
```

于是：

```text
map
 │
 ├── section 在哪里
 │
 └── 哪个 .o 放进来

nm
 │
 └── symbol 在哪里
```

两者结合：

```text
.data
  │
  └── main.o
        │
        └── global_data
              │
              └── 0x00600000
```

这就是以后排查：

```text
“为什么这个变量跑到这里了？”
```

最有效的办法之一。

---

# 十五、反汇编 `_start`

执行：

```bash
objdump -d custom.elf
```

寻找：

```text
_start
```

你会看到类似：

```text
0000000000400000 <_start>:
    ...
    lea    ...
    lea    ...
    ...
    call   ...
```

这里最值得观察的是：

```text
_start
   │
   ├── _sidata
   ├── _sdata
   ├── _edata
   ├── _sbss
   ├── _ebss
   │
   └── main
```

也就是说：

```text
startup assembly
        ↓
linker symbols
        ↓
memory initialization
```

三者真正连接起来了。

---

# 十六、这里有一个非常深的知识点

你可能会发现：

```asm
lea _sidata(%rip), %rsi
```

为什么可以直接使用：

```text
_sidata
```

？

因为：

```ld
_sidata = LOADADDR(.data);
```

在链接阶段已经把它变成了一个具体地址。

也就是说：

```text
源码：

_sidATA
    ↓
编译器：
“我先不知道它是多少”
    ↓
.o：
产生 relocation
    ↓
ld：
知道 _sidata
    ↓
修改机器码
    ↓
最终 ELF：
具体地址
```

这就是 **Relocation（重定位）** 最直观的一次实践。

---

# 十七、用 relocation 观察这个过程

在链接之前：

```bash
objdump -dr start.o
```

你会看到类似：

```text
R_X86_64_PC32
```

之类的 relocation。

这意味着：

> `start.o` 现在还不知道 `_sidata` 到底在哪里。

而链接之后：

```bash
objdump -d custom.elf
```

已经变成具体的机器指令和地址。

所以整个过程是：

```text
start.S
   ↓
gcc/as
   ↓
start.o
   │
   │ relocation
   ▼
ld
   │
   ├── symbol resolution
   ├── section placement
   ├── address calculation
   └── relocation
   │
   ▼
custom.elf
```

---

# 十八、这就是 ld 真正干的事情

现在回头看我们这几节实验：

### 实验 01

```text
.o → ELF
```

认识：

```text
symbol
section
relocation
```

### 实验 02

```text
-T linker.ld
```

开始控制：

```text
section address
```

### 实验 03

```text
MEMORY
> RAM
AT > ROM
```

控制：

```text
VMA
LMA
```

### 实验 04

```text
_sdata
_edata
_sidata
_sbss
_ebss
```

让：

```text
linker
      ↓
startup code
```

真正连接起来。

---

# 十九、当前阶段的完整脑图

```text
                    GNU ld
                      │
       ┌──────────────┼──────────────┐
       │              │              │
       ▼              ▼              ▼
   Symbol          Section       Relocation
   Resolution       Layout
       │              │              │
       │              ▼              │
       │          linker.ld           │
       │              │              │
       │       ┌──────┴──────┐        │
       │       ▼             ▼        │
       │      ROM           RAM       │
       │       │             │        │
       │       │             │        │
       │       └── .data ────┘        │
       │           LMA/VMA            │
       │                              │
       └──────────────┬───────────────┘
                      ▼
                   ELF
                      │
                      ▼
                startup code
                      │
             ┌────────┴────────┐
             ▼                 ▼
          copy .data        clear .bss
             │                 │
             └────────┬────────┘
                      ▼
                    main()
```

---

# 二十、下一关：Section 和 Segment

到这里我们已经开始触碰一个非常关键的问题：

```text
readelf -S
```

看到的是：

```text
Sections
```

而：

```bash
readelf -l
```

看到的是：

```text
Program Headers / Segments
```

它们**不是一回事**。

下一实验我们正式解决：

# 实验 05：Section → Segment

会直接分析：

```text
ELF
├── Section Header Table
│   ├── .text
│   ├── .rodata
│   ├── .data
│   └── .bss
│
└── Program Header Table
    ├── PT_LOAD R E
    ├── PT_LOAD RW
    └── ...
```

然后解释你之前遇到的这个警告：

```text
custom.elf has a LOAD segment with RWX permissions
```

并亲手用：

```ld
PHDRS
{
    text PT_LOAD FLAGS(5);
    data PT_LOAD FLAGS(6);
}
```

把：

```text
RWX
```

拆成：

```text
R E
RW
```

到那一步，你就会真正理解：

> **linker script 不只是决定“Section 放哪里”，还可以进一步决定“Segment 怎么交给 ELF loader”。**

这也是从“会写简单 `linker.ld`”迈向“能设计真正嵌入式/Bootloader 链接布局”的关键一步。

