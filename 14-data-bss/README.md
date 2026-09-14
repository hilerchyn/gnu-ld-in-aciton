# GNU ld 实战课程 · 实验 14

## `.data` 搬运与 `.bss` 清零：从 linker script 真正构造启动代码

上一节我们已经搞清楚：

```text
.data
├── VMA  → RAM
└── LMA  → ROM
```

以及：

```ld
ADDR(.data)
LOADADDR(.data)
SIZEOF(.data)
```

这一节不再停留在“看地址”，而是把它们真正用于启动代码：

```text
            ELF / Flash Image
                  │
                  │ LMA
                  ▼
              .data image
                  │
                  │ copy
                  ▼
RAM ─────────── .data ───────────
                  │
                  │
RAM ─────────── .bss ────────────
                  │
                  │ zero
                  ▼
              all zero
```

最终我们会实现一个最小的：

```text
_start
  ↓
init_data()
  ↓
init_bss()
  ↓
main()
```

这已经非常接近真正 MCU/裸机程序的启动过程了。

---

# 一、实验目标

本节完成 6 个实验：

```text
14-1  构造 .data / .bss
14-2  linker 自动生成启动符号
14-3  C 实现 data copy / bss zero
14-4  Assembly 调用初始化函数
14-5  readelf / objdump 验证
14-6  Map 文件反向验证整个内存布局
```

核心目标：

> **理解 linker script 如何把“链接时的地址信息”变成“启动代码可以直接使用的运行时信息”。**

---

# 二、实验目录

```text
ld-lab/
├── start.S
├── init.c
├── main.c
└── linker.ld
```

---

# 三、先明确我们模拟的内存

仍然使用：

```text
ROM
0x00400000
64 KB

RAM
0x00600000
64 KB
```

布局：

```text
ROM
0x00400000
│
├── .text
│
├── .rodata
│
└── .data 的初始化镜像
       │
       │ LMA
       │
       ▼
RAM
0x00600000
│
├── .data
│
└── .bss
```

---

# 四、main.c

先构造三个全局对象：

```c
int initialized_value = 0x12345678;

int zero_value;

int main(void)
{
    if (initialized_value != 0x12345678)
        return 1;

    if (zero_value != 0)
        return 2;

    return 0;
}
```

这里故意设计成：

```text
initialized_value
        ↓
      .data

zero_value
        ↓
      .bss
```

因此：

```text
.data
```

必须：

```text
ROM → RAM
```

而：

```text
.bss
```

必须：

```text
RAM → 0
```

---

# 五、先编译 main.c

```bash
gcc -ffreestanding -fno-pie -c main.c -o main.o
```

这里开始使用：

```text
-freestanding
```

因为我们的目标是模拟：

```text
bare-metal
```

而不是正常 Linux 用户程序。

---

# 六、观察 main.o

```bash
nm main.o
```

应该看到类似：

```text
0000000000000000 D initialized_value
0000000000000000 B zero_value
0000000000000000 T main
```

重点：

```text
D initialized_value
```

说明：

```text
initialized_value
    ↓
.data
```

而：

```text
B zero_value
```

说明：

```text
zero_value
    ↓
.bss
```

---

# 七、先看 `.data` 的原始内容

```bash
objdump -s -j .data main.o
```

你应该能看到：

```text
78 56 34 12
```

如果目标是 x86-64，小端序下：

```text
0x12345678
```

在文件中就是：

```text
78 56 34 12
```

这一步非常关键。

它说明：

> `.data` 不只是“一个地址”，它在 `.o` 中确实携带初始化数据。

---

# 八、`.bss` 再看一次

```bash
objdump -h main.o
```

观察：

```text
.data
.bss
```

然后：

```bash
objdump -s -j .bss main.o
```

通常不会像 `.data` 一样看到大量 `00` 数据。

原因就是：

```text
.bss
=
NOBITS
```

它只需要：

```text
size
```

而不需要在文件中保存：

```text
size 个 0
```

---

# 九、linker.ld

现在正式建立启动符号：

