# GNU ld 实战课程 · 实验 25

## `PHDRS` + `FILEHDR` + `PHDRS` + `SIZEOF_HEADERS` + Segment 对齐

上一节我们已经从 **Section** 正式进入 **Segment**：

```text
Section
   ↓
.text / .rodata / .data / .bss
   ↓
PHDRS
   ↓
PT_LOAD
   ↓
readelf -lW
```

这一节继续向下钻一层，重点解决你前面实验里已经遇到、而且非常容易混淆的几个问题：

```text
为什么 PT_LOAD 的 Offset / VirtAddr / PhysAddr 不一样？

为什么两个 PT_LOAD 之间突然出现很大的空洞？

为什么 ELF 很小，但文件布局却被对齐到 0x1000、0x200000？

FILEHDR 到底是什么？

PHDRS 到底是什么？

SIZEOF_HEADERS 为什么有时候会导致：
"not enough room for program headers"？

如何自己构造：
ELF Header
+ Program Header Table
+ RX LOAD
+ RW LOAD
？
```

GNU ld 文档明确说明：`PHDRS` 一旦出现在 ELF linker script 中，ld 不再自动创建其他 Program Header；Output Section 可以通过 `:phdr` 指定所属 Segment，而 `FILEHDR` 和 `PHDRS` 可以把 ELF 文件头和 Program Header Table 纳入对应 Segment。([Sourceware][1])

---

# 一、先建立本节最终目标

我们最终希望得到：

```text
ELF 文件

┌──────────────────────────────┐
│ ELF Header                   │
├──────────────────────────────┤
│ Program Header Table         │
├──────────────────────────────┤
│                              │
│ PT_LOAD #1                   │
│ R E                          │
│                              │
│ .text                        │
│ .rodata                      │
│                              │
├──────── page boundary ───────┤
│                              │
│ PT_LOAD #2                   │
│ R W                          │
│                              │
│ .data                        │
│ .bss                         │
│                              │
└──────────────────────────────┘
```

对应：

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

同时希望：

```text
.data
    VMA → RAM
    LMA → ROM
```

这一次还要明确：

```text
File Offset
Virtual Address
Physical Address
File Size
Memory Size
Alignment
```

之间到底是什么关系。

---

# 二、实验 25-1：先看看默认 ld 到底干了什么

仍然使用上一节的源码。

目录：

```text
lab25/
├── start.S
├── main.c
├── data.c
└── linker.ld
```

---

## `start.S`

```asm
.global _start

.text

_start:
    call main
    hlt
```

---

## `main.c`

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

---

## `data.c`

```c
int counter = 1234;

int magic = 0x12345678;

char message[] = "GNU ld";

int buffer[1024];
```

---

# 三、基础 linker.ld

先使用没有 `PHDRS` 的版本：

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

# 四、编译

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

---

# 五、链接

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    data.o \
    -o default.elf \
    -Map=default.map
```

---

# 六、第一次实验：观察默认 Segment

执行：

```bash
readelf -lW default.elf
```

重点记录：

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

例如可能出现类似：

```text
LOAD
000000
00400000
00400000
...
R E
...

LOAD
...
00600000
0040....
...
RW
...
```

**具体数值不要死记。**

不同：

```text
binutils
target
emulation
默认 linker script
```

可能产生不同布局。

我们真正要学习的是：

> 为什么这些数字会这样产生？

---

# 七、实验 25-2：把 ELF 文件想成二维坐标

现在建立一个非常重要的模型：

```text
ELF File Offset
        │
        ▼
文件中的位置
```

以及：

```text
Virtual Address
        │
        ▼
程序运行时地址
```

例如：

```text
File Offset       Virtual Address

0x000000          0x00400000
     │                  │
     │                  │
     ▼                  ▼
ELF Header           程序地址
```

所以：

```text
Offset
```

和：

```text
VirtAddr
```

是完全不同的坐标系。

---

# 八、实验 25-3：理解 `p_offset`

执行：

```bash
readelf -lW default.elf
```

```text
Elf file type is EXEC (Executable file)
Entry point 0x400000
There are 4 program headers, starting at offset 64

