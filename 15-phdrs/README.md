# GNU ld 实战课程 · 实验 15

## 从 Section 到 Segment：用 `PHDRS` 构造真正的 Flash Image

上一节我们已经完成了一个非常关键的闭环：

```text
.data
  │
  ├── VMA → RAM
  └── LMA → ROM
        │
        ▼
   copy_data()
        │
        ▼
      RAM .data

.bss
  │
  ▼
clear_bss()
```

这一节继续向下深入一层：

> **Section 是 linker 的组织单位，而 Segment 才是 ELF loader 真正关心的装载单位。**

GNU `ld` 文档明确说明，ELF 的 Program Header 描述的是 Segment；系统 loader 根据这些 Program Header 判断如何装载程序。使用 `PHDRS` 后，linker 将按照你显式指定的 Program Header 生成 Segment。([Sourceware][1])

所以今天我们要从：

```text
Section
```

升级到：

```text
Segment
```

最终构造出一个更接近真实 MCU 固件的布局：

```text
Flash
0x00400000
┌──────────────────────────────┐
│ ELF / code load              │
├──────────────────────────────┤
│ .text                        │
├──────────────────────────────┤
│ .rodata                      │
├──────────────────────────────┤
│ .data 的 ROM 镜像            │
└──────────────────────────────┘

RAM
0x00600000
┌──────────────────────────────┐
│ .data                        │
├──────────────────────────────┤
│ .bss                         │
├──────────────────────────────┤
│ stack                        │
└──────────────────────────────┘
```

---

# 一、实验 15 的目标

今天完成：

```text
实验 15-1   Section → Segment
实验 15-2   使用 PHDRS 显式控制 PT_LOAD
实验 15-3   控制 Segment FLAGS
实验 15-4   分离 RX / RW Segment
实验 15-5   分析 VMA / LMA / File Offset
实验 15-6   从 Map + readelf -l 反推整个 Flash Image
实验 15-7   故意制造一个错误的 PHDRS
```

今天最重要的三个工具：

```bash
readelf -S
readelf -l
objdump -h
```

其中：

```text
-S
↓
Section

-l
↓
Program Header / Segment

-h
↓
Section 的 VMA/LMA/Size
```

---

# 二、先复习上一节的 Section 布局

我们使用：

```ld
MEMORY
{
    ROM (rx) : ORIGIN = 0x00400000, LENGTH = 64K
    RAM (rw) : ORIGIN = 0x00600000, LENGTH = 64K
}
```

然后：

```ld
.text   > ROM
.rodata > ROM
.data   > RAM AT > ROM
.bss    > RAM
```

形成：

```text
                 Section

ROM              RAM
 │                │
 ├─ .text         │
 │                │
 ├─ .rodata       │
 │                │
 └─ .data image  │
       │          │
       │          └─ .data
       │
       └───────────────→
```

但是这里存在一个问题：

> `.text`、`.rodata`、`.data`、`.bss` 到底应该属于哪些 ELF Segment？

这就是今天 `PHDRS` 的任务。

---

# 三、实验目录

继续沿用：

```text
ld-lab/
├── start.S
├── init.c
├── main.c
└── linker.ld
```

---

# 四、main.c

为了让 `.text`、`.rodata`、`.data`、`.bss` 都明显存在：

```c
const char message[] = "GNU ld";

int initialized_value = 0x12345678;

int zero_value;

int add(int a, int b)
{
    return a + b;
}

int main(void)
{
    int result = add(initialized_value, zero_value);

    if (message[0] != 'G')
        return 1;

    return result;
}
```

现在：

```text
message
    ↓
.rodata

initialized_value
    ↓
.data

zero_value
    ↓
.bss

add()
main()
    ↓
.text
```

所以 ELF 中至少有：

```text
.text
.rodata
.data
.bss
```

---

# 五、编译

```bash
gcc \
    -ffreestanding \
    -fno-pie \
    -fno-stack-protector \
    -c main.c \
    -o main.o
```

然后：

```bash
nm main.o
```

应该看到类似：

```text
T add
T main
D initialized_value
B zero_value
r message
```

注意：

```text
r message
```

表示：

```text
message
↓
只读数据
↓
.rodata
```

---

# 六、先看 `.o` 的 Section

```bash
objdump -h main.o
```

你应该能看到类似：

```text
.text
.data
.bss
.rodata
```

这里再次强调：

```text
main.o
```

中的：

```text
.text
.rodata
.data
.bss
```

都是 **Input Sections**。

