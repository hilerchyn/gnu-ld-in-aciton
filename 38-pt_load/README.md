# GNU ld 实战课程 · 实验 38

上一次已经把：

- `PHDRS`
- `FILEHDR`
- `PHDRS` 关键字
- `SIZEOF_HEADERS`
- ELF Header
- Program Header Table
- `PT_LOAD`

串起来了。

这一节继续向下走，进入 **ELF Segment 最核心的一组概念：VMA / LMA / `AT()` / `p_filesz` / `p_memsz`**。

---

# 实验 38：`PT_LOAD` + `AT()` + VMA/LMA + `p_filesz/p_memsz`

## 一、这一节解决什么问题？

先看一个典型嵌入式程序：

```text
                FLASH
        0x00400000
             │
             ├── .text
             │
             ├── .rodata
             │
             └── .data 初始化镜像
                    │
                    │ 启动时复制
                    ▼
                SRAM
        0x00600000
             │
             ├── .data
             │
             └── .bss
```

为什么 `.data` 会出现两个地址？

```text
.data
 ├── VMA = 运行时地址
 └── LMA = 镜像存储地址
```

例如：

```text
.data VMA = 0x00600000
.data LMA = 0x00401000
```

程序启动时：

```c
memcpy(
    (void *)0x00600000,
    (void *)0x00401000,
    data_size
);
```

这就是：

> **`.data` 存在 FLASH 中，但运行时位于 RAM。**

而这正是：

```ld
.data > RAM AT > FLASH
```

真正解决的问题。

---

# 二、先建立四个地址/大小概念

这是本节最重要的模型。

## 1. VMA

VMA：

```text
Virtual Memory Address
```

可以理解成：

> Section 运行时应该位于哪个地址。

例如：

```text
.data VMA = 0x00600000
```

---

## 2. LMA

LMA：

```text
Load Memory Address
```

可以理解成：

> Section 的初始化内容在镜像中存放在哪里。

例如：

```text
.data LMA = 0x00401000
```

---

## 3. `p_filesz`

Program Header 中：

```text
p_filesz
```

表示：

> 该 Segment 在 ELF 文件中实际占用多少字节。

---

## 4. `p_memsz`

表示：

> 该 Segment 加载到内存后需要多少字节。

因此可能出现：

```text
p_filesz < p_memsz
```

最典型就是：

```text
.bss
```

因为 `.bss`：

```text
ELF 文件中：
不需要保存一大片 0

运行时：
必须存在这些内存
```

所以：

```text
文件：
████████ .data

内存：
████████ .data
░░░░░░░░ .bss
```

---

# 三、实验目录

建立：

```text
38-vma-lma/
├── start.S
├── main.c
└── linker38.ld
```

---

# 四、准备源码

## `start.S`

```asm
.global _start

.section .text.start

_start:
    call main

1:
    jmp 1b
```

---

## `main.c`

这里故意准备三类数据：

```c
int initialized = 0x12345678;

int uninitialized;

const char message[] = "GNU ld VMA/LMA";

int main(void)
{
    initialized++;

    uninitialized = initialized;

    return message[0];
}
```

于是会产生：

```text
initialized
    ↓
.data

uninitialized
    ↓
.bss

message
    ↓
.rodata
```

这是非常适合观察 VMA/LMA 的最小案例。

---

# 五、先编译成目标文件

```bash
gcc \
    -ffreestanding \
    -fno-pie \
    -fno-asynchronous-unwind-tables \
    -c start.S main.c
```

检查：

```bash
readelf -SW main.o
```

应该能看到类似：

```text
.text
.data
.bss
.rodata
.comment
```

重点：

```text
.data
.bss
.rodata
```

---

# 六、先不写复杂 linker script

先看看目标文件中的 Section：

```bash
objdump -h main.o
```

重点观察：

```text
Idx
Name
Size
VMA
LMA
File off
Algn
```

此时 `.data` 和 `.bss` 还是：

```text
VMA = 0
LMA = 0
```

因为：

> **目标文件 `.o` 还没有经过最终地址布局。**

最终地址是 `ld` 决定的。

---

# 七、实验 38-1：VMA 与 LMA 分离

创建：

```text
linker38.ld
```