Program Headers:
  Type           Offset   VirtAddr           PhysAddr           FileSiz  MemSiz   Flg Align
  LOAD           0x001000 0x0000000000400000 0x0000000000400000 0x000078 0x000078 R E 0x1000
  LOAD           0x002000 0x0000000000400000 0x0000000000400078 0x000008 0x000008 RW  0x1000
  LOAD           0x000020 0x0000000000400020 0x0000000000400080 0x000000 0x001000 RW  0x1000
  GNU_STACK      0x000000 0x0000000000000000 0x0000000000000000 0x000000 0x000000 RWE 0x10

 Section to Segment mapping:
  Segment Sections...
   00     .text .rodata .eh_frame 
   01     .data 
   02     .bss 
   03     
```

找到第一个：

```text
LOAD
```

假设：

```text
Offset = 0x000000
VirtAddr = 0x00400000
```

那么：

```text
文件：

0x000000
   │
   └── PT_LOAD

内存：

0x00400000
   │
   └── PT_LOAD
```

可以理解成：

```text
文件偏移 0x000000
       │
       │ load
       ▼
内存地址 0x00400000
```

这就是 Segment 的核心作用。

---

# 九、实验 25-4：为什么 `p_offset` 不能随便？

对于典型 ELF Segment，通常要求：

```text
p_offset % p_align
=
p_vaddr % p_align
```

例如：

```text
p_align = 0x1000
```

那么：

```text
p_offset
```

和：

```text
p_vaddr
```

必须具有相同的页内偏移。

例如：

```text
p_offset = 0x1000
p_vaddr  = 0x00401000
```

那么：

```text
0x1000 % 0x1000 = 0
0x00401000 % 0x1000 = 0
```

成立。

---

# 十、如果：

```text
p_offset = 0x123
p_vaddr  = 0x00400000
```

而：

```text
p_align = 0x1000
```

那么：

```text
0x123 % 0x1000
=
0x123
```

但是：

```text
0x00400000 % 0x1000
=
0
```

不相等。

这种布局不适合典型页映射加载模型。

因此：

> Segment 对齐不是“好看”，而是 ELF 加载布局的基础约束之一。

---

# 十一、实验 25-5：看看默认 `p_align`

```bash
readelf -lW default.elf
```

观察：

```text
Align
```

你可能看到：

```text
0x1000
```

或者在某些目标/默认脚本下看到更大的值。

这也是为什么你之前会看到：

```text
0x1000
```

甚至：

```text
0x200000
```

这样的巨大对齐。

---

# 十二、为什么会有这么大的 Align？

这和目标平台的：

```text
MAXPAGESIZE
```

有关。

GNU ld 的默认 ELF linker script 会根据目标的页面/最大页面对齐规则构造 Segment。

因此：

```text
一个只有几百字节的程序
```

不代表：

```text
ELF 文件布局一定只有几百字节。
```

因为 Segment 之间可能为了满足：

```text
page alignment
```

产生大量 padding。

---

# 十三、实验 25-6：直接查看默认 linker script

这一步非常重要。

执行：

```bash
ld --verbose
```

输出非常长。

把它保存：

```bash
ld --verbose > default-linker-script.txt
```

然后：

```bash
grep -n "MAXPAGESIZE" default-linker-script.txt
```

也可以：

```bash
grep -n "PHDRS" default-linker-script.txt
```

以及：

```bash
grep -n "ALIGN" default-linker-script.txt
```

你会看到默认 linker script 中大量与：

```text
MAXPAGESIZE
CONSTANT
ALIGN
PHDRS
```

相关的布局逻辑。

这一步很值得你认真看。

因为从现在开始：

> **不要只学习“自己写 linker.ld”，还要学会阅读 GNU ld 自己生成的 linker script。**

---

# 十四、实验 25-7：`MAXPAGESIZE`

GNU ld 提供：

```ld
CONSTANT (MAXPAGESIZE)
```

可以获得目标默认最大页面大小。

例如：

```ld
. = ALIGN(CONSTANT(MAXPAGESIZE));
```

表示：

> 把当前地址推进到目标默认最大页边界。

这也是默认 ELF linker script 经常出现：

```text
ALIGN(CONSTANT (MAXPAGESIZE))
```

的原因。

---

# 十五、建立一个实验 linker

创建：

```text
linker-maxpage.ld
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

    . = ALIGN(CONSTANT(MAXPAGESIZE));

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
}
```

---

# 十六、这里故意制造一个大空洞

关键：

```ld
. = ALIGN(CONSTANT(MAXPAGESIZE));
```

假设当前：

```text
. = 0x00400050
```

而：

```text
MAXPAGESIZE = 0x200000
```

那么：

```text
ALIGN(0x00400050, 0x200000)
```

会跳到：

```text
0x00600000
```

于是：

```text
0x00400050
      ↓
      │
      │ 巨大的 padding
      │
      ↓
