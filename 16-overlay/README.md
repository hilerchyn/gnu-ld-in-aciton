# GNU ld 实战课程 · 实验 16

## `OVERLAY`：让多个模块共享同一块 RAM/执行地址空间

上一节我们已经从：

```text
Section
   ↓
VMA / LMA
   ↓
Segment
   ↓
PHDRS
```

进入了 ELF 的装载布局。

这一节继续沿着这条路线走一个很漂亮的高级实验：

> **多个程序模块在 Flash 中各自保存，但运行时共享同一块 RAM/执行地址。**

这就是 GNU `ld` 的：

```ld
OVERLAY
```

官方 linker 文档规定，`OVERLAY` 中的各个 section **拥有相同的 VMA/运行地址**，但 linker 会把它们安排到连续的 LMA/加载地址；同时 linker 会自动生成 `__load_start_secname` 和 `__load_stop_secname` 符号。([Sourceware][1])

这和上一节的：

```text
.data
VMA = RAM
LMA = ROM
```

相比又前进了一步：

```text
module_a
VMA = 0x00600000
LMA = 0x0040....

module_b
VMA = 0x00600000
LMA = 0x0040....

module_c
VMA = 0x00600000
LMA = 0x0040....
```

也就是：

# 不同 LMA，相同 VMA。

---

# 一、为什么需要 Overlay？

假设一个 MCU：

```text
Flash = 512 KB
RAM   = 64 KB
```

我们有：

```text
算法 A = 20 KB
算法 B = 24 KB
算法 C = 18 KB
```

如果全部同时放 RAM：

```text
20 + 24 + 18
=
62 KB
```

再加：

```text
.data
.bss
stack
heap
```

很容易爆 RAM。

但是如果：

```text
算法 A
算法 B
算法 C
```

**不会同时执行**，那么完全可以：

```text
Flash

A
B
C
```

全部保存。

RAM：

```text
┌─────────────────┐
│ Overlay Area    │
│                 │
│ A OR B OR C     │
└─────────────────┘
```

运行 A：

```text
Flash A
   ↓
RAM Overlay Area
```

运行 B：

```text
Flash B
   ↓
RAM Overlay Area
```

运行 C：

```text
Flash C
   ↓
RAM Overlay Area
```

这样 RAM 只需要容纳：

```text
max(
    sizeof(A),
    sizeof(B),
    sizeof(C)
)
```

而不是：

```text
sizeof(A)
+
sizeof(B)
+
sizeof(C)
```

这正是 overlay 的核心思想。GDB 对 overlay 的解释也是：多个 overlay 使用同一个映射地址，因此同一时刻只能有一个 overlay 映射在那里。([Sourceware][2])

---

# 二、今天的实验模型

继续使用：

```text
ROM
0x00400000
64 KB

RAM
0x00600000
64 KB
```

我们构造：

```text
Flash / ROM
────────────────────────────

.text
.rodata

.overlay_a
.overlay_b
.overlay_c


RAM
────────────────────────────

.data
.bss

0x00602000
┌──────────────────────────┐
│ Overlay Area             │
│                          │
│ A / B / C               │
│                          │
└──────────────────────────┘
```

关键：

```text
.overlay_a VMA = 0x00602000
.overlay_b VMA = 0x00602000
.overlay_c VMA = 0x00602000
```

但：

```text
.overlay_a LMA = 0x0040xxxx
.overlay_b LMA = 0x0040yyyy
.overlay_c LMA = 0x0040zzzz
```

---

# 三、实验目录

```text
ld-lab/
├── start.S
├── main.c
├── overlay_a.c
├── overlay_b.c
├── overlay_c.c
└── linker.ld
```

---

# 四、实验 16-1：三个 Overlay 模块

先创建 `overlay_a.c`：

```c
int overlay_a(void)
{
    return 100;
}
```

`overlay_b.c`：

```c
int overlay_b(void)
{
    return 200;
}
```

`overlay_c.c`：

```c
int overlay_c(void)
{
    return 300;
}
```

现在三个模块：

