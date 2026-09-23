# GNU ld 实战课程 · 实验 23

## `AT()` + `LOADADDR()` + `ADDR()` + `SIZEOF()`：亲手制作 ROM → RAM 的完整启动镜像

上一节我们把 **Section Alignment** 彻底拆开了：

```text
Input Section Alignment
        ↓
Output Section Alignment
        ↓
Location Counter
        ↓
padding
        ↓
最终 VMA
```

现在进入 GNU ld 中真正开始“像做固件”的一节：

> **程序运行时的数据在 RAM，程序烧录时的数据却在 ROM。**

这正是 `.data` 的经典问题。

我们今天不再只看：

```ld
.data :
{
    *(.data)
} > RAM
```

而是最终做成：

```text
ROM
0x00400000
┌─────────────────────────────┐
│ .text                       │
│ .rodata                     │
│ .data 的初始化镜像           │
└─────────────────────────────┘
              │
              │ startup.S
              │ copy
              ▼
RAM
0x00600000
┌─────────────────────────────┐
│ .data                       │
│ .bss                        │
└─────────────────────────────┘
```

这一步会把：

```text
AT()
LOADADDR()
ADDR()
SIZEOF()
PROVIDE()
ASSERT()
```

第一次真正串起来。

---

# 一、实验 23 的最终目标

最终 ELF 中：

```text
.text
.rodata
.data
.bss
```

满足：

```text
.data VMA  → RAM
.data LMA  → ROM
```

也就是说：

```text
ADDR(.data)
```

得到：

```text
RAM 地址
```

而：

```text
LOADADDR(.data)
```

得到：

```text
ROM 中初始化镜像地址
```

然后：

```text
startup.S
```

执行：

```text
.data ROM 镜像
       │
       │ memcpy
       ▼
.data RAM
```

---

# 二、实验目录

建立：

```text
lab23/
├── start.S
├── main.c
├── data.c
├── linker.ld
└── Makefile
```

---

# 三、实验 23-1：制造一个真正需要初始化的 `.data`

`data.c`：

```c
int counter = 1234;

int magic = 0x12345678;

char message[] = "GNU ld";
```

这里三个变量：

```text
counter
magic
message
```

都是：

```text
已初始化
+
可写
```

所以应该进入：

```text
.data
```

---

# 四、先不要链接，观察 `.o`

编译：

```bash
gcc \
    -ffreestanding \
    -fno-pie \
    -fno-stack-protector \
    -fdata-sections \
    -c data.c \
    -o data.o
```

然后：

```bash
objdump -h data.o
```

应该看到类似：

```text
.data
.data.counter
.data.magic
.data.message
```

因为我们用了：

```bash
-fdata-sections
```

GCC 会尽量把不同数据对象放入独立的 input section。

这对理解 linker 非常有帮助。

---

# 五、查看实际初始化数据

执行：

```bash
objdump -s data.o
```

你会看到类似：

```text
78 56 34 12
D2 04 00 00
...
47 4E 55 20 6C 64
```

具体顺序取决于编译器。

但核心是：

> `.data` 的**初始值本身必须存在于文件镜像中**。

例如：

```c
int magic = 0x12345678;
```

程序启动以后希望：

```text
RAM[addr] = 0x12345678
```

那么这个 `0x12345678` 必须先存在于：

```text
ELF / Flash / ROM image
```

否则 CPU 启动时没有东西可以复制到 RAM。

---

# 六、实验 23-2：建立最小 `main.c`

```c
extern int counter;
extern int magic;
extern char message[];

int main(void)
{
    counter++;
    magic++;

    return message[0];
}
```

编译：

```bash
gcc \
    -ffreestanding \
    -fno-pie \
    -fno-stack-protector \
    -ffunction-sections \
    -c main.c \
    -o main.o
```

---

# 七、实验 23-3：启动代码

`start.S`：

```asm
.global _start

.extern main

.text

_start:
    call main
    hlt
```

先故意**不初始化 `.data`**。

编译：

```bash
gcc -c start.S -o start.o
```

---

# 八、实验 23-4：先做一个“错误但能链接”的版本

`linker.ld`：