0x00600000
```

这就是：

# Segment 为什么可能突然变得很大。

---

# 十七、重新链接

```bash
ld \
    -T linker-maxpage.ld \
    start.o \
    main.o \
    data.o \
    -o maxpage.elf \
    -Map=maxpage.map
```

然后：

```bash
readelf -lW maxpage.elf
```

再：

```bash
ls -lh maxpage.elf
```

你会非常直观地看到：

```text
Section 实际数据很小
```

但是：

```text
ELF 文件布局
```

可能明显膨胀。

---

# 十八、Map 文件观察

```bash
less maxpage.map
```

重点找：

```text
.text
.rodata
.data
```

观察：

```text
.text
    ↓
.rodata
    ↓
巨大地址跳跃
    ↓
.data
```

Map 中可能出现：

```text
*fill*
```

或者你可以直接计算：

```text
.data LMA
-
.rodata end
```

得到中间浪费的空间。

---

# 十九、这是一个非常重要的经验

以后看到：

```text
ELF 很大
```

不要第一反应：

> “代码是不是很多？”

先检查：

```bash
readelf -S
readelf -lW
```

尤其看：

```text
p_offset
p_filesz
p_memsz
p_align
```

然后：

```text
Map
```

看有没有：

```text
ALIGN
```

导致的大块空洞。

---

# 二十、实验 25-8：`FILEHDR`

现在开始研究：

```ld
FILEHDR
```

GNU ld 的 `PHDRS` 语法：

```ld
PHDRS
{
    name type [FILEHDR] [PHDRS] ...
}
```

其中 `FILEHDR` 表示：

> 这个 Segment 包含 ELF file header。

官方文档明确将 `FILEHDR` 与 `PHDRS` 列为 `PHDRS` 命令中的关键属性。([Sourceware][1])

---

# 二十一、实验：没有 `FILEHDR`

```ld
PHDRS
{
    text PT_LOAD FLAGS(5);
}
```

然后：

```ld
.text :
{
    *(.text)
} > ROM :text
```

此时：

```text
PT_LOAD
```

并不要求把：

```text
ELF Header
```

包含进 Segment。

---

# 二十二、加上 `FILEHDR`

修改：

```ld
PHDRS
{
    text PT_LOAD FILEHDR FLAGS(5);
}
```

现在：

```text
text Segment
```

必须覆盖：

```text
ELF Header
```

因此它的：

```text
p_offset
```

通常会从：

```text
0
```

开始。

这也是常见 ELF 布局：

```text
Offset 0
│
├── ELF Header
├── Program Header Table
└── .text
```

---

# 二十三、实验 25-9：`PHDRS`

现在：

```ld
PHDRS
{
    text PT_LOAD FILEHDR PHDRS FLAGS(5);
}
```

这里两个关键词：

```text
FILEHDR
PHDRS
```

分别表示：

```text
FILEHDR
    ELF File Header

PHDRS
    Program Header Table
```

所以：

```text
PT_LOAD text
```

可以覆盖：

```text
ELF Header
Program Header Table
.text
```

形成：

```text
┌────────────────────────────┐
│ ELF Header                 │
├────────────────────────────┤
│ Program Header Table       │
├────────────────────────────┤
│ .text                      │
├────────────────────────────┤
│ .rodata                    │
└────────────────────────────┘
        PT_LOAD R E
```

这就是非常经典的 ELF 第一 Segment 布局。

---

# 二十四、实验 25-10：验证 `FILEHDR PHDRS`

建立：

```ld
ENTRY(_start)