之后 linker script 会把它们组织成 Output Sections。

例如：

```ld
.text :
{
    *(.text)
    *(.text.*)
}
```

意思是：

```text
多个 Input Section
       │
       ▼
Output Section
.text
```

---

# 七、先链接一个没有显式 `PHDRS` 的版本

为了理解 `PHDRS` 到底改变了什么，先不用 `PHDRS`。

创建：

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
        *(.rodata)
        *(.rodata.*)
    } > ROM

    .data :
    {
        _sdata = .;

        *(.data)
        *(.data.*)

        _edata = .;
    } > RAM AT > ROM

    _data_load = LOADADDR(.data);

    .bss :
    {
        _sbss = .;

        *(.bss)
        *(.bss.*)
        *(COMMON)

        _ebss = .;
    } > RAM
}
```

---

# 八、链接

```bash
ld \
    -T linker.ld \
    start.o \
    init.o \
    main.o \
    -o no-phdr.elf \
    -Map=no-phdr.map
```

---

# 九、先看 Section

```bash
readelf -S no-phdr.elf
```

你看到的是：

```text
.text
.rodata
.data
.bss
```

这回答：

> ELF 中有哪些 Section？

但是：

```bash
readelf -l no-phdr.elf
```

回答的是另一个问题：

> loader 应该加载哪些 Segment？

这两个概念一定要分开。

---

# 十、Section 和 Segment 的关系

可以把它理解成：

```text
Input Section
       │
       ▼
Output Section
       │
       ▼
Segment
```

例如：

```text
.text
.rodata
```

可能组成：

```text
PT_LOAD
R E
```

而：

```text
.data
.bss
```

可能组成：

```text
PT_LOAD
RW
```

于是：

```text
            ELF

       ┌──────────────┐
       │  Section     │
       ├──────────────┤
       │ .text        │
       │ .rodata      │
       ├──────────────┤
       │ .data        │
       │ .bss         │
       └──────────────┘
              │
              ▼
       Program Headers

       PT_LOAD RX
       PT_LOAD RW
```

---

# 十一、实验 15-1：加入 `PHDRS`

现在修改 linker.ld：

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

    .bss :
    {
        _sbss = .;

        *(.bss)
        *(.bss.*)
        *(COMMON)

        _ebss = .;
    } > RAM :data
}
```

这里第一次出现：

```ld
:text
```

和：

```ld
:data
```

它们不是 Section 名字。

而是：

> **PHDRS 中定义的 Program Header 名字。**

---

# 十二、`PHDRS` 到底定义了什么？

```ld
PHDRS
{
    text PT_LOAD FLAGS(5);
    data PT_LOAD FLAGS(6);
}
```

这里：

```text
text
```

是我们给 Program Header 起的 linker-script 名字。

```text
PT_LOAD
```

是 ELF Program Header Type。

```text
FLAGS(5)
```

指定：

```text
5 = R + X
```

而：

```text
FLAGS(6)
```

指定：

```text
6 = R + W
```

也就是：

```text
5 = 101b
    │ │
    │ └─ X
    └─── R

6 = 110b
    │ │
    │ └─ W
    └─── R
```

所以：

```text
text
    PT_LOAD
    R E

data
    PT_LOAD
    R W
```

GNU ld 文档说明，`PHDRS` 可以显式指定 Program Header，而 `FLAGS` 可以直接设置最终 Program Header 的 `p_flags`。([Sourceware][1])

---

# 十三、重新链接

```bash
ld \
    -T linker.ld \
    start.o \
    init.o \
    main.o \
    -o phdr.elf \
    -Map=phdr.map
```

---

# 十四、第一验证：`readelf -l`

```bash
readelf -l phdr.elf
```

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

你应该看到两个：

```text
LOAD
```

类似：

```text
LOAD  ...  R E
LOAD  ...  RW
```

这就是我们通过：

```ld
PHDRS
```

主动构造出来的两个 Segment。

---

# 十五、为什么 `FLAGS(5)` 是 `R E`？

ELF 的：

```text
p_flags
```

定义：

```text
PF_X = 1
PF_W = 2
PF_R = 4
```

因此：

```text
5 = 4 + 1
  = R + X
```

而：

```text
6 = 4 + 2
  = R + W
```

所以：

```text
FLAGS(5)
    ↓
R E

FLAGS(6)
    ↓
RW
```

这个小知识以后分析：

```text
LOAD
R E
LOAD
RW
```

非常有用。

---

# 十六、第二验证：`readelf -S`

