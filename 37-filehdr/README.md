好，继续往下推进。上次已经进入 **`PHDRS` / Segment** 阶段，并完成了“Section → Segment”的基本映射。

这一次不再重复 `PT_LOAD + FLAGS()`，直接进入下一层：

# GNU ld 实战课程 · 实验 37

# `FILEHDR` + `PHDRS` + `SIZEOF_HEADERS`：亲手控制 ELF 文件头与 Program Header

这一节非常关键。

到实验 36，我们已经能够做到：

```text
.text   ──────→ PT_LOAD R-X
.rodata ──────→ PT_LOAD R--
.data   ──────→ PT_LOAD RW-
.bss    ──────→ PT_LOAD RW-
```

现在进一步回答：

> **ELF Header 和 Program Header Table 到底放在哪里？**
>
> **为什么有时候第一个 PT_LOAD 从文件 offset 0 开始？**
>
> **`SIZEOF_HEADERS` 到底是什么？**
>
> **`FILEHDR` 和 `PHDRS` 到底改变了什么？**

---

# 一、先把 ELF 文件重新画一遍

一个典型 ELF 文件可以抽象成：

```text
文件 Offset
0x00000000
        │
        ▼
┌──────────────────────────────┐
│ ELF Header                   │
│                              │
│ e_entry                      │
│ e_phoff                      │
│ e_phnum                      │
│ e_shoff                      │
│ ...                          │
├──────────────────────────────┤
│ Program Header Table         │
│                              │
│ PHDR #0                      │
│ PHDR #1                      │
│ PHDR #2                      │
│ ...                          │
├──────────────────────────────┤
│ .text                        │
├──────────────────────────────┤
│ .rodata                      │
├──────────────────────────────┤
│ .data                        │
├──────────────────────────────┤
│ Section Header Table         │
└──────────────────────────────┘
```

这里有三个概念一定不能混：

```text
ELF Header
Program Header Table
Section Header Table
```

它们分别对应：

```text
ELF Header
    ↓
描述整个 ELF 文件

Program Header
    ↓
描述 Loader 如何加载

Section Header
    ↓
描述链接后的 Section
```

---

# 二、实验 37-1：先看看默认 ELF 的 Header

继续使用上一节工程。

目录：

```text
37-elf-headers/
├── start.S
├── main.c
└── linker.ld
```

源码仍然使用：

### `start.S`

```asm
.global _start

.section .text.start
_start:
    call main

1:
    jmp 1b
```

### `main.c`

```c
volatile int counter = 42;

const char message[] = "GNU ld";

int main(void)
{
    counter++;
    return counter;
}
```

---

# 三、编译

```bash
gcc -ffreestanding -c start.S main.c
```

得到：

```text
start.o
main.o
```

检查：

```bash
readelf -h start.o
readelf -h main.o
```

不过我们真正关心的是最终 ELF。

---

# 四、先用一个简单 linker script

创建：

```text
linker37-default.ld
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
    text PT_LOAD FLAGS(5);
    ro   PT_LOAD FLAGS(4);
    data PT_LOAD FLAGS(6);
}

SECTIONS
{
    .text :
    {
        . = ALIGN(16);

        *(.text.start)
        *(.text*)
    } > FLASH :text

    .rodata :
    {
        . = ALIGN(16);

        *(.rodata*)
    } > FLASH :ro

    .data :
    {
        . = ALIGN(16);

        *(.data*)
    } > SRAM AT > FLASH :data

    .bss (NOLOAD) :
    {
        . = ALIGN(16);

        *(.bss*)
        *(COMMON)
    } > SRAM :data
}
```

注意这里继续使用之前已经纠正过的正确形式：

```ld
.text :
{
    . = ALIGN(16);
```

不要写成：

```ld
.text ALIGN(16) :
```

---

# 五、链接

```bash
ld \
    -T linker37-default.ld \
    start.o \
    main.o \
    -o elf37-default.elf \
    -Map=elf37-default.map
```

---

# 六、第一次观察 ELF Header

执行：

```bash
readelf -h elf37-default.elf
```

重点观察：

```text
ELF Header:
  Type:
  Entry point address:
  Start of program headers:
  Start of section headers:
  Size of program header:
  Number of program headers:
  Size of section headers:
  Number of section headers:
  Section header string table index:
```

这些字段非常重要。

---

# 七、重点理解 `e_phoff`

例如：

```text
Start of program headers: 64 (bytes into file)
```

这个值就是：