MEMORY
{
    ROM (rx) : ORIGIN = 0x00400000, LENGTH = 64K
    RAM (rw) : ORIGIN = 0x00600000, LENGTH = 64K
}

PHDRS
{
    text PT_LOAD FILEHDR PHDRS FLAGS(5);
    data PT_LOAD FLAGS(6);
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
        *(.data)
        *(.data.*)
    } > RAM AT > ROM :data

    .bss :
    {
        *(.bss)
        *(.bss.*)
        *(COMMON)
    } > RAM :data
}
```

---

# 二十五、为什么这里用 `SIZEOF_HEADERS`？

`SIZEOF_HEADERS` 返回：

> ELF 输出文件头部区域的大小，也就是文件开头的 ELF Header + Program Header 等头部数据所占空间。

GNU ld 官方文档就是这样定义它的，并指出它可以用于把第一个 Section 放到 headers 之后。([Sourceware][2])

所以：

```ld
. = SIZEOF_HEADERS;
```

可以理解为：

```text
跳过：

ELF Header
+
Program Header Table

然后开始：

.text
```

于是：

```text
ELF Header
      ↓
Program Header Table
      ↓
.text
```

布局非常直观。

---

# 二十六、但是 `SIZEOF_HEADERS` 有一个大坑

这是今天非常重要的一点。

GNU ld 文档明确警告：

> 如果 linker script 使用 `SIZEOF_HEADERS`，linker 必须在确定所有 Section 地址和大小之前计算 Program Header 数量。

如果后面发现需要额外的 Program Header，就可能报：

```text
not enough room for program headers
```

官方建议是：

```text
避免 SIZEOF_HEADERS
```

或者：

```text
重新设计 linker script
```

或者：

```text
自己通过 PHDRS 明确定义 Program Header
```

([Sourceware][2])

这也是为什么我们现在正好先学习：

```text
PHDRS
```

再学习：

```text
SIZEOF_HEADERS
```

---

# 二十七、实验 25-11：故意制造 `SIZEOF_HEADERS` 问题

先：

```ld
ENTRY(_start)

SECTIONS
{
    . = SIZEOF_HEADERS;

    .text :
    {
        *(.text)
    }

    .weird :
    {
        *(.weird)
    }
}
```

然后人为制造一个特殊 Section：

```c
__attribute__((section(".weird")))
int weird_data = 123;
```

编译：

```bash
gcc -ffreestanding -fno-pie -c weird.c -o weird.o
```

链接：

```bash
ld \
    -T linker-sizeof-headers.ld \
    start.o \
    weird.o \
    -o sizeofheaders.elf
```

如果 linker 因为额外 Program Header 需求导致布局冲突，你可能得到：

```text
not enough room for program headers
```

不同目标和 binutils 版本未必稳定复现这个错误，但**原理非常重要**。

---

# 二十八、为什么 `PHDRS` 可以解决这个问题？

因为：

```ld
PHDRS
{
    text PT_LOAD FILEHDR PHDRS FLAGS(5);
    data PT_LOAD FLAGS(6);
}
```

告诉 linker：

> 我自己已经定义好了需要哪些 Program Header。

这样：

```text
Program Header 数量
```

不再需要完全由 ld 在后面推断。

因此：

```text
SIZEOF_HEADERS
```

就有了稳定的 header size 基础。

---

# 二十九、实验 25-12：正式建立“Header Segment”

我们使用：

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
headers
```

是：

```text
PT_PHDR
```

而：

```text
text
```

是：

```text
PT_LOAD
```

并且：

```text
FILEHDR
PHDRS
```

都纳入 `text` Segment。

---

# 三十、完整脚本

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

# 三十一、链接

```bash
ld \
    -T linker-phdrs-header.ld \
    start.o \
    main.o \
    data.o \
    -o header.elf \
    -Map=header.map
```

---

# 三十二、第一验证：ELF Header

```bash
readelf -h header.elf
```

重点看：

```text
Entry point address
Start of program headers
Number of program headers
Size of program headers
```

例如：

```text
Start of program headers:
    64

Number of program headers:
    3
```

具体数字根据目标架构不同。