```ld
ENTRY(_start)

MEMORY
{
    ROM (rx) : ORIGIN = 0x00400000, LENGTH = 64K
    RAM (rw) : ORIGIN = 0x00600000, LENGTH = 64K
}

SECTIONS
{
    .text :
    {
        *(.text)
        *(.text.*)
    } > ROM

    .rodata :
    {
        *(.rodata)
        *(.rodata.*)
    } > ROM

    .data :
    {
        *(.data)
        *(.data.*)
    } > RAM

    .bss :
    {
        *(.bss)
        *(.bss.*)
        *(COMMON)
    } > RAM
}
```

链接：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    data.o \
    -o bad-data.elf \
    -Map=bad-data.map
```

---

# 九、观察这个 ELF

```bash
readelf -S bad-data.elf
```

```text
There are 8 section headers, starting at offset 0x2170:

Section Headers:
  [Nr] Name              Type             Address           Offset
       Size              EntSize          Flags  Link  Info  Align
  [ 0]                   NULL             0000000000000000  00000000
       0000000000000000  0000000000000000           0     0     0
  [ 1] .text             PROGBITS         0000000000400000  00001000
       0000000000000038  0000000000000000  AX       0     0     1
  [ 2] .eh_frame         PROGBITS         0000000000400038  00001038
       0000000000000038  0000000000000000   A       0     0     8
  [ 3] .data             PROGBITS         0000000000600000  00002000
       000000000000000f  0000000000000000  WA       0     0     4
  [ 4] .comment          PROGBITS         0000000000000000  0000200f
       000000000000002d  0000000000000001  MS       0     0     1
  [ 5] .symtab           SYMTAB           0000000000000000  00002040
       00000000000000c0  0000000000000018           6     3     8
  [ 6] .strtab           STRTAB           0000000000000000  00002100
       0000000000000031  0000000000000000           0     0     1
  [ 7] .shstrtab         STRTAB           0000000000000000  00002131
       000000000000003a  0000000000000000           0     0     1
Key to Flags:
  W (write), A (alloc), X (execute), M (merge), S (strings), I (info),
  L (link order), O (extra OS processing required), G (group), T (TLS),
  C (compressed), x (unknown), o (OS specific), E (exclude),
  D (mbind), l (large), p (processor specific)
```

找到：

```text
.data
```

再：

```bash
objdump -h bad-data.elf
```

```text
bad-data.elf:     file format elf64-x86-64

Sections:
Idx Name          Size      VMA               LMA               File off  Algn
  0 .text         00000038  0000000000400000  0000000000400000  00001000  2**0
                  CONTENTS, ALLOC, LOAD, READONLY, CODE
  1 .eh_frame     00000038  0000000000400038  0000000000400038  00001038  2**3
                  CONTENTS, ALLOC, LOAD, READONLY, DATA
  2 .data         0000000f  0000000000600000  0000000000600000  00002000  2**2
                  CONTENTS, ALLOC, LOAD, DATA
  3 .comment      0000002d  0000000000000000  0000000000000000  0000200f  2**0
                  CONTENTS, READONLY
```

你会看到：

```text
.data
```

的地址位于：

```text
0x00600000
```

附近。

也就是说：

```text
VMA(.data)
=
RAM
```

这看起来没问题。

但是：

> **初始化数据也跟着进入了 RAM 的文件地址布局。**

这不是典型 MCU 固件想要的布局。

我们希望：

```text
运行地址：
RAM

加载地址：
ROM
```

---

# 十、VMA 与 LMA 再正式定义一次

这是本实验最重要的概念。

## VMA

Virtual Memory Address：

```text
程序运行时地址
```

对于：

```text
.data
```

我们希望：

```text
VMA = RAM
```

---

## LMA

Load Memory Address：

```text
程序加载/烧录时的数据地址
```

对于：

```text
.data
```

我们希望：

```text
LMA = ROM
```

于是：

```text
.data
```

有两个地址：

```text
LMA
 ↓
ROM 中保存初始化值

VMA
 ↓
RAM 中运行
```

---

# 十一、实验 23-5：使用 `AT()`

把：

```ld
.data :
{
    *(.data)
    *(.data.*)
} > RAM
```

改成：

```ld
.data :
{
    *(.data)
    *(.data.*)
} > RAM AT > ROM
```

完整：

```ld
.data :
{
    *(.data)
    *(.data.*)
} > RAM AT > ROM
```

这里发生了一件非常重要的事情：

```text
> RAM
```

决定：

```text
VMA
```

而：

```text
AT > ROM
```

决定：

```text
LMA
```

因此：

```text
.data
VMA → RAM
LMA → ROM
```

---

# 十二、重新链接

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    data.o \
    -o data-at.elf \
    -Map=data-at.map
```