```ld
ENTRY(_start)

MEMORY
{
    ROM (rx) : ORIGIN = 0x00400000, LENGTH = 64K
    RAM (rw) : ORIGIN = 0x00600000, LENGTH = 64K
}

PHDRS
{
    text PT_LOAD FLAGS(5);
    data PT_LOAD FLAGS(6);
}

SECTIONS
{
    .text :
    {
        _stext = .;

        *(.text)
        *(.text.*)

        _etext = .;
    } > ROM :text

    .rodata :
    {
        *(.rodata)
        *(.rodata.*)
    } > ROM :text

    .data :
    {
        _sdata = .;

        *(.data)
        *(.data.*)

        _edata = .;
    } > RAM AT > ROM :data

    _data_load = LOADADDR(.data);
    _data_size = SIZEOF(.data);

    .bss :
    {
        _sbss = .;

        *(.bss)
        *(.bss.*)
        *(COMMON)

        _ebss = .;
    } > RAM :data

    _data_vma = ADDR(.data);
    _data_lma = LOADADDR(.data);
}
```

---

# 十、这里已经准备好了所有启动信息

linker 自动产生：

```text
_sdata
_edata
_data_load
_data_size

_sbss
_ebss
```

对应：

```text
                .data

RAM              ROM
 │                 │
 │ _sdata          │ _data_load
 ▼                 ▼
┌────────┐        ┌────────┐
│        │        │ image  │
│ .data  │ ←───── │ .data  │
│        │        │ image  │
└────────┘        └────────┘
     ▲
     │
   _edata

_data_size
    =
_edata - _sdata
```

而 `.bss`：

```text
RAM

_sbss
  │
  ▼
┌──────────┐
│ .bss     │
│          │
└──────────┘
  ▲
  │
_ebss
```

---

# 十一、先不写启动代码，直接链接

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    -o data-bss.elf \
    -Map=data-bss.map
```

但此时我们还没有 `start.o`。

所以先创建最简单的：

```asm
.global _start

.extern main

_start:
    call main

    mov %eax, %edi
    mov $60, %eax
    syscall

.section .note.GNU-stack,"",@progbits
```

编译：

```bash
gcc -c start.S -o start.o
```

然后链接：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    -o data-bss.elf \
    -Map=data-bss.map
```

---

# 十二、先验证 linker 的结果

```bash
nm -n data-bss.elf
```

重点寻找：

```text
_sdata
_edata
_data_load
_data_size

_sbss
_ebss
```

你会看到类似：

```text
00000000004000xx A _data_load
0000000000600000 D _sdata
0000000000600004 D _edata

0000000000600004 B _sbss
0000000000600008 B _ebss
```

地址只是示意，实际以你的输出为准。

---

# 十三、先自己计算一遍

假设：

```text
_sdata     = 0x600000
_edata     = 0x600004
```

那么：

```text
_data_size = 0x4
```

而：

```text
_sbss      = 0x600004
_ebss      = 0x600008
```

那么：

```text
_bss_size = 0x4
```

因此：

```text
.data
RAM:
0x600000
    ↓
0x600004

.bss
RAM:
0x600004
    ↓
0x600008
```

---

# 十四、实验 14-1：实现 `copy_data()`

创建：

```text
init.c
```

内容：

```c
extern char _data_load[];
extern char _sdata[];
extern char _edata[];

void copy_data(void)
{
    char *src = _data_load;
    char *dst = _sdata;

    while (dst < _edata)
    {
        *dst++ = *src++;
    }
}
```

注意：

```text
src
=
_data_load
```

也就是：

```text
ROM
```

而：

```text
dst
=
_sdata
```

也就是：

```text
RAM
```

---

# 十五、这段代码其实就是 linker script 的“运行时消费者”

linker：

```ld
_data_load = LOADADDR(.data);
_sdata = .;
_edata = .;
```

C：

```c
char *src = _data_load;
char *dst = _sdata;

while (dst < _edata)
    *dst++ = *src++;
```

两者刚好形成：

```text
Linker
   │
   │ address information
   ▼
Symbols
   │
   ▼
Startup C
```

这是裸机开发非常重要的设计思想。

---

# 十六、实验 14-2：实现 `clear_bss()`

继续：

