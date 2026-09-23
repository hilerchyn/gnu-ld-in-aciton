# GNU ld 实战课程 · 实验 24

## `PHDRS` + `PT_LOAD`：从 Section 布局进入 ELF Segment 布局

上一节我们完成了一个非常关键的跳跃：

```text
.data
 ├── VMA → RAM
 └── LMA → ROM
```

并且已经能够通过：

```ld
AT > ROM
ADDR(.data)
LOADADDR(.data)
SIZEOF(.data)
```

告诉 linker：

> **数据运行在哪里，以及初始化镜像从哪里加载。**

这一节再向下走一层：

```text
Section
   ↓
Segment
   ↓
PT_LOAD
   ↓
真正的 ELF 装载单元
```

GNU `ld` 官方文档明确说明，`PHDRS` 可以显式定义 ELF Program Header；其中 `PT_LOAD` 描述可加载 Segment，`FLAGS()` 可以显式指定 Segment 的 `p_flags`。Section 可以通过 `:name` 绑定到指定 Program Header。([Sourceware][1])

这一节非常重要，因为你前面已经碰到过：

```text
LOAD segment with RWX permissions
```

现在我们不再“看到警告再猜”，而是亲手控制它。

---

# 一、先建立一个最重要的认识

到现在为止，我们一直在研究：

```text
readelf -S
```

它告诉我们：

# Section Header Table

例如：

```text
.text
.rodata
.data
.bss
```

但操作系统、Bootloader、ELF Loader 真正加载文件时，更重要的是：

```text
readelf -l
```

它显示：

# Program Header Table

例如：

```text
PT_LOAD
PT_DYNAMIC
PT_INTERP
PT_PHDR
```

所以：

```text
Section
```

和：

```text
Segment
```

不是同一个概念。

---

# 二、Section 与 Segment 的关系

可以先建立这个模型：

```text
ELF
│
├── Section Header Table
│     │
│     ├── .text
│     ├── .rodata
│     ├── .data
│     ├── .bss
│     └── ...
│
└── Program Header Table
      │
      ├── PT_LOAD
      │      ├── .text
      │      └── .rodata
      │
      └── PT_LOAD
             ├── .data
             └── .bss
```

也就是说：

```text
多个 Section
      ↓
组成
      ↓
一个 Segment
```

---

# 三、为什么这一层特别重要？

假设：

```text
.text
.rodata
```

应该：

```text
R + X
```

而：

```text
.data
.bss
```

应该：

```text
R + W
```

理想布局：

```text
PT_LOAD #1
R E
    .text
    .rodata

PT_LOAD #2
R W
    .data
    .bss
```

而如果 linker 最终产生：

```text
PT_LOAD
R W X
    .text
    .data
```

就可能出现：

```text
LOAD segment with RWX permissions
```

这正是我们今天要解决的问题。

---

# 四、实验 24-1：先看默认情况下 ld 怎么做

继续使用实验 23 的源码。

目录：

```text
lab24/
├── start.S
├── main.c
├── data.c
└── linker-default.ld
```

`data.c`：

```c
int counter = 1234;

int magic = 0x12345678;

char message[] = "GNU ld";

int buffer[1024];
```

`main.c`：

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

`start.S`：

```asm
.global _start

.text

_start:
    call main
    hlt
```

---

# 五、基础 linker script

先不要使用 `PHDRS`：

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
}
```

---

# 六、编译

```bash
gcc \
    -ffreestanding \
    -fno-pie \
    -fno-stack-protector \
    -ffunction-sections \
    -fdata-sections \
    -c start.S -o start.o
```

```bash
gcc \
    -ffreestanding \
    -fno-pie \
    -fno-stack-protector \
    -ffunction-sections \
    -fdata-sections \
    -c main.c -o main.o
```

```bash
gcc \
    -ffreestanding \
    -fno-pie \
    -fno-stack-protector \
    -ffunction-sections \
    -fdata-sections \
    -c data.c -o data.o
```

---

# 七、链接

```bash
ld \
    -T linker-default.ld \
    start.o \
    main.o \
    data.o \
    -o default.elf \
    -Map=default.map
```

---

# 八、第一次看 Section

```bash
readelf -S default.elf
```

重点：

```text
.text
.rodata
.data
.bss
```

你现在已经非常熟悉这个输出了。

但是今天：

> **不要停在这里。**

继续：

```bash
readelf -l default.elf
```

---

# 九、第一次真正观察 Program Header

你会看到类似：

```text
Program Headers:

  Type           Offset   VirtAddr   PhysAddr
                 FileSiz  MemSiz     Flg Align

  LOAD           ...
  LOAD           ...