---

# 十三、第一次正式验证

执行：

```bash
readelf -S data-at.elf
```

```text

There are 8 section headers, starting at offset 0x2170:

Section Headers:
  [Nr] Name              Type             Address           Offset
       Size              EntSize          Flags  Link  Info  Align
  [ 0]                   NULL             0000000000000000  00000000
       0000000000000000  0000000000000000           0     0     0
  [ 1] .text             PROGBITS         0000000000400000  00001000
       0000000000000038  0000000000000000  AX       0     0     1
  [ 2] .eh_frame         PROGBITS         0000000000400038  00001038
       0000000000000038  0000000000000000   A       0     0     8
  [ 3] .data             PROGBITS         0000000000600000  00002000
       000000000000000f  0000000000000000  WA       0     0     4
  [ 4] .comment          PROGBITS         0000000000000000  0000200f
       000000000000002d  0000000000000001  MS       0     0     1
  [ 5] .symtab           SYMTAB           0000000000000000  00002040
       00000000000000c0  0000000000000018           6     3     8
  [ 6] .strtab           STRTAB           0000000000000000  00002100
       0000000000000031  0000000000000000           0     0     1
  [ 7] .shstrtab         STRTAB           0000000000000000  00002131
       000000000000003a  0000000000000000           0     0     1
Key to Flags:
  W (write), A (alloc), X (execute), M (merge), S (strings), I (info),
  L (link order), O (extra OS processing required), G (group), T (TLS),
  C (compressed), x (unknown), o (OS specific), E (exclude),
  D (mbind), l (large), p (processor specific)
```

观察：

```text
.data
```

它的：

```text
Address
```

应该位于：

```text
0x00600000
```

附近。

也就是说：

```text
VMA = RAM
```

---

# 十四、再看 Program Header

执行：

```bash
readelf -l data-at.elf
```

```text


Elf file type is EXEC (Executable file)
Entry point 0x400000
There are 3 program headers, starting at offset 64

Program Headers:
  Type           Offset             VirtAddr           PhysAddr
                 FileSiz            MemSiz              Flags  Align
  LOAD           0x0000000000001000 0x0000000000400000 0x0000000000400000
                 0x0000000000000070 0x0000000000000070  R E    0x1000
  LOAD           0x0000000000002000 0x0000000000600000 0x0000000000400070
                 0x000000000000000f 0x000000000000000f  RW     0x1000
  GNU_STACK      0x0000000000000000 0x0000000000000000 0x0000000000000000
                 0x0000000000000000 0x0000000000000000  RWE    0x10

 Section to Segment mapping:
  Segment Sections...
   00     .text .eh_frame 
   01     .data 
   02     
```

这次不要只看 Section。

重点看：

```text
LOAD
```

以及：

```text
Section to Segment mapping
```

你会开始看到：

```text
.text
.rodata
.data
```

在：

```text
PT_LOAD
```

中的映射关系。

---

# 十五、`objdump -h` 是第二个证据

执行：

```bash
objdump -h data-at.elf
```

```text


data-at.elf:     file format elf64-x86-64

Sections:
Idx Name          Size      VMA               LMA               File off  Algn
  0 .text         00000038  0000000000400000  0000000000400000  00001000  2**0
                  CONTENTS, ALLOC, LOAD, READONLY, CODE
  1 .eh_frame     00000038  0000000000400038  0000000000400038  00001038  2**3
                  CONTENTS, ALLOC, LOAD, READONLY, DATA
  2 .data         0000000f  0000000000600000  0000000000400070  00002000  2**2
                  CONTENTS, ALLOC, LOAD, DATA
  3 .comment      0000002d  0000000000000000  0000000000000000  0000200f  2**0
                  CONTENTS, READONLY
```

这里可以看到：

```text
VMA
LMA
```

这是非常关键的。

你可能看到类似：

```text
Idx Name       Size      VMA               LMA
...
.data          0000000c  0000000000600000  00000000004000xx
```

这就是我们想看到的：

```text
.data VMA
    ↓
0x0060....

.data LMA
    ↓
0x0040....
```

---