```ld
ENTRY(_start)

MEMORY
{
    FLASH (rx)  : ORIGIN = 0x00400000, LENGTH = 64K
    SRAM  (rwx) : ORIGIN = 0x00600000, LENGTH = 64K
}

PHDRS
{
    text PT_LOAD
         FILEHDR
         PHDRS
         FLAGS(5);

    ro PT_LOAD
       FLAGS(4);

    data PT_LOAD
         FLAGS(6);
}

SECTIONS
{
    . = ORIGIN(FLASH) + SIZEOF_HEADERS;

    .text :
    {
        . = ALIGN(16);

        __text_start = .;

        *(.text.start)
        *(.text*)

        __text_end = .;
    } > FLASH :text

    .rodata :
    {
        . = ALIGN(16);

        __rodata_start = .;

        *(.rodata*)

        __rodata_end = .;
    } > FLASH :ro

    .data :
    {
        . = ALIGN(16);

        __data_start = .;

        *(.data*)

        __data_end = .;
    } > SRAM AT > FLASH :data

    .bss (NOLOAD) :
    {
        . = ALIGN(16);

        __bss_start = .;

        *(.bss*)
        *(COMMON)

        __bss_end = .;
    } > SRAM :data
}
```

注意这一行：

```ld
.data > SRAM AT > FLASH :data
```

它是整个实验的核心。

---

# 八、链接

执行：

```bash
ld \
    -T linker38.ld \
    start.o \
    main.o \
    -o vma-lma.elf \
    -Map=vma-lma.map
```

---

# 九、第一组验证：Section 地址

执行：

```bash
readelf -SW vma-lma.elf
```

或者：

```bash
objdump -h vma-lma.elf
```

重点找到：

```text
.text
.rodata
.data
.bss
```

你应该看到类似：

```text
.text
VMA = 0x00400...

.rodata
VMA = 0x00400...

.data
VMA = 0x00600...

.bss
VMA = 0x00600...
```

这里已经出现非常重要的布局：

```text
FLASH
0x00400000
│
├── .text
└── .rodata

SRAM
0x00600000
│
├── .data
└── .bss
```

---

# 十、但是 `.data` 的初始化数据到底在哪里？

这时候执行：

```bash
objdump -h vma-lma.elf
```

注意：

```text
VMA
LMA
```

两个字段。

`.data` 可能出现：

```text
VMA = 0x00600000
LMA = 0x00400xxx
```

这就是：

```text
.data
       ┌──────────────┐
       │              │
LMA ───┤ FLASH 镜像   │
       │              │
       └──────────────┘
               │
               │ 启动复制
               ▼
       ┌──────────────┐
VMA ───┤ SRAM 运行区  │
       │              │
       └──────────────┘
```

---

# 十一、`AT > FLASH` 到底干了什么？

这一句：

```ld
.data > SRAM AT > FLASH
```

可以拆成：

```text
> SRAM
    ↓
VMA 放 SRAM

AT > FLASH
    ↓
LMA 放 FLASH
```

所以：

```text
.data > SRAM AT > FLASH
```

不是：

> 把 `.data` 放到 FLASH。

而是：

> `.data` **运行时地址放 SRAM，初始化镜像地址放 FLASH**。

这是 linker script 中非常关键的区别。

---

# 十二、实验 38-2：用 `ADDR()` 和 `LOADADDR()` 验证

增加：

```ld
PROVIDE(__data_vma = ADDR(.data));
PROVIDE(__data_lma = LOADADDR(.data));
PROVIDE(__data_size = SIZEOF(.data));
```

完整相关部分：

```ld
.data :
{
    . = ALIGN(16);

    __data_start = .;

    *(.data*)

    __data_end = .;
} > SRAM AT > FLASH :data

.bss (NOLOAD) :
{
    . = ALIGN(16);

    __bss_start = .;

    *(.bss*)
    *(COMMON)

    __bss_end = .;
} > SRAM :data

PROVIDE(__data_vma  = ADDR(.data));
PROVIDE(__data_lma  = LOADADDR(.data));
PROVIDE(__data_size = SIZEOF(.data));
```

重新链接：

```bash
ld \
    -T linker38.ld \
    start.o \
    main.o \
    -o vma-lma.elf \
    -Map=vma-lma.map
```

---

# 十三、用 `nm` 验证

执行：

```bash
nm -n vma-lma.elf
```

或者：

```bash
nm -n vma-lma.elf | grep '__data'
```