```

具体输出会随着你的 binutils、默认 emulation 和脚本略有差异。

重点看：

```text
Type
Offset
VirtAddr
PhysAddr
FileSiz
MemSiz
Flg
Align
```

---

# 十、`readelf -l` 中最重要的 8 个字段

例如：

```text
LOAD
Offset   = 0x000000
VirtAddr = 0x00400000
PhysAddr = 0x00400000
FileSiz  = 0x....
MemSiz   = 0x....
Flg      = R E
Align    = 0x1000
```

它们分别代表：

```text
Offset
    ELF 文件中的位置

VirtAddr
    Segment 运行地址

PhysAddr
    物理地址字段

FileSiz
    文件中实际占用大小

MemSiz
    加载后内存占用大小

Flg
    R/W/X 权限

Align
    Segment 对齐
```

---

# 十一、最关键的区别：`FileSiz` vs `MemSiz`

假设：

```text
.data
```

有：

```text
Size = 0x20
```

而：

```text
.bss
```

有：

```text
Size = 0x1000
```

那么一个：

```text
PT_LOAD
```

可能是：

```text
FileSiz = 0x20
MemSiz  = 0x1020
```

因为：

```text
.data
```

是真正存在于文件中的数据。

而：

```text
.bss
```

只是：

```text
运行时需要内存
```

不需要把 0 全部存进文件。

这和上一节：

```text
SHT_NOBITS
```

完全对应。

---

# 十二、Section 到 Segment 的映射

`readelf -l` 最下面有：

```text
Section to Segment mapping:
```

这是今天最值得反复看的地方。

可能类似：

```text
Segment Sections...
   00     .text .rodata
   01     .data .bss
```

这张表告诉你：

```text
Section
    ↓
属于哪个 PT_LOAD
```

于是：

```text
readelf -S
```

和：

```text
readelf -l
```

第一次真正连接起来。

---

# 十三、实验 24-2：自己定义 `PHDRS`

现在创建：

```text
linker-phdrs.ld
```

内容：

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
        *(.text)
        *(.text.*)
    } > ROM :text

    .rodata :
    {
        *(.rodata)
        *(.rodata.*)
    } > ROM :text

    .data :
    {
        __data_start = .;

        *(.data)
        *(.data.*)

        __data_end = .;
    } > RAM AT > ROM :data

    __data_load_start = LOADADDR(.data);
    __data_size = SIZEOF(.data);

    .bss :
    {
        __bss_start = .;

        *(.bss)
        *(.bss.*)
        *(COMMON)

        __bss_end = .;
    } > RAM :data
}
```

---

# 十四、这里第一次出现：

```ld
:text
```

和：

```ld
:data
```

这两个东西。

它们不是 Section 名字。

它们是：

# Program Header 名字

因为：

```ld
PHDRS
{
    text PT_LOAD FLAGS(5);
    data PT_LOAD FLAGS(6);
}
```

定义了两个 Program Header：

```text
text
data
```

然后：

```ld
.text : { ... } :text
```

意思是：

> 把 `.text` 放入名为 `text` 的 Program Header。

---

# 十五、`FLAGS(5)` 为什么是 RX？

ELF 的：

```text
PF_R = 4
PF_W = 2
PF_X = 1
```

所以：

```text
5
=
4 + 1
=
R + X
```

因此：

```ld
text PT_LOAD FLAGS(5);
```

就是：

```text
PT_LOAD
R E
```

而：

```text
6
=
4 + 2
=
R + W
```

所以：

```ld
data PT_LOAD FLAGS(6);
```

就是：

```text
PT_LOAD
R W
```

---

# 十六、重新链接

```bash
ld \
    -T linker-phdrs.ld \
    start.o \
    main.o \
    data.o \
    -o phdrs01.elf \
    -Map=phdrs01.map
```

---

# 十七、第一项验证

```bash
readelf -l phdrs01.elf
```

目标是看到：

```text
LOAD
    R E

LOAD
    RW
```

而不是：

```text
LOAD
    RWX
```

---

# 十八、第二项验证

查看：

```text
Section to Segment mapping:
```

应该得到类似：

```text
Segment Sections...
   00     .text .rodata
   01     .data .bss
```