# 十六、这里出现了一个极其重要的关系

假设：

```text
ADDR(.data)
=
0x00600000
```

而：

```text
LOADADDR(.data)
=
0x00400080
```

那么：

```text
.data 初始化镜像
```

位于：

```text
ROM
0x00400080
```

启动以后：

```text
RAM
0x00600000
```

需要得到同样的数据。

于是：

```text
copy source
=
LOADADDR(.data)

copy destination
=
ADDR(.data)
```

这就是后面 startup.S 的核心。

---

# 十七、实验 23-6：使用 `ADDR()`

在 linker script 中：

```ld
.data :
{
    __data_start = .;

    *(.data)
    *(.data.*)

    __data_end = .;
} > RAM AT > ROM
```

现在：

```text
__data_start
```

等价于：

```text
ADDR(.data)
```

而：

```text
__data_end
```

就是：

```text
ADDR(.data) + SIZEOF(.data)
```

---

# 十八、使用 `SIZEOF()`

可以定义：

```ld
__data_size = SIZEOF(.data);
```

于是：

```text
__data_start
__data_end
__data_size
```

形成：

```text
start
 │
 ├────────── data
 │
end

size = end - start
```

---

# 十九、加入 `LOADADDR()`

现在：

```ld
__data_load_start = LOADADDR(.data);
```

完整：

```ld
.data :
{
    __data_start = .;

    *(.data)
    *(.data.*)

    __data_end = .;
} > RAM AT > ROM

__data_load_start = LOADADDR(.data);
__data_size = SIZEOF(.data);
```

现在 linker 给我们生成了：

```text
__data_start
__data_end
__data_load_start
__data_size
```

---

# 二十、查看符号

重新链接：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    data.o \
    -o data-symbols.elf \
    -Map=data-symbols.map
```

执行：

```bash
nm -n data-symbols.elf | grep data
```

```text

000000000000000f A __data_size
0000000000400070 A __data_load_start
0000000000600000 D __data_start
000000000060000f D __data_end
```

可能看到：

```text
000000000040....
__data_load_start

0000000000600000
__data_start

000000000060000c
__data_end

000000000000000c
__data_size
```

这里最重要的是：

```text
__data_load_start
```

和：

```text
__data_start
```

不一样。

---

# 二十一、Map 文件分析

打开：

```bash
less data-symbols.map
```

找到：

```text
.data
```

你应该看到类似：

```text
.data           0x0000000000600000
                0x0000000000600000 __data_start = .

 *(.data)
 .data          0x0000000000600000 ...
 .data.magic    0x0000000000600000 ...
 .data.counter  0x0000000000600004 ...
 .data.message  0x0000000000600008 ...

                0x000000000060000c __data_end = .
```

然后：

```text
__data_load_start
```

会对应 ROM 中的装载地址。

---

# 二十二、现在真正理解 `AT > ROM`

这一行：

```ld
.data :
{
    ...
} > RAM AT > ROM
```

可以拆成：

```text
.data
  │
  ├── VMA → RAM
  │
  └── LMA → ROM
```

因此：

```text
> RAM
```

回答：

> **程序运行时在哪里？**

而：

```text
AT > ROM
```

回答：

> **初始化镜像从哪里加载？**

---

# 二十三、实验 23-7：把 `.rodata` 加入 ROM

```ld
.rodata :
{
    *(.rodata)
    *(.rodata.*)
} > ROM
```

这样：

```text
ROM
├── .text
├── .rodata
└── .data 的初始化镜像
```

RAM：

```text
RAM
├── .data
└── .bss
```

这是典型 MCU 布局。

---

# 二十四、但是现在还有一个坑

我们写：

```ld
.data > RAM AT > ROM
```

并不意味着：

> `.data` 的 LMA 一定紧紧跟在 `.rodata` 后面。

ld 会根据当前的 load address 和其他布局规则安排它。

所以必须：

```text
readelf
+
objdump
+
Map
```

一起确认。

不要仅凭 linker script 猜地址。

---

# 二十五、实验 23-8：用显式 `AT()`

我们也可以不写：

```ld
AT > ROM
```

而使用：

```ld
AT(ADDR(.rodata) + SIZEOF(.rodata))
```

例如：

```ld
.data :
{
    __data_start = .;

    *(.data)
    *(.data.*)

    __data_end = .;
}
> RAM
AT(ADDR(.rodata) + SIZEOF(.rodata))
```

于是：

```text
.data LMA
=
.rodata VMA
+
.rodata Size
```

不过这里有一个工程上的重要提醒：

> **在复杂脚本中，最好明确区分 VMA 与 LMA 的布局，而不要随意假设“ROM 当前地址就是某个 VMA”。**

尤其加入：

```text
PHDRS
ALIGN
padding
多个 LOAD segment
```

以后，简单公式很容易失效。

---

# 二十六、推荐的固件写法

对于现在这个阶段，我更推荐：

```ld
.data :
{
    __data_start = .;

    *(.data)
    *(.data.*)

    __data_end = .;
} > RAM AT > ROM