应该看到：

```text
__data_vma
__data_lma
__data_size
```

例如：

```text
0000000000400xxx A __data_lma
0000000000600000 A __data_vma
0000000000000004 A __data_size
```

其中最关键的是：

```text
__data_vma
```

和：

```text
__data_lma
```

不同。

---

# 十四、为什么 `ADDR(.data)` 和 `LOADADDR(.data)` 不一样？

因为：

```ld
ADDR(.data)
```

返回：

> `.data` 的 VMA。

而：

```ld
LOADADDR(.data)
```

返回：

> `.data` 的 LMA。

因此：

```text
ADDR(.data)
       ↓
0x00600000

LOADADDR(.data)
       ↓
0x0040xxxx
```

这两个地址恰恰就是启动代码需要的：

```c
src = LOADADDR(.data);
dst = ADDR(.data);
size = SIZEOF(.data);
```

---

# 十五、这就可以写出真实的启动代码

在很多裸机程序中，启动代码会做：

```c
extern char __data_lma[];
extern char __data_start[];
extern char __data_end[];

void init_data(void)
{
    char *src = __data_lma;
    char *dst = __data_start;

    while (dst < __data_end)
        *dst++ = *src++;
}
```

逻辑：

```text
FLASH
__data_lma
    │
    │ copy
    ▼
SRAM
__data_start
    │
    └── __data_end
```

---

# 十六、实验 38-3：观察 Program Header

现在执行：

```bash
readelf -lW vma-lma.elf
```

重点观察：

```text
LOAD
```

尤其：

```text
Offset
VirtAddr
PhysAddr
FileSiz
MemSiz
Flg
Align
```

然后你会看到一个非常有意思的现象：

```text
.data
```

虽然：

```text
VMA 在 SRAM
```

但：

```text
文件中的初始化内容
```

仍然位于 ELF 文件中。

因此：

```text
.data
```

不能简单理解为：

```text
“它属于 RAM，所以 ELF 文件里没有它。”
```

正确理解是：

```text
.data
├── 运行地址 → SRAM
└── 初始化镜像 → FLASH
```

---

# 十七、真正理解 `p_filesz`

假设某个 `PT_LOAD`：

```text
p_filesz = 0x20
```

表示：

```text
ELF 文件中
这个 Segment 有 0x20 字节内容
```

例如：

```text
.text
.rodata
.data 初始化镜像
```

都可能属于它。

---

# 十八、真正理解 `p_memsz`

如果：

```text
p_memsz = 0x40
```

那么：

```text
运行时需要 0x40 字节
```

于是：

```text
p_filesz = 0x20
p_memsz  = 0x40
```

意味着：

```text
文件中：
████████████████████████
<--- 0x20 --->

内存中：
████████████████████████░░░░░░░░░░░░░░░░
<------------- 0x40 -------------------->
```

后面的：

```text
0x20
```

字节：

> 不需要从文件读取。

Loader 应该把它当作：

```text
zero-filled memory
```

这就是 `.bss` 的核心机制。

---

# 十九、实验 38-4：专门观察 `.bss`

执行：

```bash
readelf -SW vma-lma.elf
```

找到：

```text
.bss
```

注意：

```text
Type = NOBITS
```

这是关键。

---

# 二十、`SHT_NOBITS` 是什么？

`.bss` 常见：

```text
Type: NOBITS
```

意思是：

> Section 在 ELF 文件中有逻辑大小，但不需要实际保存这些字节。

例如：

```text
.bss size = 0x1000
```

并不意味着：

```text
ELF 文件增加 4096 个 0
```

而是：

```text
ELF：
只记录：

.bss
size = 4096

加载：
分配 4096 字节
然后清零
```

因此：

```text
文件大小
≠
内存映像大小
```

这就是：

```text
p_filesz
p_memsz
```

产生差异的根本原因。

---

# 二十一、用 `readelf -lW` 验证 `.bss`

执行：

```bash
readelf -lW vma-lma.elf
```

然后查看：

```text
Section to Segment mapping
```

找到：

```text
.bss
```

它通常属于：

```text
RW PT_LOAD
```

然后观察这个 Segment：

```text
FileSiz
MemSiz
```

如果 `.bss` 在 Segment 尾部，那么：

```text
MemSiz > FileSiz
```