这就是：

```text
PHDRS
  ↓
Section → Segment
```

真正生效的证据。

---

# 十九、`FLAGS()` 为什么很重要？

如果你不指定：

```ld
FLAGS()
```

ld 通常会根据包含的 Section 推导 Segment flags。GNU ld 文档也明确说明，Segment flags 可以由 Section 推导，也可以通过 `FLAGS` 显式设置。([Sourceware][2])

例如：

```text
.text
```

通常：

```text
R X
```

而：

```text
.data
```

通常：

```text
R W
```

但是复杂工程中：

```text
自定义 Section
+
多个属性
+
特殊 orphan section
+
PHDRS
```

可能让最终权限变得不符合你的预期。

所以在需要严格控制 ELF Segment 的场景：

```ld
FLAGS()
```

非常有价值。

---

# 二十、实验 24-3：故意制造 RWX

把：

```ld
PHDRS
{
    text PT_LOAD FLAGS(7);
}
```

其中：

```text
7
=
4 + 2 + 1
=
R + W + X
```

然后：

```bash
ld \
    -T linker-phdrs.ld \
    start.o \
    main.o \
    data.o \
    -o rwx.elf \
    -Map=rwx.map
```

检查：

```bash
readelf -l rwx.elf
```

应该看到：

```text
LOAD
RWE
```

这就是：

```text
RWX
```

---

# 二十一、为什么这是危险的？

因为：

```text
R
读取

W
写入

X
执行
```

如果一个 Segment 同时：

```text
R W X
```

那么其中的数据：

```text
可写
+
可执行
```

在安全设计上通常不是理想状态。

所以我们之前看到：

```text
LOAD segment with RWX permissions
```

现在可以准确解释：

> 某个 PT_LOAD 的 `p_flags` 同时包含 `PF_R | PF_W | PF_X`。

而不是模糊地认为：

> “某个 Section 权限有问题。”

---

# 二十二、实验 24-4：Section 与 PHDRS 的完整关系

现在重新看：

```ld
PHDRS
{
    text PT_LOAD FLAGS(5);
    data PT_LOAD FLAGS(6);
}
```

和：

```ld
SECTIONS
{
    .text : { ... } :text

    .rodata : { ... } :text

    .data : { ... } :data

    .bss : { ... } :data
}
```

可以画成：

```text
                 ELF
                  │
           ┌──────┴──────┐
           │             │
       Sections       Program Headers
           │             │
           │          PT_LOAD:text
           │             │
           ├── .text ────┤
           │             │
           └── .rodata ──┘

           ┌──────────────┐
           │ PT_LOAD:data │
           │              │
           ├── .data      │
           │              │
           └── .bss       │
```

这就是：

# Section → Segment 映射。

---

# 二十三、实验 24-5：把 `.data` 的 VMA/LMA 再放回来

注意：

```ld
.data :
{
    ...
} > RAM AT > ROM :data
```

这里同时存在三个概念：

```text
> RAM
AT > ROM
:data
```

分别解决：

```text
> RAM
    ↓
VMA

AT > ROM
    ↓
LMA

:data
    ↓
Program Header / Segment
```

所以一行代码同时涉及三个 ELF 层次：

```text
.data > RAM AT > ROM :data
       │        │        │
       │        │        └── Segment
       │        └─────────── Load Address
       └──────────────────── Virtual Address
```

这就是上一节和本节真正接起来的地方。

---

# 二十四、实验 24-6：验证 `.data` 的 VMA/LMA

执行：

```bash
objdump -h phdrs01.elf
```

找到：

```text
.data
```

记录：

```text
VMA
LMA
Size
Align
```

然后：

```bash
readelf -l phdrs01.elf
```

找到：

```text
RW
```

的：

```text
LOAD
```

比较：

```text
.data LMA
```

和：

```text
PT_LOAD
PhysAddr
```

你应该开始看到：

```text
Section
   ↓
VMA/LMA

Segment
   ↓
VirtAddr/PhysAddr
```

之间的关系。

---

# 二十五、一个非常重要的区别

不要把：

```text
Section LMA
```

和：

```text
Segment PhysAddr
```

简单认为永远完全相同。

在普通、简单 ELF 中，它们经常表现出非常直接的对应关系。

但是一旦你加入：

```text
多个 Section
多个 Segment
AT()
PHDRS
特殊地址
```

就必须从：

```text
readelf -l
```