```bash
readelf -S phdr.elf
```

现在不要只看地址。

我们要建立：

```text
Section → Segment
```

的映射。

`readelf -l` 最后通常会显示：

```text
Section to Segment mapping:
```

这部分就是今天的重点。

---

# 十七、观察 Section to Segment mapping

你会看到类似：

```text
Section to Segment mapping:

 Segment Sections...
   00     .text .rodata
   01     .data .bss
```

于是：

```text
PT_LOAD[0]
    ↓
.text
.rodata

PT_LOAD[1]
    ↓
.data
.bss
```

这就是：

# Section → Segment

---

# 十八、实验 15-2：为什么 `.bss` 可以进入 RW Segment？

我们写：

```ld
.bss :
{
    *(.bss)
} > RAM :data
```

所以：

```text
.bss
 ↓
data PHDR
 ↓
PT_LOAD
 ↓
RW
```

这完全合理：

```text
.bss
```

运行时需要：

```text
RAM
```

而 RAM 通常需要：

```text
R + W
```

因此：

```text
.bss
    ↓
RW segment
```

非常自然。

---

# 十九、实验 15-3：观察 `FileSiz` 和 `MemSiz`

执行：

```bash
readelf -l phdr.elf
```

重点看：

```text
FileSiz
MemSiz
```

假设：

```text
.data = 4 bytes
.bss  = 4 bytes
```

那么：

```text
FileSiz
```

可能接近：

```text
4
```

而：

```text
MemSiz
```

可能是：

```text
8
```

原因：

```text
.data
    有文件内容

.bss
    NOBITS
    只有内存空间
```

因此：

```text
MemSiz
=
FileSiz
+
.bss
```

这是 ELF 中一个非常重要的设计。

---

# 二十、用公式理解

假设：

```text
.data
size = 0x10

.bss
size = 0x20
```

那么：

```text
FileSiz
≈ 0x10
```

而：

```text
MemSiz
≈ 0x30
```

于是：

```text
       file
         │
         ├── .data 0x10
         │
         └── EOF

memory
         │
         ├── .data 0x10
         │
         └── .bss  0x20
```

所以：

```text
FileSiz < MemSiz
```

并不是异常。

它正是 `.bss` 的意义。

---

# 二十一、实验 15-4：观察 File Offset

执行：

```bash
objdump -h phdr.elf
```

观察：

```text
Idx
Name
Size
VMA
LMA
File off
```

例如：

```text
.text
    VMA = 0x00400000
    LMA = 0x00400000

.rodata
    VMA = ...
    LMA = ...

.data
    VMA = 0x00600000
    LMA = 0x0040....
```

这里非常关键：

```text
VMA
≠
File Offset
```

不要混淆。

---

# 二十二、三个地址概念现在必须彻底分开

到这里我们已经至少有三个“位置”：

## 1. VMA

```text
Virtual Memory Address
```

程序运行时地址。

例如：

```text
.data
VMA = 0x00600000
```

---

## 2. LMA

```text
Load Memory Address
```

section 初始镜像的加载地址。

例如：

```text
.data
LMA = 0x00400xxx
```

---

## 3. File Offset

ELF 文件内部：

```text
从文件开头数多少字节
```

例如：

```text
.data
File Offset = 0x....
```

所以：

```text
.data

VMA
0x00600000

LMA
0x00400xxx

File Offset
0x....
```

三个完全不同的概念。

---

# 二十三、画出来就清楚了

```text
             ELF 文件
0x00000000
│
├── ELF Header
│
├── Program Headers
│
├── .text
│
├── .rodata
│
└── .data image
       │
       │ File Offset
       │
       │ LMA
       ▼
    Flash / ROM

             Runtime

RAM
0x00600000
│
├── .data
│
└── .bss
```

于是：

```text
File Offset
    ↓
ELF 文件里的位置

LMA
    ↓
加载镜像地址

VMA
    ↓
运行地址
```

---

# 二十四、实验 15-5：让 `.rodata` 与 `.text` 进入同一个 Segment

现在：

```ld
.text :
{
    *(.text)
} > ROM :text

.rodata :
{
    *(.rodata)
} > ROM :text
```

这意味着：

```text
.text
.rodata
    │
    └── :text
          ↓
        PT_LOAD
          ↓
        R E
```

所以：

```text
PT_LOAD RX
├── .text
└── .rodata
```

这是典型的：

```text
代码 + 只读数据
```

布局。

---

# 二十五、为什么 `.rodata` 通常可以和 `.text` 放一起？