其差值就是需要在内存中补出来的空间。

---

# 二十二、非常重要的公式

对于一个典型包含 `.bss` 的 `PT_LOAD`：

```text
p_memsz
=
p_filesz
+
.bss 所需额外内存
```

更准确地说：

```text
p_memsz - p_filesz
```

表示：

> Segment 在运行时比 ELF 文件中的实际内容多出来的空间。

这部分通常就是：

```text
NOBITS / zero-fill
```

---

# 二十三、实验 38-5：用 `objdump -p` 从另一个角度观察

执行：

```bash
objdump -p vma-lma.elf
```

找到：

```text
Program Header:
```

观察：

```text
LOAD off
vaddr
paddr
align
filesz
memsz
flags
```

这里特别值得对比：

```text
readelf -lW
```

和：

```text
objdump -p
```

它们描述的是同一个 Program Header。

---

# 二十四、建立 `Section → Segment` 映射

现在把所有结果放在一起：

```text
Section               Segment
──────────────────────────────────

.text       ────────→ PT_LOAD RX

.rodata     ────────→ PT_LOAD R

.data       ────────→ PT_LOAD RW
                         │
                         ├── 文件中有初始化数据
                         │
                         └── VMA 在 SRAM

.bss        ────────→ PT_LOAD RW
                         │
                         └── NOBITS
```

而：

```text
.data
```

还有：

```text
LMA = FLASH
VMA = SRAM
```

---

# 二十五、Map 文件分析

现在：

```bash
less vma-lma.map
```

搜索：

```text
.data
```

你会看到类似：

```text
.data           0x0000000000600000
                0x0000000000000004
                ...
```

这里重点是：

```text
0x00600000
```

它是 `.data` 的 VMA。

---

# 二十六、Map 文件怎么看 LMA？

Map 文件中还需要找：

```text
load address
```

可以直接：

```bash
grep -n "load address" vma-lma.map
```

或者：

```bash
grep -A10 -B3 "\.data" vma-lma.map
```

你应该能够看到：

```text
.data
    ...
    load address 0x0040....
```

于是：

```text
Map
```

把：

```text
VMA
LMA
```

都暴露出来。

---

# 二十七、现在把四种工具放到一起

| 工具 | 最适合观察 |
|---|---|
| `readelf -h` | ELF Header |
| `readelf -SW` | Section |
| `readelf -lW` | Segment |
| `objdump -h` | Section VMA/LMA |
| `objdump -p` | Program Header |
| `nm -n` | Symbol 地址 |
| `.map` | ld 的完整布局过程 |

所以以后分析 linker 问题，不要只看一个工具。

建议固定使用：

```bash
readelf -h
readelf -SW
readelf -lW
objdump -h
objdump -p
nm -n
```

再配合：

```text
xxx.map
```

---

# 二十八、实验 38-6：计算 `.data` 初始化镜像

加入：

```ld
PROVIDE(__data_load = LOADADDR(.data));
PROVIDE(__data_start = ADDR(.data));
PROVIDE(__data_end = ADDR(.data) + SIZEOF(.data));
PROVIDE(__data_size = SIZEOF(.data));
```

然后：

```bash
nm -n vma-lma.elf | grep '__data'
```

得到：

```text
__data_load
__data_start
__data_end
__data_size
```

于是可以自己验证：

```text
__data_end - __data_start
=
__data_size
```

这就是一个非常重要的 linker script 自验证方法。

---

# 二十九、再加入 `.bss` 信息

```ld
PROVIDE(__bss_start = ADDR(.bss));
PROVIDE(__bss_end   = ADDR(.bss) + SIZEOF(.bss));
PROVIDE(__bss_size  = SIZEOF(.bss));
```

然后：

```bash
nm -n vma-lma.elf | grep -E '__data|__bss'
```

最终应该形成：

```text
FLASH
│
├── __text_start
├── __text_end
│
├── __rodata_start
├── __rodata_end
│
└── __data_load
        │
        │ copy
        ▼
SRAM
│
├── __data_start
├── __data_end
│
├── __bss_start
└── __bss_end
```

---

# 三十、实验 38-7：真正理解 `.data > SRAM AT > FLASH`

现在做三个 linker script 对比。

### 情况 A

```ld
.data > SRAM
```

表示：

```text
VMA = SRAM
LMA = 默认跟随 VMA
```