__data_load_start = LOADADDR(.data);
__data_size = SIZEOF(.data);
```

原因很简单：

```text
AT > ROM
```

让 ld 负责计算真正的 LMA。

然后：

```text
LOADADDR(.data)
```

让我们获取最终结果。

也就是：

```text
让 linker 算
+
我们读取结果
```

而不是：

```text
我们自己猜
```

---

# 二十七、实验 23-9：第一次真正修改 `start.S`

现在我们有：

```text
__data_load_start
__data_start
__data_size
```

于是启动代码可以做：

```text
ROM
 │
 │ __data_load_start
 ▼
[初始化数据]
 │
 │ copy
 ▼
RAM
 │
 │ __data_start
 ▼
[data]
```

---

# 二十八、实现一个最小的 `memcpy`

为了避免依赖 libc：

```asm
.global memcpy_simple

memcpy_simple:
    # rdi = dst
    # rsi = src
    # rdx = size

    test %rdx, %rdx
    je .done

.loop:
    movb (%rsi), %al
    movb %al, (%rdi)

    inc %rsi
    inc %rdi
    dec %rdx

    jne .loop

.done:
    ret
```

这里采用 x86-64 System V ABI：

```text
RDI = 第 1 参数
RSI = 第 2 参数
RDX = 第 3 参数
```

---

# 二十九、启动代码

修改 `start.S`：

```asm
.global _start

.extern main

.extern __data_load_start
.extern __data_start
.extern __data_size

.text

_start:

    lea __data_start(%rip), %rdi
    lea __data_load_start(%rip), %rsi
    mov $__data_size, %rdx

    call memcpy_simple

    call main

    hlt


memcpy_simple:

    test %rdx, %rdx
    je .done

.loop:

    movb (%rsi), %al
    movb %al, (%rdi)

    inc %rsi
    inc %rdi
    dec %rdx

    jne .loop

.done:

    ret
```

---

# 三十、这里有一个值得特别注意的问题

你可能会问：

> `.data` 的 LMA 在 ROM，为什么 startup.S 可以直接访问？

因为：

```text
ELF
```

最终会把 `.data` 的初始化内容作为可加载数据放到对应的 `PT_LOAD` 中。

也就是说：

```text
ROM image
```

里面实际上包含：

```text
.text
.rodata
.data initial values
```

而：

```text
RAM
```

里面最终运行的是：

```text
.data
.bss
stack
heap
```

---

# 三十一、实验 23-10：编译完整程序

```bash
gcc \
    -ffreestanding \
    -fno-pie \
    -fno-stack-protector \
    -fdata-sections \
    -c data.c \
    -o data.o
```

```bash
gcc \
    -ffreestanding \
    -fno-pie \
    -fno-stack-protector \
    -ffunction-sections \
    -c main.c \
    -o main.o
```

```bash
gcc -c start.S -o start.o
```

链接：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    data.o \
    -o firmware.elf \
    -Map=firmware.map
```

---

# 三十二、验证 `.data`

```bash
readelf -S firmware.elf
```

找到：

```text
.data
```

再：

```bash
objdump -h firmware.elf
```

重点记录：

```text
.data
VMA = ?
LMA = ?
Size = ?
Align = ?
```

然后：

```bash
nm -n firmware.elf | grep __data
```

你应该能建立：

```text
__data_load_start
       │
       │ ROM
       ▼
[1234][magic]["GNU ld"]
       │
       │ copy
       ▼
__data_start
       │
       ▼
RAM .data
       │
__data_end
```

---

# 三十三、实验 23-11：验证 `ADDR()` 与 `LOADADDR()`