因为：

```text
.text
```

需要：

```text
R + X
```

而：

```text
.rodata
```

需要：

```text
R
```

因此：

```text
R E
```

Segment 完全可以承载：

```text
.text
.rodata
```

它们都不需要：

```text
W
```

所以：

```text
RX
```

是很自然的组合。

---

# 二十六、实验 15-6：让 `.data` 独立成 RW Segment

继续：

```ld
.data :
{
    _sdata = .;

    *(.data)

    _edata = .;
} > RAM AT > ROM :data
```

然后：

```ld
.bss :
{
    _sbss = .;

    *(.bss)
    *(COMMON)

    _ebss = .;
} > RAM :data
```

最终：

```text
Segment 0
PT_LOAD
R E

    .text
    .rodata


Segment 1
PT_LOAD
R W

    .data
    .bss
```

这是非常经典的 ELF 布局。

---

# 二十七、这时候 `readelf -l` 应该成为你的“第一观察工具”

执行：

```bash
readelf -l phdr.elf
```

重点看：

```text
Program Headers:
```

然后：

```text
Section to Segment mapping:
```

建议以后每次修改 linker script，都执行：

```bash
readelf -S xxx.elf
readelf -l xxx.elf
objdump -h xxx.elf
```

三件套。

---

# 二十八、实验 15-7：Map 文件分析

执行：

```bash
grep -A 40 -B 5 "\.text" phdr.map
```

你会看到：

```text
.text
    ...
    main.o
    init.o
    start.o
```

然后：

```bash
grep -A 30 -B 5 "\.data" phdr.map
```

观察：

```text
.data
    main.o
        initialized_value
```

再：

```bash
grep -A 30 -B 5 "\.bss" phdr.map
```

观察：

```text
.bss
    main.o
        zero_value
```

---

# 二十九、Map 文件和 `readelf -l` 要结合起来看

这是今天非常重要的分析方法：

### Map

告诉你：

```text
谁进入了哪个 Output Section？
```

### readelf -S

告诉你：

```text
Output Section 的地址和属性是什么？
```

### readelf -l

告诉你：

```text
Output Section 属于哪个 Segment？
```

### objdump -h

告诉你：

```text
VMA / LMA / File Offset / Size
```

所以完整分析链：

```text
                 map
                  │
                  ▼
       Input → Output Section
                  │
                  ▼
             readelf -S
                  │
                  ▼
                VMA
                  │
                  ▼
             readelf -l
                  │
                  ▼
               Segment
                  │
                  ▼
             objdump -h
                  │
          ┌───────┼───────┐
          ▼       ▼       ▼
         VMA     LMA   File Offset
```

---

# 三十、实验 15-8：故意把 `.data` 放进 RX Segment

现在故意修改：

```ld
.data :
{
    *(.data)
} > RAM AT > ROM :text
```

注意：

```text
:text
```

而不是：

```text
:data
```

重新：

```bash
ld \
    -T linker.ld \
    start.o init.o main.o \
    -o bad-phdr.elf \
    -Map=bad-phdr.map
```

然后：

```bash
readelf -l bad-phdr.elf
```

你会发现：

```text
.data
```

可能进入：

```text
R E
```

Segment。

这就是一个典型的 linker script 错误：

```text
.data
需要 RW

结果
进入 RX
```

---

# 三十一、为什么这很危险？

因为：

```text
.data
```

运行时需要修改：

```c
initialized_value++;
```

但是 Segment：

```text
R E
```

没有：

```text
W
```

于是：

```text
运行时写 .data
        ↓
违反内存权限
        ↓
可能产生 fault
```

在真正的 MCU/MMU 系统中，这是严重问题。

所以：

```text
.text
.rodata
    ↓
RX

.data
.bss
    ↓
RW
```

是一个非常值得记住的设计原则。

---

# 三十二、实验 15-9：验证 Segment Flags

执行：

```bash
readelf -l phdr.elf
```

观察：

```text
Flg
```

典型：

```text
R E
RW
```

再：

```bash
objdump -p phdr.elf
```

也可以直接查看 Program Header 相关信息。GNU ld 文档指出，Program Headers 可以通过 `objdump -p` 查看。([Sourceware][1])

---

# 三十三、实验 15-10：理解 `:phdr` 的“继承”行为

GNU ld 的 linker script 有一个很容易忽略的规则：

如果一个 allocatable output section 已经通过：

```ld
:phdr
```