实际确认 Program Header。

这也是为什么：

> **学 GNU ld 不能只看 `readelf -S`。**

---

# 二十六、实验 24-7：加入 ELF Header 和 Program Header

现在进入一个更真实的 ELF linker script。

```ld
PHDRS
{
    headers PT_PHDR PHDRS;
    text    PT_LOAD FILEHDR PHDRS FLAGS(5);
    data    PT_LOAD FLAGS(6);
}
```

这里：

```text
PT_PHDR
```

表示 Program Header 本身。

而：

```ld
FILEHDR
PHDRS
```

会把 ELF File Header 和 Program Header Table 纳入对应 LOAD Segment 的文件布局。

GNU ld 官方文档给出了这种 `PHDRS` 组合方式。([Sourceware][1])

---

# 二十七、为什么需要 `SIZEOF_HEADERS`？

我们可以写：

```ld
. = SIZEOF_HEADERS;
```

含义：

> 把 Location Counter 放到 ELF Header + Program Header Table 之后。

于是：

```text
ELF 文件
┌──────────────────────┐
│ ELF Header           │
├──────────────────────┤
│ Program Header Table │
├──────────────────────┤
│ .text                │
├──────────────────────┤
│ .rodata              │
└──────────────────────┘
```

这对于构造自定义 ELF Segment 布局很重要。

---

# 二十八、实验 24-8：完整 PHDRS 版本

尝试：

```ld
ENTRY(_start)

MEMORY
{
    ROM (rx) : ORIGIN = 0x00400000, LENGTH = 64K
    RAM (rw) : ORIGIN = 0x00600000, LENGTH = 64K
}

PHDRS
{
    headers PT_PHDR PHDRS;
    text    PT_LOAD FILEHDR PHDRS FLAGS(5);
    data    PT_LOAD FLAGS(6);
}

SECTIONS
{
    . = SIZEOF_HEADERS;

    .text :
    {
        *(.text)
        *(.text.*)
    } > ROM :text

    .rodata :
    {
        *(.rodata)
        *(.rodata.*)
    } > ROM :text

    .data :
    {
        __data_start = .;

        *(.data)
        *(.data.*)

        __data_end = .;
    } > RAM AT > ROM :data

    __data_load_start = LOADADDR(.data);
    __data_size = SIZEOF(.data);

    .bss :
    {
        __bss_start = .;

        *(.bss)
        *(.bss.*)
        *(COMMON)

        __bss_end = .;
    } > RAM :data
}
```

---

# 二十九、这里有一个非常值得你警惕的问题

你现在可能会发现：

```text
.data
```

的 LMA/VMA 和：

```text
PT_LOAD data
```

之间不一定马上符合你脑中的：

```text
ROM
0x400000

RAM
0x600000
```

整齐布局。

这是正常的。

因为现在我们已经同时控制：

```text
Section VMA
Section LMA
Segment
Segment alignment
File offset
Memory offset
```

如果发现：

```text
LMA
```

不符合预期：

> **不要继续盲改 `AT()`。**

先看：

```bash
readelf -l
```

再看：

```bash
readelf -S
```

最后看：

```text
Map
```

这是 GNU ld 调试的一个非常重要的方法。

---

# 三十、实验 24-9：Map 文件第一次真正分析 Segment

执行：

```bash
less phdrs01.map
```

现在 Map 文件不只是告诉你：

```text
.text
.rodata
.data
.bss
```

还应该结合：

```text
LOAD
```

进行分析。

建立：

```text
Section
    ↓
VMA
    ↓
LMA
    ↓
Segment
    ↓
File Offset
```

的关系。

---

# 三十一、建议做一张自己的实验记录表

例如：

| Section   | VMA | LMA | Size | Segment |
| --------- | --: | --: | ---: | ------- |
| `.text`   |   ? |   ? |    ? | text    |
| `.rodata` |   ? |   ? |    ? | text    |
| `.data`   |   ? |   ? |    ? | data    |
| `.bss`    |   ? |   ? |    ? | data    |

然后：

```bash
readelf -S phdrs01.elf
```

填 VMA。

```bash
objdump -h phdrs01.elf
```

填 VMA/LMA/Size。

```bash
readelf -l phdrs01.elf
```

填 Segment。

这张表非常值得保留。

---

# 三十二、实验 24-10：观察 `p_filesz` 和 `p_memsz`

这是本节另一个核心。

执行：