```c
extern char _sbss[];
extern char _ebss[];

void clear_bss(void)
{
    char *p = _sbss;

    while (p < _ebss)
    {
        *p++ = 0;
    }
}
```

完整 `init.c`：

```c
extern char _data_load[];
extern char _sdata[];
extern char _edata[];

extern char _sbss[];
extern char _ebss[];

void copy_data(void)
{
    char *src = _data_load;
    char *dst = _sdata;

    while (dst < _edata)
    {
        *dst++ = *src++;
    }
}

void clear_bss(void)
{
    char *p = _sbss;

    while (p < _ebss)
    {
        *p++ = 0;
    }
}
```

---

# 十七、编译 init.c

```bash
gcc \
    -ffreestanding \
    -fno-pie \
    -fno-stack-protector \
    -c init.c \
    -o init.o
```

这里：

```text
-fno-stack-protector
```

是为了避免编译器生成额外的运行时依赖。

---

# 十八、观察 init.o

```bash
nm init.o
```

你会看到：

```text
U _data_load
U _sdata
U _edata
U _sbss
U _ebss

T copy_data
T clear_bss
```

这特别漂亮。

因为：

```text
init.o
```

本身不知道这些地址是多少。

它只知道：

```text
U _data_load
U _sdata
U _edata
```

然后交给 linker：

```text
ld
 ↓
Symbol Resolution
 ↓
最终地址
```

---

# 十九、观察 relocation

执行：

```bash
readelf -r init.o
```

你应该能看到类似：

```text
_data_load
_sdata
_edata
_sbss
_ebss
```

相关 relocation。

也就是说：

```text
init.o
```

里面实际上存在：

```text
load address ?
data start ?
data end ?
bss start ?
bss end ?
```

这些地址都还没有最终确定。

---

# 二十、用 `objdump -dr`

```bash
objdump -dr init.o
```

这次非常值得仔细看。

你会同时看到：

```text
copy_data:
    ...
    relocation → _data_load
    relocation → _sdata
    relocation → _edata
```

以及：

```text
clear_bss:
    ...
    relocation → _sbss
    relocation → _ebss
```

所以：

```text
C source
    ↓
compiler
    ↓
machine code
    +
relocations
    ↓
ld
```

这就是我们前面十几节一直建立的知识，现在真正开始合流。

---

# 二十一、修改 `_start`

现在让启动代码先初始化内存。

```asm
.global _start

.extern copy_data
.extern clear_bss
.extern main

_start:

    call copy_data
    call clear_bss
    call main

    mov %eax, %edi
    mov $60, %eax
    syscall

.section .note.GNU-stack,"",@progbits
```

启动顺序：

```text
_start
   │
   ├── copy_data()
   │
   ├── clear_bss()
   │
   └── main()
```

这就是最小化的 CRT/startup 思路。

---

# 二十二、重新编译

```bash
gcc -c start.S -o start.o
gcc \
    -ffreestanding \
    -fno-pie \
    -fno-stack-protector \
    -c init.c \
    -o init.o
gcc \
    -ffreestanding \
    -fno-pie \
    -c main.c \
    -o main.o
```

---

# 二十三、重新链接

```bash
ld \
    -T linker.ld \
    start.o \
    init.o \
    main.o \
    -o startup.elf \
    -Map=startup.map
```

---

# 二十四、现在出现一个重要现实问题

我们的：

```text
.data
```

运行地址是：

```text
0x00600000
```

而 Linux 用户态程序真正运行时：

```text
0x00600000
```

并不是我们为这个裸机模型定义的 RAM。

所以直接：

```bash
./startup.elf
```

在普通 Linux 环境下可能：

```text
Segmentation fault
```

甚至无法正常作为普通 Linux 程序执行。

**这不是 linker script 错误。**

这是因为我们现在正在故意模拟：

```text
MCU Flash + RAM
```

而不是：

```text
Linux process virtual memory
```

因此本实验重点是：

```text
ELF layout
+
linker
+
startup code
```

而不是 Linux 下实际执行。

---

# 二十五、验证 ELF Section

```bash
readelf -S startup.elf
```

重点看：

```text
.text
.rodata
.data
.bss
```

然后：

```bash
objdump -h startup.elf
```

重点观察：