---

# 三十三、第二验证：Program Header

```bash
readelf -lW header.elf
```

现在你应该看到：

```text
PHDR
LOAD
LOAD
```

类似：

```text
Type   Offset   VirtAddr   PhysAddr   FileSiz   MemSiz   Flg
PHDR   ...
LOAD   ...
LOAD   ...
```

---

# 三十四、第三验证：Section → Segment

继续看：

```text
Section to Segment mapping:
```

理想情况下：

```text
Segment 0
    headers

Segment 1
    .text
    .rodata

Segment 2
    .data
    .bss
```

具体映射可能随脚本和目标有所变化，但你要重点理解：

```text
PHDR
```

和：

```text
PT_LOAD
```

是两种不同的 Program Header 类型。

---

# 三十五、`PT_PHDR` 是什么？

它描述：

> Program Header Table 自己的位置。

所以：

```text
PT_PHDR
```

可以理解成：

```text
“程序头表本身在哪里？”
```

而：

```text
PT_LOAD
```

是：

```text
“哪些内容需要被加载到内存？”
```

---

# 三十六、实验 25-13：`objdump -p`

执行：

```bash
objdump -p header.elf
```

这里可以再次看到：

```text
Program Header:
```

比较：

```bash
readelf -lW header.elf
```

和：

```bash
objdump -p header.elf
```

这两个命令以后会成为你分析 Segment 的常用组合。

GNU ld 文档也明确建议可以使用 `objdump -p` 查看 Program Header。([Sourceware][1])

---

# 三十七、实验 25-14：分析 `FILEHDR`

现在我们做一个小实验。

### A

```ld
text PT_LOAD FLAGS(5);
```

### B

```ld
text PT_LOAD FILEHDR FLAGS(5);
```

### C

```ld
text PT_LOAD FILEHDR PHDRS FLAGS(5);
```

分别：

```bash
ld -T a.ld ... -o a.elf
ld -T b.ld ... -o b.elf
ld -T c.ld ... -o c.elf
```

然后：

```bash
readelf -lW a.elf
readelf -lW b.elf
readelf -lW c.elf
```

观察：

```text
Offset
VirtAddr
FileSiz
```

尤其：

```text
PT_LOAD #1
```

覆盖范围的变化。

---

# 三十八、建立理解表

| 属性               | 控制什么                              |
| ---------------- | --------------------------------- |
| `FILEHDR`        | 把 ELF File Header 纳入 Segment      |
| `PHDRS`          | 把 Program Header Table 纳入 Segment |
| `FLAGS(5)`       | `R + X`                           |
| `FLAGS(6)`       | `R + W`                           |
| `:text`          | Section → `text` Segment          |
| `:data`          | Section → `data` Segment          |
| `SIZEOF_HEADERS` | ELF headers 总大小                   |

这张表建议直接记下来。

---

# 三十九、实验 25-15：理解三个地址

现在重新看：

```text
p_offset
p_vaddr
p_paddr
```

建立：

```text
ELF 文件

Offset
   │
   │
   ▼
文件位置
```

然后：

```text
VirtAddr
   │
   ▼
运行地址
```

再：

```text
PhysAddr
   │
   ▼
物理加载地址语义
```

对于普通 Linux 用户空间 ELF：

```text
p_paddr
```

通常不像：

```text
p_vaddr
```

那样重要。

但是在：

```text
裸机
Bootloader
Firmware
ROM/RAM
```

场景里：

```text
PhysAddr / LMA
```

的概念就开始非常重要。

---

# 四十、实验 25-16：把 Section 与 Segment 完全统一

现在把前面 23、24、25 三节串起来：

```text
.data
│
├── VMA
│     ↓
│   RAM
│
├── LMA
│     ↓
│   ROM
│
└── Segment
      ↓
    PT_LOAD
      ↓
    FLAGS(6)
      ↓
    R W
```

所以：

```text
.data
```

同时参与：

```text
Section Layout
+
Memory Layout
+
Load Image Layout
+
Program Header Layout
```

这就是为什么 GNU ld 的 linker script 到后面会越来越复杂。

---

# 四十一、实验 25-17：`AT()` 与 PHDR `AT()`