放入某个 segment，那么后面的 section 如果没有显式指定 `:phdr`，可能会继续沿用之前的 segment 映射。

因此实验中最好明确写：

```ld
.text   : { ... } :text
.rodata : { ... } :text

.data   : { ... } :data
.bss    : { ... } :data
```

而不要大量依赖隐式继承。

GNU ld 文档明确描述了这种 `:phdr` 映射的继承行为，以及可以使用 `:NONE` 清除默认 segment 映射。([Sourceware][2])

---

# 三十四、推荐的写法

对于教学和实际工程：

```ld
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
    *(.data)
    *(.data.*)
} > RAM AT > ROM :data

.bss :
{
    *(.bss)
    *(.bss.*)
    *(COMMON)
} > RAM :data
```

这样一眼就知道：

```text
.text
.rodata
    → text segment

.data
.bss
    → data segment
```

---

# 三十五、实验 15-11：让 Flash 中的 `.data` 紧跟 `.rodata`

现在我们进一步控制：

```text
ROM:

.text
.rodata
.data image
```

使用：

```ld
.data :
{
    _sdata = .;

    *(.data)
    *(.data.*)

    _edata = .;
}
> RAM
AT(LOADADDR(.rodata) + SIZEOF(.rodata))
:data
```

这里：

```ld
LOADADDR(.rodata)
```

获得：

```text
.rodata LMA
```

然后：

```ld
SIZEOF(.rodata)
```

得到：

```text
.rodata size
```

所以：

```text
.data LMA
=
.rodata LMA + .rodata size
```

形成：

```text
ROM
│
├── .text
├── .rodata
└── .data image
```

---

# 三十六、这个公式非常值得掌握

```ld
AT(
    LOADADDR(.rodata)
    + SIZEOF(.rodata)
)
```

意思就是：

```text
.data 的 Flash 镜像
=
.rodata 镜像结束之后
```

因此：

```text
       ROM

.text
  │
  ▼
.rodata
  │
  ▼
.data image
```

而运行时：

```text
       RAM

.data
  │
  ▼
.bss
```

于是：

```text
LMA
```

和：

```text
VMA
```

彻底解耦。

---

# 三十七、实验 15-12：用 Map 验证这个公式

执行：

```bash
grep -A 40 -B 5 "\.rodata" phdr.map
```

然后：

```bash
grep -A 40 -B 5 "\.data" phdr.map
```

计算：

```text
.data LMA
=
.rodata LMA
+
.rodata SIZE
```

再通过：

```bash
objdump -h phdr.elf
```

验证：

```text
.data LMA
```

是否与计算结果一致。

这就是 linker script 实验非常重要的一种学习方法：

> **不要只相信 linker 输出，自己根据表达式计算一次。**

---

# 三十八、现在建立“Section / Segment / Memory Region”三层关系

这是本节最重要的抽象。

```text
              linker.ld
                  │
       ┌──────────┼───────────┐
       ▼          ▼           ▼
    Section     Segment    MEMORY
       │          │           │
       │          │           │
       ▼          ▼           ▼
   .text        PT_LOAD      ROM
   .rodata      PT_LOAD      RAM
   .data
   .bss
```

具体关系：

```text
.text
   │
   ├── VMA → ROM
   └── PHDR → text

.rodata
   │
   ├── VMA → ROM
   └── PHDR → text

.data
   │
   ├── VMA → RAM
   ├── LMA → ROM
   └── PHDR → data

.bss
   │
   ├── VMA → RAM
   └── PHDR → data
```

这张图建议你真正理解，而不是背。

---

# 三十九、为什么 `MEMORY` 和 `PHDRS` 不是一回事？

这是一个特别容易混淆的地方。

## `MEMORY`

回答：

> **Section 的地址空间在哪里？**

例如：

```ld
ROM = 0x00400000
RAM = 0x00600000
```

---

## `PHDRS`

回答：

> **这些 Section 在 ELF 中属于哪个 Program Segment？**

例如：

```text
text → PT_LOAD RX
data → PT_LOAD RW
```

所以：

```text
MEMORY
    ↓
地址空间

PHDRS
    ↓
ELF 装载组织
```

两者完全不是一个层级。

---

# 四十、一个非常重要的对照表