```text
e_phoff
```

也就是：

```text
ELF Header
     │
     │ 64 bytes
     ▼
Program Header Table
```

在 64 位 ELF 中，ELF Header 通常是 64 字节，因此很容易看到：

```text
e_phoff = 64
```

于是文件开头大概是：

```text
offset 0
   │
   ├── ELF Header
   │      64 bytes
   │
offset 0x40
   │
   └── Program Header Table
```

---

# 八、`e_phnum` 是什么？

执行：

```bash
readelf -h elf37-default.elf
```

你可能看到：

```text
Number of program headers: 3
```

因为我们定义了：

```ld
PHDRS
{
    text PT_LOAD FLAGS(5);
    ro   PT_LOAD FLAGS(4);
    data PT_LOAD FLAGS(6);
}
```

所以：

```text
e_phnum = 3
```

对应：

```text
PHDR #0 → text
PHDR #1 → ro
PHDR #2 → data
```

---

# 九、计算 Program Header Table 的大小

继续观察：

```text
Size of program headers: 56 (bytes)
Number of program headers: 3
```

那么：

```text
Program Header Table size
=
56 × 3
=
168 bytes
```

因此：

```text
ELF Header
64 bytes

Program Header Table
168 bytes
```

总共：

```text
64 + 168 = 232 bytes
```

十六进制：

```text
0x40 + 0xa8 = 0xe8
```

这就引出本实验最重要的 linker script 内建函数：

# `SIZEOF_HEADERS`

---

# 十、`SIZEOF_HEADERS` 是什么？

GNU ld 提供：

```ld
SIZEOF_HEADERS
```

它表示：

> ELF 文件头以及 Program Header Table 所占的总大小。

也就是：

```text
ELF Header
+
Program Header Table
```

可以理解成：

```text
SIZEOF_HEADERS
        │
        ▼
┌──────────────────────┐
│ ELF Header           │
├──────────────────────┤
│ Program Header Table │
└──────────────────────┘
```

例如：

```text
ELF Header = 64
PHDR = 56
PHNUM = 3

SIZEOF_HEADERS
=
64 + 56 × 3
=
232
=
0xe8
```

---

# 十一、实验 37-2：第一次使用 `SIZEOF_HEADERS`

创建：

```text
linker37-sizeof-headers.ld
```

内容：

```ld
ENTRY(_start)

MEMORY
{
    FLASH (rx)  : ORIGIN = 0x00400000, LENGTH = 64K
    SRAM  (rwx) : ORIGIN = 0x00600000, LENGTH = 64K
}

PHDRS
{
    text PT_LOAD FLAGS(5);
    ro   PT_LOAD FLAGS(4);
    data PT_LOAD FLAGS(6);
}

SECTIONS
{
    . = ORIGIN(FLASH) + SIZEOF_HEADERS;

    .text :
    {
        . = ALIGN(16);

        *(.text.start)
        *(.text*)
    } > FLASH :text

    .rodata :
    {
        . = ALIGN(16);

        *(.rodata*)
    } > FLASH :ro

    .data :
    {
        . = ALIGN(16);

        *(.data*)
    } > SRAM AT > FLASH :data

    .bss (NOLOAD) :
    {
        . = ALIGN(16);

        *(.bss*)
        *(COMMON)
    } > SRAM :data
}
```

这里出现：

```ld
. = ORIGIN(FLASH) + SIZEOF_HEADERS;
```

---

# 十二、这条语句到底在做什么？

假设：

```text
ORIGIN(FLASH)
=
0x00400000
```

而：

```text
SIZEOF_HEADERS
=
0xe8
```

那么：

```text
.
=
0x00400000 + 0xe8
```

即：

```text
.
=
0x004000e8
```

因此：

```text
.text
```

会从：

```text
0x004000e8
```

附近开始布局。

---

# 十三、但是这里马上会遇到一个重要问题

执行：

```bash
ld \
    -T linker37-sizeof-headers.ld \
    start.o \
    main.o \
    -o elf37-sizeof.elf \
    -Map=elf37-sizeof.map
```

然后：

```bash
readelf -lW elf37-sizeof.elf
```

观察：

```text
Offset
VirtAddr
PhysAddr
FileSiz
MemSiz
Flg
Align
```

你会发现：

> **“Section VMA 从哪里开始”与“Segment 文件 Offset 从哪里开始”是两个不同问题。**

这正是实验 37 的重点。

---

# 十四、`FILEHDR`：让 Segment 包含 ELF Header