这里再引入一个容易混淆的语法。

Section：

```ld
.data :
{
    ...
} > RAM AT > ROM
```

是：

```text
Output Section LMA
```

而：

```ld
PHDRS
{
    text PT_LOAD
        AT(0x00400000)
        FLAGS(5);
}
```

这里的：

```text
AT()
```

属于：

# Program Header

不是：

# Output Section

因此：

```ld
.data AT(...)
```

和：

```ld
PHDRS ... AT(...)
```

不要混淆。

它们分别作用在：

```text
Section LMA
```

和：

```text
Program Header physical address
```

层次。

---

# 四十二、实验 25-18：为什么不建议现在乱用 PHDR `AT()`

当前我们的目标是：

```text
.data
VMA → RAM
LMA → ROM
```

因此：

```ld
.data > RAM AT > ROM
```

已经非常直观。

如果再给：

```ld
PT_LOAD
```

指定：

```ld
AT(...)
```

那么：

```text
Section LMA
+
Segment p_paddr
```

之间就可能产生更加复杂的关系。

所以当前阶段：

> **先掌握 `Section AT()`，再掌握 `PHDRS AT()`。**

不要一口气全部混起来。

---

# 四十三、实验 25-19：Map 文件分析方法升级

这一节 Map 文件分析增加两个字段：

```text
Section
Segment
```

以后每次做实验，建议记录：

```text
Section:
    VMA
    LMA
    Size
    Alignment

Segment:
    Offset
    VirtAddr
    PhysAddr
    FileSiz
    MemSiz
    Flags
    Align
```

然后画成：

```text
.text
  │
  └────→ PT_LOAD RX

.rodata
  │
  └────→ PT_LOAD RX

.data
  │
  └────→ PT_LOAD RW

.bss
  │
  └────→ PT_LOAD RW
```

这会极大提升你排查 linker 问题的效率。

---

# 四十四、实验 25-20：用 `readelf -SW` 和 `readelf -lW` 配对

以后不要：

```bash
readelf -S
```

看完就结束。

固定执行：

```bash
readelf -SW firmware.elf
```

然后：

```bash
readelf -lW firmware.elf
```

前者：

```text
Section
```

后者：

```text
Segment
```

然后：

```bash
objdump -h firmware.elf
```

确认：

```text
VMA
LMA
```

最后：

```bash
nm -n firmware.elf
```

确认：

```text
symbol
```

这四个命令构成：

# GNU ld ELF 布局分析四件套

```text
readelf -SW
readelf -lW
objdump -h
nm -n
```

再加：

```text
.map
```

就是完整闭环。

---

# 四十五、实验 25-21：计算一个 Segment 的真实大小

假设：

```text
p_offset = 0x000000
p_filesz = 0x250
```

那么文件中的：

```text
PT_LOAD
```

覆盖：

```text
0x000000
~
0x00024F
```

如果：

```text
p_memsz = 0x1250
```

那么加载后：

```text
内存：

0x000000
──────────────
实际文件数据
──────────────
额外 zero-fill
──────────────
0x1250
```

差值：

```text
0x1250 - 0x250
=
0x1000
```

非常可能对应：

```text
.bss
```

或者其他：

```text
NOBITS
```

Section。

---

# 四十六、实验 25-22：为什么 Segment 之间有巨大文件空洞？

假设：

```text
LOAD #1

Offset:
0x000000

FileSiz:
0x200

```

第二个：

```text
LOAD #2

Offset:
0x200000
```

那么中间：

```text
0x200000 - 0x200
=
0x1FFE00
```

全部可能只是：

```text
Segment alignment
```

造成的文件间隔。

所以：

```text
ELF 很大
```

不等于：

```text
代码很多
```

有可能只是：

```text
p_align
```

造成的布局浪费。

---

# 四十七、实验 25-23：把大页面对齐改成 0x1000

在自定义 linker script 中，不要直接：

```ld
ALIGN(CONSTANT(MAXPAGESIZE))
```

而可以实验性地使用：

```ld
. = ALIGN(0x1000);
```

例如：

```ld
.text :
{
    *(.text)
} > ROM :text

. = ALIGN(0x1000);

.rodata :
{
    *(.rodata)
} > ROM :text
```