| linker script | 回答的问题                        |
| ------------- | ---------------------------- |
| `MEMORY`      | 地址空间有哪些？                     |
| `> ROM`       | Section 的 VMA 放哪里？           |
| `AT > ROM`    | Section 的 LMA 从哪里分配？         |
| `PHDRS`       | Segment 如何定义？                |
| `:text`       | Section 属于哪个 Program Header？ |
| `ADDR()`      | Section VMA 是多少？             |
| `LOADADDR()`  | Section LMA 是多少？             |
| `SIZEOF()`    | Section 多大？                  |
| `readelf -S`  | Section 长什么样？                |
| `readelf -l`  | Segment 长什么样？                |
| `objdump -h`  | VMA/LMA/Offset/Size          |
| Map           | linker 为什么这样布局？              |

---

# 四十一、实验 15-13：最终版 linker.ld

这一节推荐最终保留这个版本：

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

    _bss_size = SIZEOF(.bss);
}
```

这里：

```text
.text
.rodata
```

进入：

```text
text PT_LOAD RX
```

而：

```text
.data
.bss
```

进入：

```text
data PT_LOAD RW
```

---

# 四十二、完整验证流程

每次修改 linker.ld 后，建议固定执行：

```bash
rm -f *.o *.elf *.map
```

然后：

```bash
gcc \
    -ffreestanding \
    -fno-pie \
    -fno-stack-protector \
    -c main.c \
    -o main.o

gcc \
    -ffreestanding \
    -fno-pie \
    -fno-stack-protector \
    -c init.c \
    -o init.o

gcc -c start.S -o start.o
```

链接：

```bash
ld \
    -T linker.ld \
    start.o \
    init.o \
    main.o \
    -o phdr.elf \
    -Map=phdr.map
```

然后按这个顺序：

```bash
nm -n phdr.elf
```

↓

```bash
readelf -S phdr.elf
```

↓

```bash
readelf -l phdr.elf
```

↓

```bash
objdump -h phdr.elf
```

↓

```bash
objdump -p phdr.elf
```

↓

```bash
objdump -d phdr.elf
```

↓

```bash
less phdr.map
```

---

# 四十三、今天真正要掌握的是这条链

```text
                C / ASM
                   │
                   ▼
                  .o
                   │
                   ▼
             Input Sections
                   │
                   ▼
             Output Sections
                   │
        ┌──────────┴──────────┐
        ▼                     ▼
      VMA/LMA              PHDRS
        │                     │
        ▼                     ▼
     MEMORY               Segment
        │                     │
        └──────────┬──────────┘
                   ▼
                  ELF
                   │
        ┌──────────┼──────────┐
        ▼          ▼          ▼
    readelf -S readelf -l objdump -h
        │          │          │
        └──────────┼──────────┘
                   ▼
                  Map
```

这一步之后，GNU `ld` 就从：

> “怎么把 `.text`、`.data` 放到某个地址？”

正式升级成：

> **“怎么设计整个 ELF 的内存布局和装载布局？”**

---

# 四十四、下一节：实验 16

下一节继续进入一个非常关键的 GNU `ld` 能力：

# 实验 16：`OVERLAY` —— 同一块 RAM 放多个代码模块

我们会构造：

```text
FLASH
│
├── module_a
├── module_b
└── module_c
       │
       │ load
       ▼
RAM
0x00600000
┌───────────────────┐
│ module_a          │
│                   │
└───────────────────┘

运行 module_b 时：

┌───────────────────┐
│ module_b          │
│                   │
└───────────────────┘

运行 module_c 时：

┌───────────────────┐
│ module_c          │
│                   │
└───────────────────┘
```

也就是说：

```text
多个模块
   ↓
不同 LMA
   ↓
相同/重叠 VMA
   ↓
运行时按需搬运
```

这会把我们目前已经掌握的：

```text
VMA
LMA
AT()
LOADADDR()
SIZEOF()
PHDRS
MEMORY
```

全部串起来。

而且还会第一次真正碰到：

```text
“多个 Section 可以拥有重叠运行地址”
```

这正是 GNU ld `OVERLAY` 的用武之地。GNU ld 文档也明确说明，overlay 用于让多个 section 共享同一运行地址空间，而它们在输出文件中的加载地址不同。([Sourceware][3])

这会是从普通 ELF 链接脚本进入**嵌入式固件高级链接布局**的一个很漂亮的分水岭。

[1]: https://sourceware.org/binutils/docs-2.40/ld.pdf?utm_source=chatgpt.com "The GNU linker"
[2]: https://sourceware.org/binutils/docs-2.43/ld.pdf?utm_source=chatgpt.com "The GNU linker"
[3]: https://sourceware.org/gdb/current/onlinedocs/gdb?utm_source=chatgpt.com "Debugging with GDB"