现在修改：

```ld
PHDRS
{
    text PT_LOAD FILEHDR FLAGS(5);
    ro   PT_LOAD FLAGS(4);
    data PT_LOAD FLAGS(6);
}
```

这里：

```ld
FILEHDR
```

告诉 ld：

> `text` 这个 Segment 包含 ELF File Header。

也就是说：

```text
text PT_LOAD
│
├── ELF Header
│
├── Program Header Table
│
└── .text
```

但这里还缺一部分。

Program Header Table 呢？

---

# 十五、`PHDRS`：让 Segment 包含 Program Header Table

修改成：

```ld
PHDRS
{
    text PT_LOAD FILEHDR PHDRS FLAGS(5);
    ro   PT_LOAD FLAGS(4);
    data PT_LOAD FLAGS(6);
}
```

现在：

```text
text PT_LOAD
│
├── ELF Header
│
├── Program Header Table
│
└── .text
```

这才形成一个完整的第一个 LOAD Segment。

---

# 十六、实验 37-3：正式实验

创建：

```text
linker37-filehdr.ld
```

完整内容：

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

    ro   PT_LOAD
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

这里故意把 `PHDRS` 分行写，是为了以后阅读复杂 linker script 更清楚。

---

# 十七、链接

```bash
ld \
    -T linker37-filehdr.ld \
    start.o \
    main.o \
    -o elf37-filehdr.elf \
    -Map=elf37-filehdr.map
```

---

# 十八、第一组验证：ELF Header

```bash
readelf -h elf37-filehdr.elf
```

重点记录：

```text
Entry point address
Start of program headers
Size of program headers
Number of program headers
```

尤其：

```text
Start of program headers
```

通常会是：

```text
64
```

即：

```text
0x40
```

---

# 十九、第二组验证：Program Header

```bash
readelf -lW elf37-filehdr.elf
```

重点看第一个：

```text
LOAD
```

你希望看到：

```text
Offset    0x000000
VirtAddr  0x00400000
...
Flg       R E
```

也就是说：

```text
第一个 PT_LOAD
从 ELF 文件 offset 0 开始
```

---

# 二十、为什么 `FILEHDR` 很重要？

因为：

```ld
text PT_LOAD FILEHDR PHDRS FLAGS(5);
```

等价于告诉 linker：

```text
这个 Segment：

从 ELF 文件开头开始
        ↓
包含 ELF Header
        ↓
包含 Program Header Table
        ↓
继续包含 .text
```

形成：

```text
File Offset

0x000000
┌──────────────────────┐
│ ELF Header           │
├──────────────────────┤
│ Program Header Table │
├──────────────────────┤
│ padding              │
├──────────────────────┤
│ .text                │
└──────────────────────┘
```

这就是：

> **第一个 PT_LOAD 覆盖 ELF 文件头。**

---

# 二十一、`readelf -lW` 的字段现在全部串起来了

现在重新看：

```bash
readelf -lW elf37-filehdr.elf
```

例如：

```text
Type   Offset
LOAD   0x000000
```

表示：

```text
这个 Segment 从文件 offset 0 开始。
```

然后：

```text
VirtAddr
```

表示：

```text
Segment 加载后的虚拟地址。
```

然后：

```text
PhysAddr
```

表示：

```text
物理地址 / LMA 相关语义。
```

然后：

```text
FileSiz
```

表示：

```text
这个 Segment 在 ELF 文件中占多少字节。
```

然后：

```text
MemSiz
```

表示：

```text
运行时内存需要多少字节。
```

最后：

```text
Flg
```

表示：

```text
R / W / E
```

以及：

```text
Align
```

表示：

```text
Segment 对齐要求。
```

---

# 二十二、现在做一个非常关键的对照

执行：

```bash
readelf -lW elf37-filehdr.elf
```

同时：

```bash
readelf -SW elf37-filehdr.elf
```

然后建立：

```text
ELF Header
      │
      ▼
Program Header
      │
      ▼
PT_LOAD
      │
      ├──────── .text
      │
      └──────── ...
```

而：

```text
Section Header
      │
      ├── .text
      ├── .rodata
      ├── .data
      └── .bss
```

这两个表的关系终于完全清楚。

---

# 二十三、实验 37-4：`SIZEOF_HEADERS` 与实际文件 Offset

这是今天最值得做的实验。

执行：

```bash
readelf -h elf37-filehdr.elf
```

得到：