```bash
readelf -l phdrs01.elf
```

例如某个：

```text
LOAD
```

可能是：

```text
FileSiz = 0x100
MemSiz  = 0x1100
```

意味着：

```text
文件：
    0x100 bytes

内存：
    0x1100 bytes
```

多出来的：

```text
0x1000
```

通常就是：

```text
.bss
```

对应的运行时零初始化空间。

因此：

```text
p_filesz <= p_memsz
```

是一个非常重要的观察。

---

# 三十三、把 `.bss` 看成 Segment 尾部

例如：

```text
PT_LOAD data

File:
┌────────────────┐
│ .data          │
└────────────────┘
       ↑
    p_filesz

Memory:
┌────────────────┐
│ .data          │
├────────────────┤
│ .bss           │
│                │
│                │
└────────────────┘
       ↑
    p_memsz
```

所以：

```text
p_memsz - p_filesz
```

可以对应一部分：

```text
NOBITS / zero-fill
```

这就是 ELF Loader 为什么不需要从文件读取一大堆 0。

---

# 三十四、实验 24-11：验证 `.bss` 不占文件空间

执行：

```bash
readelf -S phdrs01.elf
```

找到：

```text
.bss
```

观察：

```text
Type = NOBITS
```

然后：

```bash
objdump -h phdrs01.elf
```

比较：

```text
.data Size
.bss Size
```

最后：

```bash
readelf -l phdrs01.elf
```

比较：

```text
FileSiz
MemSiz
```

形成：

```text
.bss
 ↓
NOBITS
 ↓
不增加对应文件内容
 ↓
增加 Segment 的 MemSiz
```

---

# 三十五、实验 24-12：为什么 `.rodata` 可以和 `.text` 共用 RX Segment？

因为：

```text
.text
```

需要：

```text
R X
```

而：

```text
.rodata
```

需要：

```text
R
```

`R X` Segment 同样允许：

```text
读取 .rodata
```

因此：

```text
PT_LOAD text
R E
├── .text
└── .rodata
```

是非常自然的布局。

这比：

```text
.text → RX
.rodata → R
```

拆成两个 Segment 更节省 Program Header 和页面布局开销。

---

# 三十六、实验 24-13：为什么 `.data` 不能和 `.text` 共用 RX Segment？

因为：

```text
.data
```

必须：

```text
R W
```

而：

```text
.text
```

必须：

```text
R X
```

如果放在一起：

```text
.text
.data
```

就只能：

```text
R W X
```

于是：

```text
RWX
```

出现。

所以我们设计：

```text
PT_LOAD #1
R X
.text
.rodata

PT_LOAD #2
R W
.data
.bss
```

这就是：

# W^X 思维

也就是：

```text
Writable
```

和：

```text
Executable
```

尽量不要同时存在。

---

# 三十七、实验 24-14：故意错误映射

尝试：

```ld
.text : { *(.text) } > ROM :data
```

而：

```ld
.data : { *(.data) } > RAM :data
```

此时：

```text
.text
.data
```

都进入：

```text
data PT_LOAD
```

如果：

```ld
data PT_LOAD FLAGS(6);
```

那么：

```text
.text
```

所在 Segment 可能变成：

```text
RW
```

这意味着：

```text
代码
```

所在 Segment：

```text
不可执行
```

这就是 Section 到 Segment 映射错误可能造成的后果。

---

# 三十八、再反过来

如果：

```ld
text PT_LOAD FLAGS(5);
```

然后把：

```text
.data
```

也塞进：

```text
:text
```

那么：

```text
.data
```

可能处于：

```text
R X
```

Segment 中。

这样：

```text
.data
```

缺少：

```text
W
```

又不正确。

因此：

```text
Section
属性
+
Segment FLAGS
```

必须协调。

---

# 三十九、实验 24-15：`PHDRS` 的一个非常重要规则

一旦你开始使用：

```ld
PHDRS
```

就应该明确思考：

```text
每一个重要 Output Section
属于哪个 Program Header？
```

例如：

```ld
.text   : { ... } :text
.rodata : { ... } :text
.data   : { ... } :data
.bss    : { ... } :data
```

形成：

```text
text
 ├── .text
 └── .rodata

data
 ├── .data
 └── .bss
```

这是最容易理解的模型。

---

# 四十、实验 24-16：`AT()` 与 `PHDRS` 同时存在

这一节是最关键的组合：