```text
overlay_a.o
    T overlay_a

overlay_b.o
    T overlay_b

overlay_c.o
    T overlay_c
```

---

# 五、编译三个模块

```bash
gcc \
    -ffreestanding \
    -fno-pie \
    -fno-stack-protector \
    -c overlay_a.c \
    -o overlay_a.o

gcc \
    -ffreestanding \
    -fno-pie \
    -fno-stack-protector \
    -c overlay_b.c \
    -o overlay_b.o

gcc \
    -ffreestanding \
    -fno-pie \
    -fno-stack-protector \
    -c overlay_c.c \
    -o overlay_c.o
```

然后：

```bash
nm overlay_a.o
nm overlay_b.o
nm overlay_c.o
```

应该分别看到：

```text
T overlay_a
```

```text
T overlay_b
```

```text
T overlay_c
```

---

# 六、先看看普通 Section 的情况

```bash
objdump -h overlay_a.o
```

你会看到：

```text
.text
.data
.bss
```

我们现在希望把：

```text
overlay_a.o:.text
```

变成：

```text
.overlay_a
```

因此给 C 函数增加 section attribute：

```c
__attribute__((section(".overlay_a")))
int overlay_a(void)
{
    return 100;
}
```

于是最终：

```text
overlay_a.o
    │
    └── .overlay_a
            │
            └── overlay_a()
```

同样：

```c
__attribute__((section(".overlay_b")))
int overlay_b(void)
{
    return 200;
}
```

以及：

```c
__attribute__((section(".overlay_c")))
int overlay_c(void)
{
    return 300;
}
```

---

# 七、重新编译

```bash
gcc \
    -ffreestanding \
    -fno-pie \
    -fno-stack-protector \
    -c overlay_a.c \
    -o overlay_a.o

gcc \
    -ffreestanding \
    -fno-pie \
    -fno-stack-protector \
    -c overlay_b.c \
    -o overlay_b.o

gcc \
    -ffreestanding \
    -fno-pie \
    -fno-stack-protector \
    -c overlay_c.c \
    -o overlay_c.o
```

---

# 八、验证 Input Section

分别：

```bash
objdump -h overlay_a.o
```

```bash
objdump -h overlay_b.o
```

```bash
objdump -h overlay_c.o
```

现在应该看到：

```text
.overlay_a
```

```text
.overlay_b
```

```text
.overlay_c
```

这一步非常重要：

```text
C function
    ↓
Input Section
```

我们马上要让 linker：

```text
Input Section
    ↓
OVERLAY Output Sections
```

---

# 九、先建立 main.c

为了先观察符号，不需要真的执行 overlay：

```c
extern int overlay_a(void);
extern int overlay_b(void);
extern int overlay_c(void);

int main(void)
{
    return overlay_a();
}
```

这里故意只调用：

```text
overlay_a()
```

因为真正的 overlay 运行时通常需要 overlay manager 来负责：

```text
Flash
 ↓
copy
 ↓
Overlay RAM
```

---

# 十、实验 16-2：第一次写 `OVERLAY`

linker script：

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

    . = 0x00602000;

    OVERLAY :
    {
        .overlay_a
        {
            *(.overlay_a)
        }

        .overlay_b
        {
            *(.overlay_b)
        }

        .overlay_c
        {
            *(.overlay_c)
        }
    } > RAM AT > ROM :data

    .data :
    {
        _sdata = .;

        *(.data)
        *(.data.*)

        _edata = .;
    } > RAM AT > ROM :data

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

这里就是今天最核心的：

```ld
OVERLAY :
{
    .overlay_a
    {
        *(.overlay_a)
    }

    .overlay_b
    {
        *(.overlay_b)
    }

    .overlay_c
    {
        *(.overlay_c)
    }
}
```

---

# 十一、一个关键规则：Overlay 内不能自己指定地址

注意：

```ld
OVERLAY :
{
    .overlay_a
    {
        *(.overlay_a)
    }

    .overlay_b
    {
        *(.overlay_b)
    }
}
```

里面不要写：

```ld
.overlay_a 0x00602000 :
```

也不要：