然后：

```bash
ld \
    -T linker-4k.ld \
    start.o \
    main.o \
    data.o \
    -o 4k.elf \
    -Map=4k.map
```

比较：

```bash
ls -l 4k.elf
```

与：

```bash
ls -l maxpage.elf
```

再：

```bash
readelf -lW 4k.elf
readelf -lW maxpage.elf
```

你会直观看到：

```text
Section 地址
Segment Offset
文件大小
```

发生的变化。

---

# 四十八、但是要特别注意

不要得出：

> “以后全部使用 4K 对齐就好了。”

不是。

对于：

```text
Linux ELF
```

平台默认的：

```text
page size
max page size
ABI
loader
```

都有自己的约束。

而对于：

```text
裸机 MCU
```

你可能根本不需要：

```text
Linux-style PT_LOAD
```

的页面语义。

所以：

```text
4K
2MB
64K
Flash sector
MCU erase block
MMU page
```

必须根据目标平台理解。

---

# 四十九、实验 25-24：真正制作一个“固件式” Segment 布局

现在我们把目标明确化：

```text
ROM:
0x00400000
│
├── ELF Header
├── Program Headers
├── .text
├── .rodata
└── .data 初始化镜像
             │
             │ copy
             ▼
RAM:
0x00600000
│
├── .data
├── .bss
├── heap
└── stack
```

对应 Segment：

```text
PT_LOAD RX
    .text
    .rodata

PT_LOAD RW
    .data
    .bss
```

这就是我们下一阶段最终要实现的：

# Firmware Image Layout

---

# 五十、实验 25-25：最终版 linker.ld

先给出一个适合继续实验的版本：

```ld
ENTRY(_start)

MEMORY
{
    ROM (rx) : ORIGIN = 0x00400000, LENGTH = 64K
    RAM (rw) : ORIGIN = 0x00600000, LENGTH = 64K
}

PHDRS
{
    text PT_LOAD
         FILEHDR
         PHDRS
         FLAGS(5);

    data PT_LOAD
         FLAGS(6);
}

SECTIONS
{
    . = SIZEOF_HEADERS;

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

# 五十一、这份 linker script 现在已经控制了多少东西？

已经同时控制：

```text
① ROM
② RAM
③ Section VMA
④ Section LMA
⑤ Output Section Alignment
⑥ Program Header
⑦ Segment FLAGS
⑧ ELF Header 所属 Segment
⑨ Program Header Table 所属 Segment
⑩ .data 初始化镜像
⑪ .bss zero-fill
⑫ RAM overflow
⑬ ROM overflow
```

这已经是一个相当完整的 ELF linker script 骨架。

---

# 五十二、最终验证命令

完整跑一遍：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    data.o \
    -o firmware.elf \
    -Map=firmware.map
```

然后：

```bash
readelf -h firmware.elf
```

看：

```text
Entry point
Start of program headers
Number of program headers
```

---

```bash
readelf -SW firmware.elf
```

看：

```text
.text
.rodata
.data
.bss
```

---

```bash
objdump -h firmware.elf
```

看：

```text
VMA
LMA
Size
Align
```

---

```bash
readelf -lW firmware.elf
```

看：

```text
PHDR
LOAD
LOAD
```

以及：

```text
Offset
VirtAddr
PhysAddr
FileSiz
MemSiz
Flg
Align
```

---

```bash
objdump -p firmware.elf
```

再次确认 Program Headers。

---

```bash
nm -n firmware.elf | grep -E 'data|bss'
```

确认：

```text
__data_start
__data_end
__data_load_start
__data_size

__bss_start
__bss_end
__bss_size
```

---

# 五十三、Map 文件最终分析模板

打开：

```bash
less firmware.map
```

建议每次都按这个顺序：

### ① `.text`

```text
VMA =
Size =
Segment = text
```

### ② `.rodata`

```text
VMA =
Size =
Segment = text
```

### ③ `.data`

```text
VMA =
LMA =
Size =
Segment = data
```

### ④ `.bss`

```text
VMA =
Size =
Segment = data
```

### ⑤ Segment

然后去：