```ld
PHDRS
{
    text PT_LOAD FLAGS(5);
    data PT_LOAD FLAGS(6);
}

SECTIONS
{
    .text : { ... } > ROM :text

    .rodata : { ... } > ROM :text

    .data :
    {
        ...
    } > RAM AT > ROM :data

    .bss :
    {
        ...
    } > RAM :data
}
```

现在：

```text
.text
    VMA → ROM
    Segment → text

.rodata
    VMA → ROM
    Segment → text

.data
    VMA → RAM
    LMA → ROM
    Segment → data

.bss
    VMA → RAM
    Segment → data
```

把四者放在一张图里：

```text
                  ELF
                   │
        ┌──────────┴──────────┐
        │                     │
       ROM                   RAM
        │                     │
   .text .rodata             .data .bss
        │                     │
        │                     │
     PT_LOAD                PT_LOAD
       R E                    R W
        │                     │
        └────── .data LMA ────┘
```

这已经是完整 ELF 固件布局的雏形。

---

# 四十一、实验 24-17：验证 `PHDRS` 的最终结果

每次修改 `PHDRS` 后，固定执行：

```bash
readelf -S phdrs01.elf
```

然后：

```bash
objdump -h phdrs01.elf
```

然后：

```bash
readelf -l phdrs01.elf
```

然后：

```bash
readelf -lW phdrs01.elf
```

最后这个：

```bash
readelf -lW
```

非常推荐。

因为宽格式可以避免：

```text
VirtAddr
PhysAddr
FileSiz
MemSiz
```

被截断。

---

# 四十二、`readelf -lW` 是以后排查 Segment 的主力命令

建议以后看到：

```text
PT_LOAD
```

直接：

```bash
readelf -lW firmware.elf
```

重点看：

```text
Offset
VirtAddr
PhysAddr
FileSiz
MemSiz
Flg
Align
```

然后下面：

```text
Section to Segment mapping
```

一起看。

---

# 四十三、实验 24-18：用 `objdump -p`

还有一个很好用的命令：

```bash
objdump -p phdrs01.elf
```

它也可以帮助查看：

```text
Program Header
```

尤其适合：

```text
LOAD
DYNAMIC
INTERP
```

等信息的快速查看。

于是：

```text
readelf -l
```

和：

```text
objdump -p
```

可以交叉验证。

---

# 四十四、实验 24-19：Map 文件最终分析方法

这一节以后，Map 文件分析要分两层。

## 第一层：Section

```text
.text
.rodata
.data
.bss
```

回答：

```text
谁放在哪里？
大小多少？
哪个 .o 提供？
```

## 第二层：Segment

```text
PT_LOAD
```

回答：

```text
哪些 Section 被装在一起？
权限是什么？
文件大小是多少？
内存大小是多少？
```

因此：

```text
Map
+
readelf -S
+
readelf -l
```

才是完整分析。

---

# 四十五、实验 24-20：制作最终版 linker script

建议先使用这个版本：

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
        _srodata = .;

        *(.rodata)
        *(.rodata.*)

        _erodata = .;
    } > ROM :text

    .data :
    {
        __data_start = .;

        *(.data)
        *(.data.*)

        __data_end = .;
    } > RAM AT > ROM :data

    __data_load_start = LOADADDR(.data);
    __data_size = SIZEOF(.data);

    .bss :
    {
        __bss_start = .;

        *(.bss)
        *(.bss.*)
        *(COMMON)

        __bss_end = .;
    } > RAM :data

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
        "ERROR: .data image exceeds ROM"
    );
}
```

---

# 四十六、最终编译命令

```bash
rm -f *.o *.elf *.map
```

```bash
gcc \
    -ffreestanding \
    -fno-pie \
    -fno-stack-protector \
    -ffunction-sections \
    -fdata-sections \
    -c start.S \
    -o start.o
```

```bash
gcc \
    -ffreestanding \
    -fno-pie \
    -fno-stack-protector \
    -ffunction-sections \
    -fdata-sections \
    -c main.c \
    -o main.o
```

```bash
gcc \
    -ffreestanding \
    -fno-pie \
    -fno-stack-protector \
    -ffunction-sections \
    -fdata-sections \
    -c data.c \
    -o data.o
```

链接：

```bash
ld \
    -T linker-phdrs.ld \
    start.o \
    main.o \
    data.o \
    -o firmware.elf \
    -Map=firmware.map