```ld
.overlay_b > RAM
```

因为：

> Overlay 中的 section 自动共享 Overlay 的 VMA。

GNU ld 文档明确指出，`OVERLAY` 内部的 section 定义类似普通 output section，但**不能为这些内部 section 单独指定地址或 memory region**。([Sourceware][1])

---

# 十二、为什么三个 Section 会拥有同一个 VMA？

这就是：

```ld
OVERLAY
```

的核心语义。

假设：

```text
Overlay VMA
=
0x00602000
```

那么：

```text
.overlay_a
VMA = 0x00602000

.overlay_b
VMA = 0x00602000

.overlay_c
VMA = 0x00602000
```

注意：

```text
Size
```

可以不同。

例如：

```text
.overlay_a = 0x20
.overlay_b = 0x40
.overlay_c = 0x30
```

那么：

```text
RAM
0x00602000
│
├── A 0x20
│
├── B 0x40
│
└── C 0x30
```

**不是实际同时占用这 0x90 字节。**

它们在运行地址空间上重叠。

实际 Overlay RAM 需要：

```text
max(0x20, 0x40, 0x30)
=
0x40
```

也就是：

```text
64 bytes
```

---

# 十三、链接

先编译 `main.c`：

```bash
gcc \
    -ffreestanding \
    -fno-pie \
    -fno-stack-protector \
    -c main.c \
    -o main.o
```

再：

```bash
gcc -c start.S -o start.o
```

链接：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    overlay_a.o \
    overlay_b.o \
    overlay_c.o \
    -o overlay.elf \
    -Map=overlay.map
```

---

# 十四、第一次观察：`readelf -S`

```bash
readelf -S overlay.elf
```

重点找：

```text
.overlay_a
.overlay_b
.overlay_c
```

你会发现一个非常反直觉的现象：

```text
Address
```

三者应该相同或者从 linker 的 overlay 起始地址开始共享同一 VMA。

例如：

```text
.overlay_a    0x00602000
.overlay_b    0x00602000
.overlay_c    0x00602000
```

这就是：

# 同一个 VMA。

---

# 十五、第二次观察：`objdump -h`

执行：

```bash
objdump -h overlay.elf
```

重点：

```text
Name
Size
VMA
LMA
```

你可能看到类似：

```text
.overlay_a
Size = 0x10
VMA  = 0x00602000
LMA  = 0x0040xxxx

.overlay_b
Size = 0x10
VMA  = 0x00602000
LMA  = 0x0040yyyy

.overlay_c
Size = 0x10
VMA  = 0x00602000
LMA  = 0x0040zzzz
```

这张表非常重要：

| Section      |        VMA |        LMA |
| ------------ | ---------: | ---------: |
| `.overlay_a` | 0x00602000 | 0x0040xxxx |
| `.overlay_b` | 0x00602000 | 0x0040yyyy |
| `.overlay_c` | 0x00602000 | 0x0040zzzz |

于是：

```text
VMA
A = B = C

LMA
A ≠ B ≠ C
```

这就是 Overlay 的本质。

---

# 十六、现在看 ROM

想象：

```text
ROM
0x00400000

.text
.rodata

.overlay_a
      ↓
0x0040xxxx

.overlay_b
      ↓
0x0040yyyy

.overlay_c
      ↓
0x0040zzzz
```

这些模块在 Flash 中：

```text
各自独立保存
```

但是 RAM：

```text
0x00602000

┌─────────────────┐
│ overlay_a       │
│ OR              │
│ overlay_b       │
│ OR              │
│ overlay_c       │
└─────────────────┘
```

永远只有一个实际映射。

---

# 十七、实验 16-3：观察 linker 自动生成的符号

这是 `OVERLAY` 非常漂亮的地方。

GNU ld 会自动为每个 overlay section 生成：

```text
__load_start_secname
__load_stop_secname
```

例如：

```text
__load_start_overlay_a
__load_stop_overlay_a

__load_start_overlay_b
__load_stop_overlay_b