```text
Start of program headers
Size of program headers
Number of program headers
```

自己计算：

```text
HEADER_SIZE
=
ELF Header Size
+
Program Header Size × Number
```

然后与：

```bash
readelf -SW elf37-filehdr.elf
```

中的：

```text
Offset
```

比较。

再执行：

```bash
objdump -h elf37-filehdr.elf
```

观察：

```text
Idx
Name
Size
VMA
LMA
File off
Algn
```

你现在应该能够解释：

```text
File offset
VMA
LMA
```

三个数字为什么不一定相同。

---

# 二十四、Map 文件分析

现在：

```bash
less elf37-filehdr.map
```

重点搜索：

```text
.text
```

然后：

```bash
grep -A15 -B5 '\.text' elf37-filehdr.map
```

再：

```bash
grep -A15 -B5 '\.rodata' elf37-filehdr.map
```

再：

```bash
grep -A15 -B5 '\.data' elf37-filehdr.map
```

最后：

```bash
grep -A15 -B5 '\.bss' elf37-filehdr.map
```

---

# 二十五、Map 文件与 `readelf -l` 的关系

现在建立完整链条：

```text
linker.ld
    │
    ▼
ld
    │
    ├───────────────┐
    ▼               ▼
Section Layout   Segment Layout
    │               │
    ▼               ▼
Map              Program Header
    │               │
    ▼               ▼
VMA/LMA          VirtAddr/PhysAddr
    │               │
    └───────┬───────┘
            ▼
          ELF
```

因此：

> Map 文件不是 Program Header 的替代品。

它主要告诉你：

```text
ld 是如何安排 Section 和 Symbol 的。
```

而：

```bash
readelf -l
```

告诉你：

```text
最终 ELF 的 Segment 是什么样。
```

---

# 二十六、实验 37-5：直接用 `readelf` 验证 `FILEHDR`

这是一个非常好的验证技巧。

执行：

```bash
readelf -lW elf37-filehdr.elf
```

找到：

```text
Section to Segment mapping:
```

假设：

```text
Segment Sections...
  00     .text
  01     .rodata
  02     .data .bss
```

然后观察：

```text
Segment 00
Offset 0
```

如果：

```text
Offset == 0
```

再结合：

```ld
FILEHDR
PHDRS
```

就可以理解：

```text
PT_LOAD #0
```

覆盖文件开头：

```text
ELF Header
+
Program Header Table
+
.text
```

---

# 二十七、一个很容易踩的坑：不要把 `PHDRS` 和 `PHDRS` 搞混

这里名字真的有点“撞车”。

```ld
PHDRS
{
    text PT_LOAD FILEHDR PHDRS FLAGS(5);
}
```

这里出现两个：

```text
PHDRS
```

第一个：

```ld
PHDRS
{
    ...
}
```

是 linker script 的命令。

第二个：

```ld
text PT_LOAD FILEHDR PHDRS FLAGS(5);
```

是一个关键字。

它表示：

> 当前 Segment 包含 Program Header Table。

所以不要读成：

```text
PHDRS { PHDRS ... }
```

而应该读成：

```text
PHDRS command
    ↓
定义 Program Headers

PHDRS keyword
    ↓
让当前 Segment 覆盖 Program Header Table
```

---

# 二十八、实验 37-6：故意去掉 `FILEHDR`

现在做一个对照实验。

修改：

```ld
PHDRS
{
    text PT_LOAD
         PHDRS
         FLAGS(5);

    ro PT_LOAD FLAGS(4);

    data PT_LOAD FLAGS(6);
}
```

注意：

```text
FILEHDR
```

被删除。

重新链接：

```bash
ld \
    -T linker37-no-filehdr.ld \
    start.o \
    main.o \
    -o no-filehdr.elf \
    -Map=no-filehdr.map
```

然后：

```bash
readelf -lW no-filehdr.elf
```

对比：

```text
Offset
VirtAddr
```

你会发现 Segment 对文件开头的覆盖关系发生了变化。

这个实验非常重要，因为它让你看到：

```text
FILEHDR
```

不是装饰性关键字。

它直接影响：

```text
Segment → ELF Header
```

的归属关系。

---

# 二十九、实验 37-7：故意去掉 `PHDRS`

再进一步。

改成：

```ld
PHDRS
{
    text PT_LOAD
         FILEHDR
         FLAGS(5);

    ro PT_LOAD FLAGS(4);

    data PT_LOAD FLAGS(6);
}
```

也就是：

```text
FILEHDR
```