```

---

# 四十七、最终验证流程

以后这一类问题，建议固定执行：

### ① 看 Input Sections

```bash
objdump -h *.o
```

### ② 看 Output Sections

```bash
readelf -SW firmware.elf
```

### ③ 看 Section VMA/LMA

```bash
objdump -h firmware.elf
```

### ④ 看 Program Headers

```bash
readelf -lW firmware.elf
```

### ⑤ 看 Segment 映射

```bash
objdump -p firmware.elf
```

### ⑥ 看符号

```bash
nm -n firmware.elf
```

### ⑦ 看实际机器码

```bash
objdump -d firmware.elf
```

### ⑧ 看实际数据

```bash
objdump -s firmware.elf
```

### ⑨ 看 linker 的最终决策

```bash
less firmware.map
```

---

# 四十八、这一节最重要的知识关系

现在把整个课程前面学到的东西串起来：

```text
                    C / ASM
                       │
                       ▼
                 Input Sections
                       │
                       ▼
                linker script
                       │
        ┌──────────────┼──────────────┐
        ▼              ▼              ▼
       VMA            LMA           PHDRS
        │              │              │
        │              │              ▼
        │              │          PT_LOAD
        │              │              │
        │              └──────┐       │
        │                     │       │
        ▼                     ▼       ▼
      RAM                    ROM    FLAGS
        │                     │       │
        └──────────┬──────────┘       │
                   │                  │
                   ▼                  ▼
                  ELF Program Headers
                           │
                           ▼
                    真正的加载布局
```

---

# 四十九、到这里要真正建立一个思维转换

前 23 个实验，我们主要问：

> **这个 Section 放在哪里？**

从实验 24 开始，要问两个问题：

### 问题一

```text
这个 Section 在哪里？
```

看：

```text
readelf -S
objdump -h
```

### 问题二

```text
这个 Section 被哪个 Segment 加载？
```

看：

```text
readelf -lW
```

于是：

```text
Section 层
```

和：

```text
Segment 层
```

成为两个独立的分析维度。

---

# 五十、实验 24 的最终知识图

```text
                       ELF
                        │
            ┌───────────┴───────────┐
            │                       │
       Section 层                Segment 层
            │                       │
       readelf -S               readelf -lW
            │                       │
            ▼                       ▼
      .text/.data             PT_LOAD
      .rodata/.bss                 │
            │                       │
            └──────────┬────────────┘
                       │
                       ▼
                  linker script
                       │
        ┌──────────────┼──────────────┐
        │              │              │
       VMA            LMA           PHDRS
        │              │              │
       >RAM         AT>ROM        FLAGS()
                                      │
                                      ▼
                                  R E / R W
```

---

# 五十一、下一阶段：实验 25

下一节继续沿着这条主线进入：

# `PHDRS` + `FILEHDR` + `PHDRS` + `SIZEOF_HEADERS` + Segment 对齐

重点解决一个非常容易让人抓狂的问题：

```text
为什么我明明写了：

text PT_LOAD FLAGS(5);
data PT_LOAD FLAGS(6);

但是 readelf -l 的：

Offset
VirtAddr
PhysAddr
FileSiz
MemSiz
Align

看起来完全不像我想象的那样？
```

实验 25 会直接构造：

```text
ELF Header
     │
Program Header Table
     │
     ▼
PT_LOAD #1
R E
     │
     ├── .text
     └── .rodata

     ↓ page boundary

PT_LOAD #2
R W
     │
     ├── .data
     └── .bss
```

然后专门研究：

```ld
FILEHDR
PHDRS
SIZEOF_HEADERS
ALIGN(CONSTANT (MAXPAGESIZE))
AT()
PHDRS
```

以及为什么默认 Linux ELF 经常出现：

```text
0x1000
0x200000
```

这样的巨大对齐间隔。

最终还会专门做一个实验：

```text
默认 ld
        VS
自定义 PHDRS
        VS
去掉 MAXPAGESIZE 对齐
```

然后直接比较：

```bash
readelf -lW
size
objdump -h
ls -l
```

把“**为什么一个只有几百字节的程序，ELF 却突然变成几 KB、几十 KB 甚至更大**”这个问题彻底拆开。

[1]: https://sourceware.org/binutils/docs/ld.pdf?utm_source=chatgpt.com "The GNU linker"
[2]: https://sourceware.org/binutils/docs-2.41/ld.pdf?utm_source=chatgpt.com "The GNU linker"