__load_start_overlay_c
__load_stop_overlay_c
```

官方文档明确规定了这一行为。([Sourceware][1])

---

# 十八、用 `nm` 验证

```bash
nm -n overlay.elf | grep __load
```

应该看到类似：

```text
__load_start_overlay_a
__load_stop_overlay_a

__load_start_overlay_b
__load_stop_overlay_b

__load_start_overlay_c
__load_stop_overlay_c
```

现在 linker 已经自动告诉我们：

```text
A 在 ROM 哪里？
B 在 ROM 哪里？
C 在 ROM 哪里？
```

---

# 十九、计算每个 Overlay 的大小

例如：

```text
__load_start_overlay_a
__load_stop_overlay_a
```

那么：

```text
size_a
=
__load_stop_overlay_a
-
__load_start_overlay_a
```

同理：

```text
size_b
=
__load_stop_overlay_b
-
__load_start_overlay_b
```

```text
size_c
=
__load_stop_overlay_c
-
__load_start_overlay_c
```

于是运行时 overlay manager 可以：

```text
src
=
__load_start_overlay_a

dst
=
0x00602000

size
=
__load_stop_overlay_a
-
__load_start_overlay_a
```

然后：

```c
memcpy(dst, src, size);
```

---

# 二十、这和上一节 `.data` 搬运高度相似

上一节：

```text
.data

source:
    LOADADDR(.data)

destination:
    ADDR(.data)

size:
    SIZEOF(.data)
```

这一节：

```text
.overlay_a

source:
    __load_start_overlay_a

destination:
    Overlay VMA

size:
    __load_stop_overlay_a
    -
    __load_start_overlay_a
```

所以可以把 Overlay 看成：

> **`.data` ROM → RAM 搬运模型的升级版。**

只不过：

```text
.data
```

是：

```text
一个源
→
一个固定 RAM 区域
```

而：

```text
OVERLAY
```

是：

```text
多个源
→
同一个 RAM 区域
```

---

# 二十一、实验 16-4：使用 `NOCROSSREFS`

Overlay 有一个特别危险的问题：

```text
overlay_a
    ↓
调用
overlay_b
```

例如：

```c
extern int overlay_b(void);

__attribute__((section(".overlay_a")))
int overlay_a(void)
{
    return overlay_b();
}
```

为什么危险？

因为：

```text
A
```

运行的时候：

```text
RAM Overlay Area
    ↓
A
```

但：

```text
B
```

没有同时加载。

如果：

```text
A → B
```

那么：

```text
call B
```

可能跳到：

```text
同一个 VMA
```

但是那里实际还是：

```text
A
```

于是程序直接跑飞。

GDB 文档也特别强调：调用 overlay 中函数之前必须确保对应 overlay 已映射，否则虽然跳到正确的地址，却可能处于错误的 overlay。([Sourceware][2])

---

# 二十二、使用 `NOCROSSREFS` 防止这个问题

把：

```ld
OVERLAY :
```

改成：

```ld
OVERLAY NOCROSSREFS :
```

例如：

```ld
OVERLAY NOCROSSREFS :
{
    .overlay_a
    {
        *(.overlay_a)
    }

    .overlay_b
    {
        *(.overlay_b)
    }

    .overlay_c
    {
        *(.overlay_c)
    }
} > RAM AT > ROM :data
```

现在：

```text
A → B
```

属于：

```text
Cross Reference
```

linker 会报错。

GNU ld 文档明确说明，`NOCROSSREFS` 用于检查 overlay section 之间的交叉引用；由于这些 section 共享运行地址，直接相互引用通常没有意义。([Sourceware][1])

---

# 二十三、实验：故意制造 Cross Reference

修改：

```c
extern int overlay_b(void);

__attribute__((section(".overlay_a")))
int overlay_a(void)
{
    return overlay_b();
}
```

编译：

```bash
gcc \
    -ffreestanding \
    -fno-pie \
    -fno-stack-protector \
    -c overlay_a.c \
    -o overlay_a.o
```

重新链接：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    overlay_a.o \
    overlay_b.o \
    overlay_c.o \
    -o overlay-cross.elf \
    -Map=overlay-cross.map
```