保留：

```text
PHDRS
```

删除。

然后：

```bash
ld \
    -T linker37-no-phdr-table.ld \
    start.o \
    main.o \
    -o no-phdr-table.elf \
    -Map=no-phdr-table.map
```

再：

```bash
readelf -lW no-phdr-table.elf
```

比较：

```text
FILEHDR
PHDRS
```

两种不同情况下 Segment 的范围。

最终你应该形成：

```text
FILEHDR
    ↓
ELF Header

PHDRS
    ↓
Program Header Table
```

这个对应关系一定要记牢。

---

# 三十、实验 37-8：`SIZEOF_HEADERS` 的真正用途

为什么 linker script 需要知道：

```ld
SIZEOF_HEADERS
```

最典型用途就是：

```text
让第一个 Section
紧跟在 ELF Header + Program Header Table 后面
```

例如：

```ld
SECTIONS
{
    . = SIZEOF_HEADERS;

    .text :
    {
        *(.text*)
    }
}
```

逻辑上：

```text
0
│
├── ELF Header
│
├── Program Header Table
│
│ ← SIZEOF_HEADERS
│
└── .text
```

不过在你当前这个：

```text
FLASH = 0x00400000
```

的实验中，通常还要考虑：

```text
VMA
LMA
MEMORY
```

因此我们写成：

```ld
. = ORIGIN(FLASH) + SIZEOF_HEADERS;
```

更容易理解为：

```text
FLASH 起点
+
ELF Headers 占用空间
```

---

# 三十一、这里埋着一个非常重要的 linker script 知识

`SIZEOF_HEADERS` 不应该被理解成：

```text
“ELF 文件头固定就是多少字节”
```

而应该理解成：

```text
当前最终 ELF 所需要的
ELF Header
+
Program Header Table
```

因此：

```text
PHDRS 数量变化
        ↓
Program Header 数量变化
        ↓
SIZEOF_HEADERS 变化
        ↓
后面的 Section 起始位置可能变化
```

这就是 linker script 中：

> **一个布局参数改变，可能导致整个 ELF 布局变化。**

---

# 三十二、实验 37-9：增加一个 Segment，看 `SIZEOF_HEADERS` 是否变化

现在：

```ld
PHDRS
{
    text PT_LOAD FILEHDR PHDRS FLAGS(5);
    ro   PT_LOAD FLAGS(4);
    data PT_LOAD FLAGS(6);
}
```

记录：

```bash
readelf -h elf37-filehdr.elf
```

然后增加一个 Segment：

```ld
PHDRS
{
    text PT_LOAD FILEHDR PHDRS FLAGS(5);
    ro   PT_LOAD FLAGS(4);
    data PT_LOAD FLAGS(6);
    extra PT_LOAD FLAGS(4);
}
```

再：

```bash
readelf -h elf37-extra.elf
```

观察：

```text
Number of program headers
```

以及：

```text
Start of program headers
Size of program headers
```

最终你会发现：

```text
Program Header 数量
        ↓
PHDR Table 大小
        ↓
SIZEOF_HEADERS
```

---

# 三十三、把这件事画成公式

假设：

```text
ELF Header = EH
```

Program Header：

```text
PH = 每个 Program Header 大小
```

数量：

```text
N = e_phnum
```

那么：

```text
SIZEOF_HEADERS
=
EH + PH × N
```

对于常见 ELF64：

```text
EH = 64
PH = 56
```

如果：

```text
N = 3
```

那么：

```text
SIZEOF_HEADERS
=
64 + 56 × 3
=
232
=
0xe8
```

如果：

```text
N = 4
```

则：

```text
64 + 56 × 4
=
288
=
0x120
```

所以增加一个 Program Header，会直接改变 Header 总大小。

---

# 三十四、这也是为什么 `PHDRS` 是危险的高级功能

你现在应该能理解：

```text
PHDRS
```

不是简单地：

```text
“给 ELF 加几个 LOAD”
```

而是在同时影响：

```text
Program Header 数量
       ↓
Header 总大小
       ↓
File Offset
       ↓
Section 地址
       ↓
Segment 地址
       ↓
Alignment
       ↓
最终 ELF 文件布局
```

所以复杂的：

```text
kernel
bootloader
bare-metal firmware
UEFI
custom runtime
```

linker script 中经常需要同时分析：

```text
MEMORY
SECTIONS
PHDRS
AT()
ALIGN()
SIZEOF_HEADERS
```

---