```text
.data
    VMA = RAM
    LMA = ROM

.bss
    VMA = RAM
```

形成：

```text
.data:
    VMA ≠ LMA

.bss:
    NOBITS
```

---

# 二十六、验证 Program Header

```bash
readelf -l startup.elf
```

观察：

```text
LOAD
```

你会看到我们在 linker script 中定义的：

```ld
PHDRS
{
    text PT_LOAD FLAGS(5);
    data PT_LOAD FLAGS(6);
}
```

产生了对应的 load segments。

于是：

```text
Section
   ↓
Segment
```

再次建立起来。

---

# 二十七、为什么 `.data` 的 File Size 和 Memory Size 会不同？

重点观察：

```bash
readelf -l startup.elf
```

例如：

```text
LOAD
Offset
VirtAddr
PhysAddr
FileSiz
MemSiz
```

对于包含 `.bss` 的 segment：

```text
FileSiz
```

可能小于：

```text
MemSiz
```

原因：

```text
.bss
=
NOBITS
```

所以：

```text
File:
    不保存 bss 内容

Memory:
    需要分配 bss 空间
```

因此：

```text
MemSiz > FileSiz
```

是非常典型的 ELF 现象。

---

# 二十八、实验 14-3：验证 `.data` 初始镜像

执行：

```bash
objdump -s -j .data startup.elf
```

注意：

这里看到的是：

```text
.data section 的内容
```

而 ELF 文件内部的 section header 地址：

```text
VMA
```

又是：

```text
RAM
```

这时候你应该开始意识到：

> **ELF 文件中的“内容位置”和 section 的“运行地址”是两个概念。**

这正是：

```text
File Offset
VMA
LMA
```

需要区分的原因。

---

# 二十九、Map 文件分析：第一层

打开：

```bash
less startup.map
```

找到：

```text
Memory Configuration
```

你应该看到：

```text
ROM
RAM
```

例如：

```text
ROM  0x00400000  0x10000
RAM  0x00600000  0x10000
```

这对应：

```ld
MEMORY
{
    ROM ...
    RAM ...
}
```

---

# 三十、Map 文件分析：第二层

继续寻找：

```text
.text
```

你会看到：

```text
.text
    start.o
    init.o
    main.o
```

这说明：

```text
_start
copy_data
clear_bss
main
```

最终都被放入：

```text
.text
```

---

# 三十一、Map 文件分析：第三层

搜索：

```text
.data
```

应该能看到：

```text
.data
    main.o
        initialized_value
```

并且 Output Section 起始地址应该：

```text
0x00600000
```

即：

```text
RAM VMA
```

---

# 三十二、Map 文件分析：第四层

搜索：

```text
_data_load
```

应该能看到：

```text
_data_load = LOADADDR (.data)
```

它对应：

```text
ROM LMA
```

于是 Map 文件可以直接帮助我们建立：

```text
.data
VMA
↓
RAM

LMA
↓
ROM
```

---

# 三十三、Map 文件分析：第五层

搜索：

```text
.bss
```

应该看到：

```text
.bss
    zero_value
```

并且：

```text
.bss
VMA
=
RAM
```

所以最终：

```text
ROM
│
├── .text
├── .rodata
└── .data image
       
RAM
│
├── .data
└── .bss
```

---

# 三十四、用 `nm` 做最终地址验证

```bash
nm -n startup.elf
```

重点：

```text
_start
copy_data
clear_bss
main

_sdata
_edata
_data_load

_sbss
_ebss
```

于是可以得到：

```text
代码：

_start
copy_data
clear_bss
main
        ↓
.text / ROM
```

数据：

```text
_data_load
        ↓
ROM

_sdata
_edata
        ↓
RAM

_sbss
_ebss
        ↓
RAM
```

---

# 三十五、用 `objdump -d` 验证启动顺序

执行：

```bash
objdump -d startup.elf
```

寻找：

```text
<_start>
```

应该能看到类似：

```text
<_start>:
    call copy_data
    call clear_bss
    call main
```

这一步非常重要。

因为：

```text
linker script
```

解决：

```text
地址
```

而：

```text
start.S
```

解决：

```text
执行顺序
```

二者共同构成：