如果使用：

```ld
OVERLAY NOCROSSREFS
```

应该得到类似：

```text
prohibited cross reference from .overlay_a
to `overlay_b' in .overlay_b
```

具体错误文本可能因 binutils 版本有所差异。

---

# 二十四、这个错误非常有价值

因为它不是：

```text
语法错误
```

也不是：

```text
地址溢出
```

而是：

```text
linker 在帮你检查架构设计错误。
```

即：

```text
A
 ↓
B
```

但是：

```text
A
B
```

共享：

```text
同一个 VMA
```

所以直接调用：

```text
A → B
```

在没有 overlay manager 的情况下是危险的。

---

# 二十五、实验 16-5：观察 Map 文件

执行：

```bash
grep -A 50 -B 5 "overlay_a" overlay.map
```

再：

```bash
grep -A 50 -B 5 "overlay_b" overlay.map
```

再：

```bash
grep -A 50 -B 5 "overlay_c" overlay.map
```

Map 中重点观察：

```text
.overlay_a
.overlay_b
.overlay_c
```

它们的：

```text
VMA
Size
Load Address
```

关系。

---

# 二十六、Map 中最值得关注的现象

你应该看到：

```text
.overlay_a
    VMA = X
    LMA = A

.overlay_b
    VMA = X
    LMA = B

.overlay_c
    VMA = X
    LMA = C
```

其中：

```text
X
```

相同。

而：

```text
A
B
C
```

递增。

例如：

```text
RAM VMA:

0x00602000
   ↑
   │
   ├── A
   ├── B
   └── C
       都从这里运行


ROM LMA:

0x00401000
   ├── A

0x00401020
   ├── B

0x00401040
   └── C
```

---

# 二十七、这就是 `OVERLAY` 最漂亮的地方

普通 section：

```text
Section A
VMA A
LMA A

Section B
VMA B
LMA B
```

Overlay：

```text
Section A
VMA X
LMA A

Section B
VMA X
LMA B

Section C
VMA X
LMA C
```

即：

```text
VMA
    ┌───────┬───────┬───────┐
    │       │       │       │
    A       B       C
    │       │       │
    └───────┴───────┴───────┘
             X

LMA
    A       B       C
    │       │       │
    ▼       ▼       ▼
   ROM     ROM     ROM
```

---

# 二十八、实验 16-6：确定 Overlay 的 RAM 大小

假设：

```text
A = 0x20
B = 0x40
C = 0x30
```

那么：

```text
Overlay RAM size
=
max(0x20, 0x40, 0x30)
=
0x40
```

GNU ld 在 `OVERLAY` 结束后，会把 location counter 设置为：

```text
overlay start
+
largest section size
```

也就是说，后面的普通 section 会从：

```text
Overlay VMA + 最大 Overlay Size
```

开始，而不是：

```text
Overlay VMA + 所有 Overlay Size
```

这是 Overlay 能够节省 RAM 的关键机制。([Sourceware][1])

---

# 二十九、可以通过 Map 验证

假设：

```text
Overlay start = 0x00602000

A = 0x20
B = 0x40
C = 0x30
```

那么后续：

```text
.
```

应该来到：

```text
0x00602000 + 0x40
=
0x00602040
```

而不是：

```text
0x00602000 + 0x20 + 0x40 + 0x30
```

这就是一个非常好的实验：

> **不要只看 overlay 三个 section 的地址，要看 overlay 结束后 `.` 到哪里。**

---

# 三十、实验 16-7：给 Overlay 设置明确的起始地址

可以：

```ld
OVERLAY 0x00602000 : AT(0x00401000)
{
    .overlay_a
    {
        *(.overlay_a)
    }

    .overlay_b
    {
        *(.overlay_b)
    }

    .overlay_c
    {
        *(.overlay_c)
    }
} > RAM
```

这里：

```text
0x00602000
```

是：

```text
Overlay VMA
```

而：

```text
AT(0x00401000)
```

是：

```text
Overlay 整体的 LMA 起点
```

之后 linker 自动排列：

```text
.overlay_a LMA
.overlay_b LMA
.overlay_c LMA
```

为连续地址。

GNU ld 文档明确说明，OVERLAY 内各 section 的 load address 会从 Overlay 的整体 load address 开始连续排列。([Sourceware][1])

---

# 三十一、这和普通 `AT()` 的关系

普通：

```ld
.data :
{
    ...
} > RAM AT > ROM
```

意思：

```text
VMA
    RAM