在 linker script 中再增加：

```ld
__data_vma = ADDR(.data);
__data_lma = LOADADDR(.data);
```

完整：

```ld
__data_vma = ADDR(.data);
__data_lma = LOADADDR(.data);
__data_size = SIZEOF(.data);
```

重新链接：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    data.o \
    -o firmware-symbols.elf \
    -Map=firmware-symbols.map
```

查看：

```bash
nm -n firmware-symbols.elf | grep __data
```

现在应该能明确看到：

```text
__data_vma
__data_start

__data_lma
__data_load_start

__data_size
```

---

# 三十四、四个符号之间的关系

最终：

```text
__data_start
=
ADDR(.data)
```

```text
__data_load_start
=
LOADADDR(.data)
```

```text
__data_end
=
ADDR(.data) + SIZEOF(.data)
```

```text
__data_size
=
SIZEOF(.data)
```

所以：

```text
RAM destination:
[__data_start, __data_end)

ROM source:
[__data_load_start, __data_load_start + __data_size)
```

这就是启动代码真正需要的数学模型。

---

# 三十五、实验 23-12：`ASSERT()` 检查 RAM

现在加入：

```ld
ASSERT(
    __data_end <= ORIGIN(RAM) + LENGTH(RAM),
    "ERROR: .data exceeds RAM"
);
```

---

# 三十六、检查 ROM

再检查：

```ld
ASSERT(
    LOADADDR(.data) + SIZEOF(.data)
        <= ORIGIN(ROM) + LENGTH(ROM),
    "ERROR: .data load image exceeds ROM"
);
```

于是我们开始拥有：

```text
RAM 安全检查
+
ROM 安全检查
```

---

# 三十七、`.bss` 又是什么？

现在：

```c
int counter = 1234;
```

进入：

```text
.data
```

但如果：

```c
int counter;
```

没有显式初始化：

```text
counter = 0
```

通常进入：

```text
.bss
```

`.bss` 的特点：

```text
运行时需要空间
+
初始值全为 0
+
通常不需要把大量 0 存进 ROM image
```

所以：

```text
.data
需要：
ROM initial image

.bss
不需要：
ROM initial image
```

这就是：

```text
.data
ROM → RAM copy

.bss
RAM → memset 0
```

---

# 三十八、实验 23-13：增加 `.bss`

`data.c`：

```c
int counter = 1234;

int magic = 0x12345678;

char message[] = "GNU ld";

int uninitialized_buffer[1024];
```

编译：

```bash
gcc \
    -ffreestanding \
    -fno-pie \
    -fno-stack-protector \
    -fdata-sections \
    -c data.c \
    -o data.o
```

检查：

```bash
objdump -h data.o
```

应该看到：

```text
.data
.bss
```

---

# 三十九、linker script

```ld
.bss :
{
    __bss_start = .;

    *(.bss)
    *(.bss.*)
    *(COMMON)

    __bss_end = .;
} > RAM

__bss_size = SIZEOF(.bss);
```

---

# 四十、为什么 `.bss` 不需要 `AT > ROM`？

因为：

```text
.bss
```

里面没有真正需要存储的初始化字节。

它只需要：

```text
RAM 空间
```

所以：

```text
.data
VMA RAM
LMA ROM