# 三十五、实验 37 的最终综合版

建议最终保存：

```text
linker37-final.ld
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
PROVIDE(__data_size = SIZEOF(.data));
PROVIDE(__bss_size  = SIZEOF(.bss));
```

---

# 三十六、完整实验命令清单

编译：

```bash
gcc -ffreestanding -c start.S main.c
```

链接：

```bash
ld \
    -T linker37-final.ld \
    start.o \
    main.o \
    -o elf37.elf \
    -Map=elf37.map
```

---

## ① ELF Header

```bash
readelf -h elf37.elf
```

重点：

```text
Entry point address
Start of program headers
Size of program headers
Number of program headers
Start of section headers
Number of section headers
```

---

## ② Section

```bash
readelf -SW elf37.elf
```

重点：

```text
.text
.rodata
.data
.bss
```

---

## ③ Segment

```bash
readelf -lW elf37.elf
```

重点：

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

## ④ Section → Segment

仍然：

```bash
readelf -lW elf37.elf
```

查看：

```text
Section to Segment mapping
```

---

## ⑤ Section 地址

```bash
objdump -h elf37.elf
```

---

## ⑥ Program Header

```bash
objdump -p elf37.elf
```

---

## ⑦ Symbol

```bash
nm -n elf37.elf
```

---

## ⑧ Map

```bash
less elf37.map
```

---

# 三十七、实验 37 最终应该建立的脑图

```text
                         ELF
                          │
             ┌────────────┴────────────┐
             │                         │
        ELF Header              Section Headers
             │                         │
             │                    .text/.data/...
             │
             ▼
    Program Header Table
             │
             │
       SIZEOF_HEADERS
             │
             ▼
        PT_LOAD
             │
      ┌──────┼──────┐
      │      │      │
     RX      R      RW
      │      │      │
    .text  .rodata .data
                    .bss
```

然后：

```text
PHDRS
  │
  ├── FILEHDR
  │       ↓
  │   ELF Header
  │
  └── PHDRS
          ↓
   Program Header Table
```

这两个关系，是本节的核心。

---

# 三十八、实验 37 的真正目标

这次不要只追求：

```text
ld 能不能成功
```

而是要达到下面这个程度：

看到：

```text
readelf -h
```

你能解释：

```text
e_entry
e_phoff
e_phnum
e_phentsize
e_shoff
```

看到：

```text
readelf -l
```

你能解释：

```text
p_offset
p_vaddr
p_paddr
p_filesz
p_memsz
p_flags
p_align
```

看到 linker script：

```ld
PHDRS
{
    text PT_LOAD FILEHDR PHDRS FLAGS(5);
}
```

你能立刻脑补成：

```text
ELF Header
     +
Program Header Table
     +
属于 text Segment 的 Section
     ↓
PT_LOAD
     ↓
R-X
```

而看到：

```ld
. = ORIGIN(FLASH) + SIZEOF_HEADERS;
```

你应该立即想到：

```text
FLASH 起点
    +
ELF Header
    +
Program Header Table
    ↓
第一个 Section 的布局起点
```

---

# 三十九、下一节：实验 38

下一节我们就进入一个比 `PHDRS` 更容易出错、但也更有价值的主题：

## 实验 38 —— `PT_LOAD` + `AT()` + VMA/LMA + `p_filesz/p_memsz`

核心目标是彻底打通：

```text
Section
   │
   ├── VMA
   └── LMA
        │
        ▼
     Segment
        │
        ├── p_vaddr
        ├── p_paddr
        ├── p_offset
        ├── p_filesz
        └── p_memsz
```

然后做一个真正的启动场景：

```text
FLASH
0x00400000
│
├── .text
├── .rodata
└── .data 的初始化镜像
        │
        │ copy
        ▼
SRAM
0x00600000
│
├── .data
└── .bss
        │
        └── zero
```

最后用：

```bash
readelf -lW
objdump -h
objdump -p
nm -n
```

以及 `.map` 文件，逐字段证明：

```text
p_filesz != p_memsz
```

为什么 `.bss` 不占 ELF 文件空间，却占 RAM；

以及为什么：

```ld
.data > SRAM AT > FLASH
```

最终会同时影响：

```text
.data VMA
.data LMA
PT_LOAD p_vaddr
PT_LOAD p_paddr
p_filesz
p_memsz
```

这一节做完，`VMA/LMA`、`AT()`、`PHDRS`、`PT_LOAD` 就真正串成一个完整模型了。