LMA
    ROM
```

Overlay：

```ld
OVERLAY 0x00602000 : AT(0x00401000)
```

则：

```text
Overlay VMA
    0x00602000

Overlay LMA
    0x00401000
```

内部：

```text
A
    VMA = 0x00602000
    LMA = 0x00401000

B
    VMA = 0x00602000
    LMA = 0x00401000 + size(A)

C
    VMA = 0x00602000
    LMA = 0x00401000 + size(A) + size(B)
```

---

# 三十二、这张图一定要理解

```text
                  FLASH

0x00401000 ─────── A ───────
                   │
                   │ size A
                   ▼
                ─── B ───────
                   │
                   │ size B
                   ▼
                ─── C ───────


                  RAM

0x00602000 ─────── A ───────
                   ▲
                   │
             copy A here

之后：

0x00602000 ─────── B ───────
                   ▲
                   │
             copy B here

之后：

0x00602000 ─────── C ───────
                   ▲
                   │
             copy C here
```

所以：

```text
Flash
    保存全部

RAM
    一次只保存一个
```

---

# 三十三、实验 16-8：写一个最小 Overlay Manager

现在我们终于可以把 linker symbol 真正用起来。

创建：

```text
overlay_manager.c
```

```c
#include <stddef.h>

extern char __load_start_overlay_a[];
extern char __load_stop_overlay_a[];

extern char __load_start_overlay_b[];
extern char __load_stop_overlay_b[];

extern char __load_start_overlay_c[];
extern char __load_stop_overlay_c[];

#define OVERLAY_RAM ((char *)0x00602000)

static void copy_overlay(
    char *src,
    char *dst,
    size_t size)
{
    while (size--)
        *dst++ = *src++;
}

void load_overlay_a(void)
{
    copy_overlay(
        __load_start_overlay_a,
        OVERLAY_RAM,
        __load_stop_overlay_a -
        __load_start_overlay_a
    );
}

void load_overlay_b(void)
{
    copy_overlay(
        __load_start_overlay_b,
        OVERLAY_RAM,
        __load_stop_overlay_b -
        __load_start_overlay_b
    );
}

void load_overlay_c(void)
{
    copy_overlay(
        __load_start_overlay_c,
        OVERLAY_RAM,
        __load_stop_overlay_c -
        __load_start_overlay_c
    );
}
```

这段代码的核心：

```text
source
=
__load_start_overlay_X

size
=
__load_stop_overlay_X
-
__load_start_overlay_X

destination
=
OVERLAY_RAM
```

---

# 三十四、这就是 linker + runtime 的真正协作

```text
linker.ld
   │
   ├── 决定 VMA
   ├── 决定 LMA
   ├── 决定 size
   │
   └── 自动生成
        __load_start_*
        __load_stop_*
                 │
                 ▼
          overlay_manager
                 │
                 ▼
              memcpy
                 │
                 ▼
             Overlay RAM
```

所以 linker 并不是：

> “把程序复制到 RAM。”

而是：

> **告诉运行时代码应该从哪里复制到哪里，以及有多大。**

真正的搬运仍然由：

```text
startup code
overlay manager
bootloader
```

执行。

---

# 三十五、实验 16-9：Overlay + `NOCROSSREFS`

最终推荐：

```ld
OVERLAY NOCROSSREFS 0x00602000 : AT(0x00401000)
{
    .overlay_a
    {
        *(.overlay_a)
    }

    .overlay_b
    {
        *(.overlay_b)
    }

    .overlay_c
    {
        *(.overlay_c)
    }
} > RAM :data
```

这时候架构就很清晰：

```text
overlay_a
    ↕
    X