.bss
VMA RAM
没有实际 ROM image
```

---

# 四十一、`readelf -S` 会告诉你答案

执行：

```bash
readelf -S firmware.elf
```

观察：

```text
.data
```

和：

```text
.bss
```

其中 `.bss` 通常是：

```text
NOBITS
```

而 `.data` 是：

```text
PROGBITS
```

这是极其重要的 ELF 知识：

```text
.data
SHT_PROGBITS
```

意味着：

> 文件中存在实际数据。

而：

```text
.bss
SHT_NOBITS
```

意味着：

> 文件中不需要保存这些零值字节，但运行时需要占用内存。

---

# 四十二、实验 23-14：验证文件大小

执行：

```bash
ls -lh firmware.elf
```

再：

```bash
size firmware.elf
```

`size` 通常显示：

```text
text
data
bss
```

例如：

```text
text   data   bss
...    ...    4096
```

这里：

```text
bss
```

可能很大。

但是：

```text
ELF 文件
```

并不会因此增加同样大小的实际数据。

这就是：

```text
NOBITS
```

的意义。

---

# 四十三、Map 文件分析：`.data`

现在打开：

```bash
less firmware.map
```

定位：

```text
.data
```

分析：

```text
VMA
LMA
size
input sections
```

你应该能回答四个问题：

```text
1. .data 在 RAM 的什么地址？
2. .data 初始化镜像在 ROM 的什么地址？
3. .data 有多少字节？
4. 哪几个 .o 贡献了这些数据？
```

如果不能从 Map 回答：

> 说明你还没有真正掌握这个 linker script。

---

# 四十四、Map 文件分析：`.bss`

再找到：

```text
.bss
```

回答：

```text
1. .bss VMA 是多少？
2. size 是多少？
3. 为什么没有对应的 ROM 数据？
4. 哪些 input section 贡献了 .bss？
```

这一步非常重要。

---

# 四十五、实验 23-15：完整启动流程

现在整个系统终于形成：

```text
               ELF
                │
       ┌────────┴─────────┐
       │                  │
      ROM                RAM
       │                  │
       │                  │
   .text                 .data
   .rodata               .bss
   .data image
       │                  │
       │                  │
       └──── startup ─────┘
               │
               ▼
        copy .data
               │
               ▼
        clear .bss
               │
               ▼
             main()
```

---

# 四十六、启动代码再完善一步：清零 `.bss`

增加：

```asm
.extern __bss_start
.extern __bss_end
```

然后：

```asm
    lea __bss_start(%rip), %rdi
    lea __bss_end(%rip), %rcx

    sub %rdi, %rcx

    xor %rax, %rax

    mov %rcx, %rdx
    shr $3, %rcx

    rep stosq

    mov %rdx, %rcx
    and $7, %rcx
    rep stosb
```

核心思想就是：

```text
bss_start
    ↓
清零
    ↓
bss_end
```

---

# 四十七、现在 startup.S 做了两件事

```text
_start
   │
   ├── copy .data
   │
   ├── clear .bss
   │
   └── call main
```

这就是裸机程序启动的基本模型。

---

# 四十八、完整 linker.ld

现在可以整理成：

```ld
ENTRY(_start)

MEMORY
{
    ROM (rx) : ORIGIN = 0x00400000, LENGTH = 64K
    RAM (rw) : ORIGIN = 0x00600000, LENGTH = 64K
}

SECTIONS
{
    .text :
    {
        _stext = .;

        *(.text)
        *(.text.*)

        _etext = .;
    } > ROM

    .rodata :
    {
        _srodata = .;

        *(.rodata)
        *(.rodata.*)

        _erodata = .;
    } > ROM

    .data :
    {
        __data_start = .;

        *(.data)
        *(.data.*)

        __data_end = .;
    } > RAM AT > ROM

    __data_load_start = LOADADDR(.data);
    __data_size = SIZEOF(.data);

    .bss :
    {
        __bss_start = .;

        *(.bss)
        *(.bss.*)
        *(COMMON)

        __bss_end = .;
    } > RAM

    __bss_size = SIZEOF(.bss);

    ASSERT(
        __data_end <= ORIGIN(RAM) + LENGTH(RAM),
        "ERROR: .data exceeds RAM"
    );

    ASSERT(
        __bss_end <= ORIGIN(RAM) + LENGTH(RAM),
        "ERROR: .bss exceeds RAM"
    );

    ASSERT(
        LOADADDR(.data) + SIZEOF(.data)
            <= ORIGIN(ROM) + LENGTH(ROM),
        "ERROR: .data load image exceeds ROM"
    );
}
```

---

# 四十九、这份 linker script 已经具备了什么能力？

现在它已经能：

```text
① 定义 ROM / RAM
② 放置 .text
③ 放置 .rodata
④ 把 .data VMA 放到 RAM
⑤ 把 .data LMA 放到 ROM
⑥ 提供 .data copy 信息
⑦ 定义 .bss
⑧ 提供 .bss clear 信息
⑨ 检查 RAM overflow
⑩ 检查 ROM overflow
```

这已经不是“学习用 linker script”了。

它已经接近真正的：

# MCU Firmware Linker Script

---

# 五十、实验 23 最重要的四个函数

以后看到：

```ld
ADDR()
LOADADDR()
SIZEOF()
AT()
```

立刻想到：

```text
AT()
 ↓