---

### 情况 B

```ld
.data > SRAM AT > FLASH
```

表示：

```text
VMA = SRAM
LMA = FLASH
```

---

### 情况 C

```ld
.data > FLASH
```

表示：

```text
VMA = FLASH
LMA = FLASH
```

所以可以记成：

```text
> REGION
      ↓
决定 VMA

AT > REGION
      ↓
决定 LMA
```

这是 linker script 最值得记住的规则之一。

---

# 三十一、一个很容易误解的地方

不要把：

```ld
AT > FLASH
```

理解成：

```text
“把 Section 放进 FLASH”
```

它真正表达的是：

```text
“Section 的加载地址在 FLASH”
```

而：

```ld
> SRAM
```

表达：

```text
“Section 的运行地址在 SRAM”
```

因此：

```ld
.data > SRAM AT > FLASH
```

完整翻译：

> `.data` 运行时位于 SRAM，但其初始化镜像存储于 FLASH。

---

# 三十二、实验 38-8：手动模拟启动代码

为了让概念彻底落地，可以写一个伪启动流程：

```c
extern unsigned char __data_load[];
extern unsigned char __data_start[];
extern unsigned char __data_end[];

extern unsigned char __bss_start[];
extern unsigned char __bss_end[];

static void init_memory(void)
{
    unsigned char *src = __data_load;
    unsigned char *dst = __data_start;

    while (dst < __data_end)
        *dst++ = *src++;

    dst = __bss_start;

    while (dst < __bss_end)
        *dst++ = 0;
}
```

整个启动过程：

```text
_start
  │
  ▼
init_memory()
  │
  ├── copy .data
  │       │
  │       └── FLASH → SRAM
  │
  └── zero .bss
          │
          └── SRAM = 0
  │
  ▼
main()
```

这就是大量裸机系统真正发生的事情。

---

# 三十三、实验 38-9：重点观察 `p_filesz != p_memsz`

现在：

```bash
readelf -lW vma-lma.elf
```

找到 RW Segment。

假设看到：

```text
LOAD
Offset   ...
VirtAddr 0x00600000
FileSiz  0x000010
MemSiz   0x000020
Flg      RW
```

那么：

```text
p_filesz = 0x10
p_memsz  = 0x20
```

意味着：

```text
ELF 文件：
████████████████
      0x10

运行时：
████████████████░░░░░░░░░░░░░░░░
          0x20
```

后面：

```text
0x10
```

字节并不来自 ELF 文件。

它们需要由 loader：

```text
zero-fill
```

---

# 三十四、这就是 `.bss` 的工程价值

假设：

```c
char huge_buffer[1024 * 1024];
```

放进 `.bss`。

如果错误地把它当普通 `.data`：

```text
ELF 文件可能增加约 1 MB
```

而使用 `.bss`：

```text
ELF 文件：
几乎不增加对应数据内容

运行时：
仍然获得 1 MB 内存
```

所以：

```text
.bss
```

本质上是一种：

> **“只描述内存需求、不保存实际零数据”的 Section。**

---

# 三十五、Map + readelf 的交叉验证方法

以后碰到：

```text
ld 链接结果不符合预期
```

建议固定做这套检查。

## 第一步

```bash
readelf -SW xxx.elf
```

问：

> Section 在哪里？

---

## 第二步

```bash
objdump -h xxx.elf
```

问：

> Section 的 VMA / LMA 是什么？

---

## 第三步

```bash
readelf -lW xxx.elf
```

问：

> Section 属于哪个 Segment？

---

## 第四步

```bash
objdump -p xxx.elf
```

问：

> Program Header 的原始参数是什么？

---

## 第五步

```bash
nm -n xxx.elf
```

问：

> Symbol 最终地址是什么？

---

## 第六步

```bash
less xxx.map
```

问：

> ld 为什么把它放到这里？

---

# 三十六、实验 38 最终 linker script

建议保存为：

```text
linker38-final.ld
```