```text
startup
```

---

# 三十六、再看 `copy_data`

```bash
objdump -d startup.elf
```

找到：

```text
<copy_data>
```

你会看到 linker 最终已经把：

```text
_data_load
_sdata
_edata
```

相关 relocation 解析成最终地址。

所以：

```text
init.o
```

阶段：

```text
_data_load = ?
```

而：

```text
startup.elf
```

阶段：

```text
_data_load = 0x0040....
```

这就是：

# Relocation Resolution

---

# 三十七、整个实验现在形成完整闭环

```text
main.c
   │
   ├── initialized_value
   │
   └── zero_value
   │
   ▼
main.o
   │
   ├── .data
   └── .bss
   │
   ▼
linker.ld
   │
   ├── .data → RAM
   │          AT → ROM
   │
   ├── .bss → RAM
   │
   ├── _sdata
   ├── _edata
   ├── _data_load
   ├── _sbss
   └── _ebss
   │
   ▼
init.o
   │
   ├── copy_data()
   └── clear_bss()
   │
   ▼
start.S
   │
   ├── copy_data
   ├── clear_bss
   └── main
   │
   ▼
ld
   │
   ├── Symbol Resolution
   ├── Relocation
   ├── Section Layout
   └── Segment Layout
   │
   ▼
startup.elf
```

这就是一个真正意义上的：

> **Linker Script + Startup Code 协同工作的完整实验。**

---

# 三十八、现在回顾我们之前学过的内容

你之前特别关注过：

```text
为什么下面 C 代码可以把 .data 从 ROM 搬到 RAM？
```

现在答案已经完整了：

```c
memcpy(
    _sdata,
    _data_load,
    _edata - _sdata
);
```

不是 C 语言“神奇地知道”：

```text
ROM
RAM
```

而是：

```text
linker.ld
    ↓
ADDR
LOADADDR
SIZEOF
    ↓
生成 linker symbols
    ↓
startup C
    ↓
执行 copy
```

也就是说：

# `.data` 搬运是 Compiler + Linker + Startup Code 三者共同完成的。

---

# 三十九、一个非常重要的细节：符号本身没有“存储空间”

例如：

```ld
_data_load = LOADADDR(.data);
```

这里：

```text
_data_load
```

不是：

```c
char _data_load;
```

它不是一个变量。

它只是：

```text
一个 linker symbol
```

也就是：

```text
名字
 ↓
某个地址值
```

所以：

```c
extern char _data_load[];
```

只是告诉编译器：

> 有一个名为 `_data_load` 的地址符号。

并不意味着真的需要一个：

```text
char[]
```

对象。

这是 linker symbol 最重要的使用方式之一。

---

# 四十、为什么用 `char []`？

例如：

```c
extern char _sdata[];
```

我们真正想要的是：

```text
_sdata
=
某个地址
```

而不是：

```text
读取 _sdata 变量里面存储的一个 char
```

因此：

```c
char *p = _sdata;
```

可以直接把它当地址使用。

这也是裸机启动代码中非常经典的写法。

---

# 四十一、实验 14-4：改用 linker 自动计算结束地址

目前：

```ld
_sdata = .;
...
_edata = .;
```

当然可以。

但也可以：

```ld
_sdata = ADDR(.data);
_edata = ADDR(.data) + SIZEOF(.data);
```

于是：

```text
_sdata
    ↓
ADDR(.data)

_edata
    ↓
ADDR(.data) + SIZEOF(.data)
```

这样可以进一步理解：

```text
ADDR
+
SIZEOF
```

是如何组合出：

```text
[start, end)
```

这个区间的。

---

# 四十二、`.bss` 也一样

可以：

```ld
_sbss = ADDR(.bss);
_ebss = ADDR(.bss) + SIZEOF(.bss);
```

所以：

```text
.data:
[_sdata, _edata)

.bss:
[_sbss, _ebss)
```

启动代码：

```c
for (p = _sdata; p < _edata; ++p)
```

和：

```c
for (p = _sbss; p < _ebss; ++p)
```

实际上就是在遍历 linker 定义的 section 地址区间。

---

# 四十三、现在可以建立“启动代码三元组”