overlay_b
    ↕
    X
overlay_c
```

三个模块互不直接依赖。

它们通过：

```text
main
overlay manager
```

控制切换。

---

# 三十六、一个现实工程中的调用方式

例如：

```text
main
 │
 ├── load_overlay_a()
 │
 ├── call overlay_a()
 │
 ├── load_overlay_b()
 │
 ├── call overlay_b()
 │
 └── load_overlay_c()
       │
       └── call overlay_c()
```

运行时：

```text
        RAM Overlay Area

第一次：
┌──────────────┐
│ overlay_a    │
└──────────────┘

第二次：
┌──────────────┐
│ overlay_b    │
└──────────────┘

第三次：
┌──────────────┐
│ overlay_c    │
└──────────────┘
```

---

# 三十七、但这里有一个非常重要的工程陷阱

假设：

```c
int global_state;
```

然后 Overlay A：

```c
global_state++;
```

Overlay B：

```c
global_state++;
```

那么：

```text
global_state
```

不能放 Overlay 区。

应该放：

```text
.bss
.data
```

因为：

```text
Overlay A
Overlay B
```

会不断被覆盖。

所以：

```text
Overlay
    ↓
代码 / 临时数据

普通 RAM
    ↓
持久状态
```

这是实际设计 Overlay 时非常重要的原则。

---

# 三十八、再一个重要问题：Stack

Overlay RAM：

```text
0x00602000
```

不要与：

```text
stack
```

重叠。

例如：

```text
RAM
0x00600000
│
├── .data
├── .bss
│
├── Overlay
│
└── Stack
0x0060FFFF
```

否则：

```text
overlay copy
```

可能覆盖：

```text
stack frame
```

最终表现为非常诡异的：

```text
随机崩溃
返回地址损坏
```

---

# 三十九、Map 文件此时特别重要

最终工程必须检查：

```text
.data
.bss
Overlay
stack
```

的范围。

例如：

```text
RAM
│
├── .data
│
├── .bss
│
├── overlay area
│
└── stack
```

然后计算：

```text
RAM end
=
ORIGIN(RAM)
+
LENGTH(RAM)
```

检查：

```text
Overlay end < Stack start
```

否则：

```text
ld
```

虽然可能成功，但运行时布局已经危险。

---

# 四十、`OVERLAY` 与 `--gc-sections`

这一点也非常值得实验。

如果：

```bash
gcc -ffunction-sections -fdata-sections ...
```

那么：

```text
overlay_a.c
```

可能产生独立 Input Section：

```text
.overlay_a
```

linker 再处理：

```text
OVERLAY
```

所以完整流程仍然是：

```text
C
 ↓
Input Section
 ↓
OVERLAY
 ↓
Output Section
 ↓
VMA/LMA
 ↓
ELF
```

而：

```text
--gc-sections
```

仍然可能影响哪些 input section 最终被保留。

因此：

```text
OVERLAY
```

不是绕过普通 linker section 机制的“特殊世界”。

它仍然建立在：

```text
Input Section
→ Output Section
```

这条基础机制上。

---

# 四十一、实验 16-10：完整观察命令

现在形成一套固定流程。

## ① 查看 Input Section

```bash
objdump -h overlay_a.o
objdump -h overlay_b.o
objdump -h overlay_c.o
```

---

## ② 查看 Symbol

```bash
nm overlay_a.o
nm overlay_b.o
nm overlay_c.o
```

---

## ③ 链接

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    overlay_a.o \
    overlay_b.o \
    overlay_c.o \
    -o overlay.elf \
    -Map=overlay.map
```

---

## ④ Section

```bash
readelf -S overlay.elf
```

---

## ⑤ Segment

```bash
readelf -l overlay.elf
```

---

## ⑥ VMA/LMA

```bash
objdump -h overlay.elf
```

---

## ⑦ Symbol

```bash
nm -n overlay.elf
```

---

## ⑧ Overlay 自动符号

```bash
nm -n overlay.elf | grep __load
```

---

## ⑨ 反汇编

```bash
objdump -d overlay.elf
```