```ld
ENTRY(_start)

MEMORY
{
    FLASH (rx)  : ORIGIN = 0x00400000, LENGTH = 64K
    SRAM  (rwx) : ORIGIN = 0x00600000, LENGTH = 64K
}

PHDRS
{
    text PT_LOAD
         FILEHDR
         PHDRS
         FLAGS(5);

    ro PT_LOAD
       FLAGS(4);

    data PT_LOAD
         FLAGS(6);
}

PROVIDE(__flash_start = ORIGIN(FLASH));
PROVIDE(__flash_end =
        ORIGIN(FLASH) + LENGTH(FLASH));

PROVIDE(__ram_start = ORIGIN(SRAM));
PROVIDE(__ram_end =
        ORIGIN(SRAM) + LENGTH(SRAM));

SECTIONS
{
    . = ORIGIN(FLASH) + SIZEOF_HEADERS;

    .text :
    {
        . = ALIGN(16);

        __text_start = .;

        *(.text.start)
        *(.text*)

        __text_end = .;
    } > FLASH :text

    .rodata :
    {
        . = ALIGN(16);

        __rodata_start = .;

        *(.rodata*)

        __rodata_end = .;
    } > FLASH :ro

    .data :
    {
        . = ALIGN(16);

        __data_start = .;

        *(.data*)

        __data_end = .;
    } > SRAM AT > FLASH :data

    .bss (NOLOAD) :
    {
        . = ALIGN(16);

        __bss_start = .;

        *(.bss*)
        *(COMMON)

        __bss_end = .;
    } > SRAM :data
}

PROVIDE(__data_load = LOADADDR(.data));
PROVIDE(__data_vma  = ADDR(.data));
PROVIDE(__data_size = SIZEOF(.data));

PROVIDE(__bss_vma   = ADDR(.bss));
PROVIDE(__bss_size  = SIZEOF(.bss));
```

---

# 三十七、实验 38 命令总表

```bash
# 1. 编译
gcc -ffreestanding -fno-pie \
    -fno-asynchronous-unwind-tables \
    -c start.S main.c

# 2. 链接
ld -T linker38-final.ld \
   start.o main.o \
   -o vma-lma.elf \
   -Map=vma-lma.map

# 3. ELF Header
readelf -h vma-lma.elf

# 4. Section
readelf -SW vma-lma.elf

# 5. Segment
readelf -lW vma-lma.elf

# 6. Section VMA/LMA
objdump -h vma-lma.elf

# 7. Program Header
objdump -p vma-lma.elf

# 8. Symbol
nm -n vma-lma.elf

# 9. Map
less vma-lma.map
```

---

# 三十八、实验 38 必须掌握的核心公式

### ① Section 运行地址

```text
VMA = ADDR(section)
```

---

### ② Section 加载地址

```text
LMA = LOADADDR(section)
```

---

### ③ `.data`

```text
.data > SRAM AT > FLASH
```

等价于：

```text
VMA → SRAM
LMA → FLASH
```

---

### ④ `.bss`

```text
.bss (NOLOAD)
```

意味着：

```text
不需要把实际数据写入 ELF 文件
```

---

### ⑤ Segment

```text
p_filesz
```

表示：

```text
ELF 文件中的实际数据量
```

而：

```text
p_memsz
```

表示：

```text
运行时内存需求
```

所以：

```text
p_memsz >= p_filesz
```

是非常常见的。

---

# 三十九、到这里，GNU ld 的模型又向前推进了一层

现在完整关系已经变成：

```text
                    linker script
                          │
          ┌───────────────┼────────────────┐
          │               │                │
       MEMORY          SECTIONS          PHDRS
          │               │                │
          │        ┌──────┴──────┐         │
          │        │             │         │
          │       VMA           LMA        │
          │        │             │         │
          │        └──────┬──────┘         │
          │               │                │
          └───────────────┼────────────────┘
                          ▼
                    ELF Section
                          │
                          ▼
                    PT_LOAD Segment
                          │
              ┌───────────┴───────────┐
              │                       │
          p_filesz                 p_memsz
              │                       │
         ELF 文件大小             内存大小
                                      │
                                  .bss / NOBITS
```

下一阶段就可以从这里继续进入 **实验 39：多 `PT_LOAD` 的 `FILEHDR/PHDRS/ALIGN/AT()` 联合控制与 Segment 边界**，然后进一步研究 **`ALIGN(CONSTANT (MAXPAGESIZE))`、`-z max-page-size`、`p_align`、Section 跨 Segment 时为什么会出现巨大的文件空洞**。这会直接解释你之前实验中遇到的 `LOAD segment`、地址对齐以及 ELF 文件布局异常问题。