对于 `.data`：

```text
_source
_destination
_size
```

也就是：

```text
_data_load
_sdata
_data_size
```

对于 `.bss`：

```text
_start
_end
```

也就是：

```text
_sbss
_ebss
```

所以：

```text
.data
    source = LOADADDR(.data)
    dest   = ADDR(.data)
    size   = SIZEOF(.data)

.bss
    start  = ADDR(.bss)
    end    = ADDR(.bss) + SIZEOF(.bss)
```

这几乎是所有裸机 linker script 的基本骨架。

---

# 四十四、一个值得注意的改进

真实 MCU 工程中通常不会把：

```ld
.data > RAM AT > ROM
```

简单地理解为：

```text
ROM
 ↓
RAM
```

还需要考虑：

```text
Flash offset
Flash image
Loadable segment
Bootloader
startup address
memory-mapped Flash
```

因此下一阶段我们需要进入：

# `AT()` + `LOADADDR()` + Program Header + Flash Image

而不是只停留在 section。

---

# 四十五、本节命令清单

### 编译

```bash
gcc -ffreestanding -fno-pie -c main.c -o main.o

gcc \
    -ffreestanding \
    -fno-pie \
    -fno-stack-protector \
    -c init.c \
    -o init.o

gcc -c start.S -o start.o
```

### 链接

```bash
ld \
    -T linker.ld \
    start.o \
    init.o \
    main.o \
    -o startup.elf \
    -Map=startup.map
```

### Symbol

```bash
nm -n startup.elf
```

### Section

```bash
readelf -S startup.elf
```

### Segment

```bash
readelf -l startup.elf
```

### Section Header 快速观察

```bash
objdump -h startup.elf
```

### 数据内容

```bash
objdump -s -j .data startup.elf
```

### 反汇编

```bash
objdump -d startup.elf
```

### `.o` relocation

```bash
readelf -r init.o
```

### `.o` 机器码 + relocation

```bash
objdump -dr init.o
```

### Map

```bash
less startup.map
```

或者：

```bash
grep -A 30 -B 5 "\.data" startup.map
grep -A 30 -B 5 "\.bss" startup.map
grep -A 10 -B 5 "_data_load" startup.map
```

---

# 四十六、本节最重要的知识图

```text
                    linker.ld
                        │
             ┌──────────┼──────────┐
             ▼          ▼          ▼
          ADDR()     LOADADDR()   SIZEOF()
             │          │          │
             ▼          ▼          ▼
            VMA        LMA        Size
             │          │          │
             │          │          │
             └──────┬───┴──────┬───┘
                    │           │
                    ▼           ▼
                 .data         .bss
                    │           │
          ┌─────────┘           └─────────┐
          ▼                               ▼
       _sdata                         _sbss
       _edata                         _ebss
       _data_load
                    │
                    ▼
              startup code
                    │
             ┌──────┴──────┐
             ▼             ▼
        copy_data()    clear_bss()
             │             │
             ▼             ▼
          ROM→RAM        RAM→0
             │             │
             └──────┬──────┘
                    ▼
                  main()
```

---

# 四十七、下一实验：进入 `AT()` 的真正高级玩法

下一节进入：

## 实验 15：多个 ROM Load Region + `AT()` + `LOADADDR()` —— 构造真正的 Flash Image

我们将不再简单使用：

```ld
.data > RAM AT > ROM
```

而是开始控制：

```text
ROM
├── .text
├── .rodata
├── .data LOAD IMAGE
├── 自定义只读表
└── 其他固件数据

RAM
├── .data
├── .bss
├── heap
└── stack
```

并实验：

```ld
AT(...)
AT > ROM
LOADADDR()
ADDR()
SIZEOF()
ALIGN()
```

同时重点分析：

```bash
readelf -S
readelf -l
objdump -h
objdump -s
nm
```

以及 Map 中的：

```text
VMA
LMA
LOAD
File Offset
FileSiz
MemSiz
```

最终我们会把：

```text
Section
```

进一步提升到：

```text
Segment
+
Flash image
+
Runtime memory
```

这一步之后，GNU `ld` 就开始真正进入**嵌入式链接脚本设计**的核心区域。