```bash
readelf -lW firmware.elf
```

建立：

```text
text
    .text
    .rodata

data
    .data
    .bss
```

这样就完成：

```text
Section Layout
        +
Segment Layout
        +
ROM/RAM Layout
```

三者统一。

---

# 五十四、本节最重要的知识图

```text
                         ELF
                          │
              ┌───────────┴───────────┐
              │                       │
          Sections                 Segments
              │                       │
       ┌──────┼──────┐          ┌─────┴─────┐
       │      │      │          │           │
     .text .rodata .data      PT_LOAD     PT_LOAD
                         │        RX          RW
                         │         │           │
                         │         │           │
                         └────┐    │           │
                              │    │           │
                         VMA/LMA  │           │
                              │   ROM         RAM
                              │
                         AT > ROM
                              │
                              ▼
                        .data image
```

再加上：

```text
FILEHDR
   ↓
ELF Header

PHDRS
   ↓
Program Header Table

SIZEOF_HEADERS
   ↓
Headers 总大小

MAXPAGESIZE
   ↓
Segment/Page 对齐
```

整个 GNU ld 的层次就开始非常清楚了。

---

# 五十五、实验 25 的核心结论

你现在应该能够准确区分：

```text
Section
```

和：

```text
Segment
```

以及：

```text
VMA
```

和：

```text
LMA
```

以及：

```text
File Offset
```

和：

```text
Virtual Address
```

以及：

```text
FILEHDR
```

和：

```text
PHDRS
```

以及：

```text
Section AT()
```

和：

```text
PHDR AT()
```

---

# 五十六、最终形成这张“GNU ld 地址地图”

```text
                   linker script
                        │
          ┌─────────────┼─────────────┐
          │             │             │
       SECTIONS       MEMORY         PHDRS
          │             │             │
          │             │             │
          ▼             ▼             ▼
       Section        ROM/RAM       Segment
          │                           │
          │                           │
      ┌───┴────┐                 ┌────┴────┐
      │        │                 │         │
     VMA      LMA              FLAGS     ALIGN
      │        │                 │         │
      │        │                 │         │
      ▼        ▼                 ▼         ▼
     RAM      ROM               RX/RW     page
      │        │
      └────┬───┘
           │
           ▼
        ELF Image
           │
           ▼
      readelf -S
      readelf -lW
      objdump -h
      objdump -p
      nm
      map
```

这张图基本就是你到目前为止这套 GNU `ld` 实战课程的核心框架。

---

## 下一节：实验 26

下一步继续往真正的 **Firmware Linker Script** 走：

### 实验 26：构造“真正的 ROM → RAM 镜像”

我们将把现在的 ELF 布局进一步做成：

```text
ROM
┌────────────────────────────────┐
│ ELF/LOAD RX                    │
│ .text                          │
│ .rodata                        │
├────────────────────────────────┤
│ .data LOAD IMAGE               │
│                                │
├────────────────────────────────┤
│ Firmware metadata              │
│ CRC / version / magic          │
└────────────────────────────────┘

RAM
┌────────────────────────────────┐
│ .data                          │
├────────────────────────────────┤
│ .bss                           │
├────────────────────────────────┤
│ heap                           │
├────────────────────────────────┤
│                                │
│ stack_top                      │
└────────────────────────────────┘
```

并第一次把：

```ld
LOADADDR()
ADDR()
SIZEOF()
ORIGIN()
LENGTH()
PROVIDE()
ASSERT()
AT()
PHDRS
```

全部组合起来。

然后再做一个非常实用的实验：

```text
firmware.elf
      ↓
objcopy
      ↓
firmware.bin
      ↓
hexdump
```

直接观察：

> **linker script 中的 ROM 布局，最终到底变成了什么样的二进制镜像。**

这一步之后，GNU `ld` 就会从“ELF 理论实验”正式进入 **Bootloader / MCU / 裸机 Firmware 镜像制作**阶段。

[1]: https://sourceware.org/binutils/docs-2.39/ld.pdf?utm_source=chatgpt.com "The GNU linker"
[2]: https://sourceware.org/binutils/docs/ld.pdf?utm_source=chatgpt.com "The GNU linker"