告诉 ld：
VMA 和 LMA 不同
```

```text
ADDR(.data)
 ↓
得到运行地址
```

```text
LOADADDR(.data)
 ↓
得到加载地址
```

```text
SIZEOF(.data)
 ↓
得到需要复制多少字节
```

所以：

```text
source
=
LOADADDR(.data)

destination
=
ADDR(.data)

length
=
SIZEOF(.data)
```

这三元组就是：

# `.data` 初始化复制的完整参数。

---

# 五十一、最终验证命令清单

这一节建议你每次都完整执行：

### 1. Input Section

```bash
objdump -h data.o
```

### 2. ELF Section

```bash
readelf -S firmware.elf
```

### 3. VMA/LMA

```bash
objdump -h firmware.elf
```

### 4. Segment

```bash
readelf -l firmware.elf
```

### 5. Symbols

```bash
nm -n firmware.elf
```

### 6. 反汇编

```bash
objdump -d firmware.elf
```

### 7. 数据

```bash
objdump -s firmware.elf
```

### 8. Size

```bash
size firmware.elf
```

### 9. Map

```bash
less firmware.map
```

---

# 五十二、建立一张最终分析表

| 项目             | 工具                  | 要回答的问题                    |
| -------------- | ------------------- | ------------------------- |
| Input `.data`  | `objdump -h data.o` | 数据来自哪里？                   |
| Output `.data` | `readelf -S`        | VMA 是多少？                  |
| LMA            | `objdump -h`        | ROM 地址是多少？                |
| Segment        | `readelf -l`        | 哪个 PT_LOAD 保存初始化镜像？       |
| Symbols        | `nm`                | start/end/load/size 是否正确？ |
| Copy           | `objdump -d`        | startup 是否使用这些符号？         |
| 数据             | `objdump -s`        | ROM 中真的存在初始化值吗？           |
| `.bss`         | `readelf -S`        | 是否为 NOBITS？               |
| Layout         | `map`               | 哪个 `.o` 贡献了多少？            |

---

# 五十三、这一节最核心的一张图

```text
                  linker script
                       │
                       │
              .data > RAM AT > ROM
                       │
          ┌────────────┴────────────┐
          │                         │
          ▼                         ▼
       VMA                       LMA
          │                         │
          │                         │
     ADDR(.data)             LOADADDR(.data)
          │                         │
          ▼                         ▼
        RAM                       ROM
          │                         │
          │                    初始化镜像
          │                         │
          └──────────┬──────────────┘
                     │
                     │ startup.S
                     │
                     ▼
                 memcpy
                     │
                     ▼
                   .data
                     │
                     ▼
                   main()
```

---

# 五十四、把课程路线推进到下一阶段

现在课程已经从：

```text
实验 20
Orphan Sections
        ↓
实验 21
INSERT BEFORE / AFTER
        ↓
实验 22
ALIGN / SUBALIGN / ALIGN_WITH_INPUT
        ↓
实验 23
AT / ADDR / LOADADDR / SIZEOF
```

进入真正的：

# 固件链接阶段

下一实验将继续做：

## 实验 24：`PHDRS` + `PT_LOAD`——从 Section 布局进入 Segment/镜像布局

我们会把现在的：

```text
.text
.rodata
.data
.bss
```

进一步控制成明确的：

```text
PT_LOAD RX
PT_LOAD RW
```

并解决几个非常关键的问题：

```text
为什么 readelf -S 看起来正确，
readelf -l 却不对？

为什么 `.data` 明明 VMA 在 RAM，
ELF 文件里的 LOAD segment 却还包含 ROM 内容？

为什么会出现：

LOAD segment with RWX permissions

为什么 `PHDRS` 写错后会导致：
section 到 segment 的映射完全改变？

为什么：
```

```ld
PHDRS
{
    text PT_LOAD FLAGS(5);
    data PT_LOAD FLAGS(6);
}
```

会把我们前面学过的：

```text
Section
VMA
LMA
AT()
ROM
RAM
```

真正统一成：

```text
ELF Program Header
        ↓
PT_LOAD
        ↓
文件加载
        ↓
内存权限
        ↓
ROM/RAM 镜像
```

下一阶段会正式从“**Section Linker Script**”进入“**ELF Segment Linker Script**”，这是 GNU `ld` 学习中非常关键的一道分水岭。