---

## ⑩ Map

```bash
less overlay.map
```

---

# 四十二、最关键的验证矩阵

最终你应该自己整理出：

| 对象           | VMA | LMA |   Size |
| ------------ | --: | --: | -----: |
| `.overlay_a` |  相同 |   A | A size |
| `.overlay_b` |  相同 |   B | B size |
| `.overlay_c` |  相同 |   C | C size |

然后验证：

```text
VMA_A == VMA_B == VMA_C
```

以及：

```text
LMA_A < LMA_B < LMA_C
```

再验证：

```text
LMA_B
=
LMA_A + SIZE_A
```

以及：

```text
LMA_C
=
LMA_B + SIZE_B
```

最后：

```text
Overlay RAM size
=
max(
    SIZE_A,
    SIZE_B,
    SIZE_C
)
```

这五个公式如果你能自己从 Map 和 `objdump -h` 验证出来，这一节就真正掌握了。

---

# 四十三、这一节把之前的知识再次全部串起来

现在 GNU `ld` 的模型变成：

```text
                       GNU ld
                          │
             ┌────────────┼─────────────┐
             ▼            ▼             ▼
          Section      Symbol       Relocation
             │            │
             ▼            ▼
         OVERLAY      Resolution
             │
       ┌─────┼─────┐
       ▼     ▼     ▼
       A     B     C
       │     │     │
       └─────┼─────┘
             │
        same VMA
             │
       different LMA
             │
             ▼
          ELF
             │
       ┌─────┼─────┐
       ▼     ▼     ▼
   readelf  objdump  nm
       │      │      │
       └──────┼──────┘
              ▼
             Map
              │
              ▼
       Runtime Overlay Manager
              │
              ▼
          ROM → RAM
```

---

# 四十四、到这里，你已经跨过一个非常重要的门槛

前面的：

```text
实验 01～10
```

主要是在理解：

```text
Section
Symbol
Relocation
Archive
GC
KEEP
```

然后：

```text
实验 11～14
```

进入：

```text
Strong
Weak
COMMON
VMA
LMA
AT()
LOADADDR()
SIZEOF()
.data 搬运
.bss 清零
```

然后：

```text
实验 15
```

进入：

```text
PHDRS
Segment
R E
RW
FileSiz
MemSiz
```

而今天：

```text
实验 16
```

进一步进入：

```text
OVERLAY
same VMA
different LMA
runtime mapping
```

于是整个知识体系已经从：

```text
“如何链接几个 .o”
```

升级成：

# “如何设计一个完整的固件内存布局”。

---

# 四十五、下一节：实验 17 —— `ASSERT()`，让 linker 自己做“内存安全检查”

下一步非常适合进入：

```ld
ASSERT()
```

我们会故意设计：

```text
ROM
├── .text
├── .rodata
├── .data image
└── Overlay

RAM
├── .data
├── .bss
├── heap
├── Overlay
└── stack
```

然后让 linker 自动检查：

```ld
ASSERT(
    SIZEOF(.text) <= LENGTH(ROM),
    "ROM overflow"
);
```

以及：

```ld
ASSERT(
    _ebss <= _stack_start,
    "RAM overflow"
);
```

进一步使用：

```ld
ORIGIN()
LENGTH()
ADDR()
LOADADDR()
SIZEOF()
MAX()
MIN()
ABSOLUTE()
```

构造真正的：

```text
ROM overflow detection
RAM overflow detection
stack collision detection
overlay collision detection
```

最终实现：

```text
编译
  ↓
ld
  ↓
自动检查 Memory Layout
  ↓
错误立即失败
```

而不是：

```text
固件烧进 MCU
  ↓
运行
  ↓
随机崩溃
```

这会是从“**会写 linker script**”进入“**会设计可靠 linker script**”的下一步。

[1]: https://sourceware.org/binutils/docs-2.39/ld.pdf?utm_source=chatgpt.com "The GNU linker"
[2]: https://sourceware.org/gdb/current/onlinedocs/gdb?utm_source=chatgpt.com "Debugging with GDB"

