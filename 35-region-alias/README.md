好，接着上次的路线走。上一节已经把 `SORT / REVERSE / SORT_NONE / EXCLUDE_FILE / KEEP` 这一组 Input Section 控制手段补齐了。

这一节正式进入我们之前规划的 **实验 35：`MEMORY` + `ORIGIN()` + `LENGTH()` + `> REGION` + `REGION_ALIAS`**。

这一节非常关键，因为从这里开始，GNU ld 不再只是“整理 Section”，而是开始真正回答：

> **程序到底应该放进哪块物理内存？**

GNU ld 的 `MEMORY` 命令就是用来描述目标内存区域的起始地址和大小，并让 Output Section 分配到指定区域；如果区域空间不足，ld 会报告 overflow，而且它不会为了塞进去而自动重新排列 Section。[Sourceware](https://sourceware.org/binutils/docs-2.38/ld.pdf?utm_source=chatgpt.com)

---

# GNU ld 实战课程 · 实验 35

## 从 Section 布局进入真实 Memory Layout

本节最终建立这样一个模型：

```text
                    ELF
                     │
             ┌───────┴───────┐
             │               │
            ROM             RAM
       0x00400000       0x00600000
             │               │
       ┌─────┼─────┐    ┌────┼────┐
       │     │     │    │    │    │
     .text .rodata      .data .bss stack
       │     │          │
       │     │          │
       │     └──────────┘
       │       Load
       │       Image
       │
       ▼
   ROM 中保存
   RAM 数据初始值
```

这里会第一次真正区分：

```text
VMA
LMA
```

这也是你之前 `AT()`、`AT > RAM`、`.data`、ROM/RAM 报错的根源。

---

# 一、实验 35 的递进路线

我们不要一次把所有东西塞进去，而是拆成：

```text
35-1  MEMORY
  ↓
35-2  ORIGIN() / LENGTH()
  ↓
35-3  > REGION
  ↓
35-4  多个 MEMORY Region
  ↓
35-5  MEMORY Overflow
  ↓
35-6  AT > REGION
  ↓
35-7  VMA / LMA / LOADADDR()
  ↓
35-8  REGION_ALIAS
  ↓
35-9  综合 ROM/RAM Image
```

最终再进入下一章：

```text
实验 36
PHDRS + Program Header + Segment
```

---

# 二、实验 35-1：最小 `MEMORY`

先不要碰 `.data`。

只做一件事：

> 定义一块 ROM，然后把 `.text` 放进去。

---

## 1. 创建目录

```text
ld-lab/
└── 35-memory/
    ├── start.S
    ├── main.c
    └── linker.ld
```

---

# 三、源码

## `start.S`

这次使用非常简单的启动代码：

```asm
.global _start

.section .text.start
_start:
    call main

1:
    jmp 1b
```

这里没有 libc。

因此后面可以直接使用：

```bash
ld
```

而不是：

```bash
gcc
```

这样更适合研究 ld 本身。

---

# 四、`main.c`

```c
volatile int counter = 42;

int main(void)
{
    counter++;

    return counter;
}
```

注意：

```c
counter
```

不是 `const`。

因此它应该进入：

```text
.data
```

而不是：

```text
.rodata
```

---

# 五、先看编译产生什么

```bash
gcc -ffreestanding -c start.S main.c
```

然后：

```bash
readelf -SW start.o
```

以及：

```bash
readelf -SW main.o
```

你应该重点观察：

```text
start.o
    .text.start

main.o
    .text
    .data
```

---

# 六、创建第一个 `MEMORY`

`linker.ld`：

```ld
ENTRY(_start)

MEMORY
{
    ROM (rx) : ORIGIN = 0x00400000, LENGTH = 64K
}

SECTIONS
{
    .text :
    {
        *(.text.start)
        *(.text)
    } > ROM
}
```

这里终于开始出现我们过去一直在讨论的：

```ld
> ROM
```

它不是：

```text
“把 Section 名字改成 ROM”
```

而是：

> **告诉 ld：这个 Output Section 应该分配到名为 `ROM` 的 MEMORY Region。**

---

# 七、编译与链接

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    -o memory01.elf \
    -Map=memory01.map
```

---

# 八、第一层验证：readelf

```bash
readelf -SW memory01.elf
```

寻找：

```text
.text
```

重点看：

```text
Addr
Offset
Size
Flg
```

`.text` 应该从：

```text
0x00400000
```

附近开始。

为什么？

因为：

```ld
ROM : ORIGIN = 0x00400000
```

而：

```ld
.text : { ... } > ROM
```

告诉 ld：

```text
.text
 ↓
ROM
 ↓
0x00400000
```

---

# 九、第二层验证：objdump

```bash
objdump -h memory01.elf
```

你会看到类似：

```text
Idx Name          Size      VMA
...
  .text          ........  00400000
```

这一步非常重要：

```text
MEMORY
   ↓
> ROM
   ↓
VMA = ORIGIN(ROM)
```

---

# 十、第三层验证：Map

```bash
grep -A15 -B3 '\.text' memory01.map
```

Map 中应该看到类似：

```text
.text           0x0000000000400000 ...
                0x0000000000400000                ...
 *(.text.start)
 .text.start    0x0000000000400000 ...
 *(.text)
 .text          0x000000000040000...
```

这里第一次出现一个非常重要的关系：

```text
Output Section
      │
      ▼
Memory Region
      │
      ▼
Address
```

---

# 十一、理解 `MEMORY` 的真正作用

现在我们的 linker script：

```ld
MEMORY
{
    ROM (rx) : ORIGIN = 0x00400000, LENGTH = 64K
}
```

相当于告诉 ld：

```text
ROM

开始地址：
0x00400000

长度：
64 × 1024

结束地址：
0x00410000
```

注意：

```text
LENGTH = 64K
```

不是结束地址。

真正的结束地址：

```text
ORIGIN(ROM) + LENGTH(ROM)
```

也就是：

```text
0x00400000 + 0x10000
=
0x00410000
```

---

# 十二、实验 35-2：`ORIGIN()` 和 `LENGTH()`

现在我们不再手算。

让 linker 自己产生符号。

修改：

```ld
ENTRY(_start)

MEMORY
{
    ROM (rx) : ORIGIN = 0x00400000, LENGTH = 64K
}

PROVIDE(__rom_start = ORIGIN(ROM));
PROVIDE(__rom_end   = ORIGIN(ROM) + LENGTH(ROM));
PROVIDE(__rom_size  = LENGTH(ROM));

SECTIONS
{
    .text :
    {
        *(.text.start)
        *(.text)
    } > ROM
}
```

---

# 十三、链接

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    -o memory02.elf \
    -Map=memory02.map
```

---

# 十四、用 `nm` 验证

```bash
nm -n memory02.elf
```

寻找：

```text
__rom_start
__rom_end
__rom_size
```

应该类似：

```text
0000000000400000 A __rom_start
0000000000410000 A __rom_end
0000000000010000 A __rom_size
```

注意这里的：

```text
A
```

通常表示：

```text
ABS
```

即 Absolute Symbol。

---

# 十五、为什么 `ORIGIN()` 很重要？

不要写死：

```ld
__rom_start = 0x00400000;
__rom_end   = 0x00410000;
```

而应该：

```ld
__rom_start = ORIGIN(ROM);
__rom_end   = ORIGIN(ROM) + LENGTH(ROM);
```

这样以后只修改：

```ld
MEMORY
{
    ROM : ORIGIN = ..., LENGTH = ...
}
```

整个 linker script 都会自动跟着变化。

这就是 linker script 中一个非常重要的设计思想：

> **让 Memory Layout 成为单一事实来源。**

---

# 十六、实验 35-3：增加 RAM

现在真正开始像 MCU 了。

修改：

```ld
MEMORY
{
    ROM (rx)  : ORIGIN = 0x00400000, LENGTH = 64K
    RAM (rwx) : ORIGIN = 0x00600000, LENGTH = 64K
}
```

然后：

```ld
SECTIONS
{
    .text :
    {
        *(.text.start)
        *(.text)
    } > ROM

    .data :
    {
        *(.data)
    } > RAM

    .bss :
    {
        *(.bss)
        *(COMMON)
    } > RAM
}
```

---

# 十七、重新链接

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    -o memory03.elf \
    -Map=memory03.map
```

---

# 十八、这时候发生了什么？

`main.c`：

```c
volatile int counter = 42;
```

产生：

```text
.data
```

而 linker script：

```ld
.data :
{
    *(.data)
} > RAM
```

于是：

```text
.data
    ↓
RAM
    ↓
0x00600000
```

所以：

```bash
readelf -SW memory03.elf
```

应该看到：

```text
.text   0x00400000
.data   0x00600000
```

---

# 十九、这里第一次出现一个关键概念

现在：

```text
.text
VMA = 0x00400000

.data
VMA = 0x00600000
```

这意味着：

```text
代码运行在 ROM 地址空间
数据运行在 RAM 地址空间
```

对于真正的 MCU：

```text
Flash
0x08000000
```

和：

```text
SRAM
0x20000000
```

通常也是类似的思想。

---

# 二十、实验 35-4：让 `MEMORY` 自己检查容量

现在故意制造一个小 ROM。

修改：

```ld
MEMORY
{
    ROM (rx)  : ORIGIN = 0x00400000, LENGTH = 32
    RAM (rwx) : ORIGIN = 0x00600000, LENGTH = 64K
}
```

注意：

```text
32
```

是：

```text
32 bytes
```

---

# 二十一、重新链接

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    -o memory-overflow.elf \
    -Map=overflow.map
```

这一次很可能出现：

```text
region `ROM' overflowed by ...
```

这就是我们之前经常看到的：

```text
region `ROM' overflowed
```

但现在终于可以从原理上解释它。

---

# 二十二、为什么 ld 能发现 Overflow？

因为我们告诉它：

```ld
ROM (rx) :
    ORIGIN = 0x00400000,
    LENGTH = 32
```

所以有效地址范围是：

```text
0x00400000
        ↓
0x00400020
```

如果：

```text
.text size > 32
```

那么：

```text
.text
████████████████████████████████████████
│
└── 超过 ROM
```

ld 就报告：

```text
region `ROM' overflowed
```

官方文档明确说明，`MEMORY` 可以让 linker 检查区域是否过满；同时 linker 不会自动重新排列 Sections 来“想办法塞进去”。[Sourceware](https://sourceware.org/binutils/docs-2.38/ld.pdf?utm_source=chatgpt.com)

---

# 二十三、实验 35-5：自己观察 `ORIGIN + LENGTH`

把 ROM 恢复：

```ld
ROM (rx) : ORIGIN = 0x00400000, LENGTH = 64K
```

然后：

```ld
PROVIDE(__rom_start = ORIGIN(ROM));
PROVIDE(__rom_end = ORIGIN(ROM) + LENGTH(ROM));
```

执行：

```bash
nm -n memory.elf
```

得到：

```text
__rom_start = 0x00400000
__rom_end   = 0x00410000
```

画成：

```text
0x00400000
     │
     │  ROM
     │
     │  64 KB
     │
0x00410000
```

以后看到：

```ld
ORIGIN(X)
LENGTH(X)
```

脑子里应该直接形成这个图。

---

# 二十四、实验 35-6：进入真正重要的 `AT >`

现在是本节的核心。

目前：

```text
.data
VMA = RAM
```

但是：

> RAM 上电之后并没有自动拥有 `.data` 的初始值。

比如：

```c
int counter = 42;
```

程序启动后必须让：

```text
RAM[counter] = 42
```

那么 `42` 从哪里来？

答案：

> 放在 ROM 的程序镜像中。

所以我们需要：

```text
ROM
 ┌─────────────────────┐
 │ .text               │
 │ .rodata             │
 │ .data initial value │
 └─────────────────────┘

RAM
 ┌─────────────────────┐
 │ .data               │ ← 启动时从 ROM 拷贝
 │ .bss                │ ← 清零
 └─────────────────────┘
```

这就是：

```text
VMA ≠ LMA
```

---

# 二十五、修改 linker script

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
        *(.text.start)
        *(.text)
    } > ROM

    .rodata :
    {
        *(.rodata*)
    } > ROM

    .data :
    {
        __data_start = .;

        *(.data)

        __data_end = .;
    } > RAM AT > ROM

    .bss (NOLOAD) :
    {
        __bss_start = .;

        *(.bss)
        *(COMMON)

        __bss_end = .;
    } > RAM
}
```

这里出现：

```ld
> RAM AT > ROM
```

这是整个 GNU ld 实战课程的一个大坎。

---

# 二十六、`> RAM AT > ROM` 到底是什么意思？

拆开：

```ld
.data
{
    ...
}
> RAM
```

表示：

```text
VMA → RAM
```

再加：

```ld
AT > ROM
```

表示：

```text
LMA → ROM
```

所以：

```text
.data

VMA = RAM
LMA = ROM
```

GNU ld 文档明确区分 Output Section 的 VMA 和 LMA；`AT>` 可以指定 LMA 所在的 MEMORY Region。[Sourceware](https://sourceware.org/binutils/docs/ld.pdf?utm_source=chatgpt.com)

---

# 二十七、这是整个 linker 学习中必须形成的思维模型

以后看到：

```ld
.data > RAM AT > ROM
```

不要读成：

> “data 放 RAM 和 ROM。”

应该读成：

```text
.data
   │
   ├── 运行地址 VMA
   │       ↓
   │      RAM
   │
   └── 镜像地址 LMA
           ↓
          ROM
```

也就是：

```text
运行：
RAM

保存：
ROM
```

---

# 二十八、重新链接

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    -o memory-data.elf \
    -Map=memory-data.map
```

---

# 二十九、readelf：第一次同时看 VMA/LMA

执行：

```bash
readelf -SW memory-data.elf
```

你需要重点关注 `.data`。

然后：

```bash
objdump -h memory-data.elf
```

通常会看到：

```text
.data
  VMA   0x00600000
  LMA   0x004000xx
```

这里：

```text
VMA
=
RAM
```

而：

```text
LMA
=
ROM
```

---

# 三十、为什么 `objdump -h` 特别适合这个实验？

因为它把：

```text
Size
VMA
LMA
File off
```

集中显示出来。

所以这一阶段建立一个固定习惯：

```bash
objdump -h xxx.elf
```

看到：

```text
Name
Size
VMA
LMA
File off
Algn
```

就开始思考：

```text
这个 Section：

在哪里运行？
在哪里加载？
在 ELF 文件哪个 offset？
```

这三个问题是以后分析 firmware linker script 的核心。

---

# 三十一、Map 文件分析

执行：

```bash
grep -A30 -B3 '\.data' memory-data.map
```

你会看到类似：

```text
.data           0x0000000000600000
                0x0000000000600000 __data_start = .

 *(.data)
 .data          0x0000000000600000 ...
                0x0000000000600004 __data_end = .
```

但是 Map 中还可能显示 Load Address。

你真正需要建立的是：

```text
.data

VMA:
0x00600000

LMA:
0x004000xx
```

---

# 三十二、实验 35-7：`LOADADDR()`

现在我们让 linker 自己生成：

```text
.data 的 LMA
```

加入：

```ld
PROVIDE(__data_load = LOADADDR(.data));
PROVIDE(__data_size = SIZEOF(.data));
```

完整：

```ld
ENTRY(_start)

MEMORY
{
    ROM (rx)  : ORIGIN = 0x00400000, LENGTH = 64K
    RAM (rwx) : ORIGIN = 0x00600000, LENGTH = 64K
}

PROVIDE(__rom_start = ORIGIN(ROM));
PROVIDE(__rom_end   = ORIGIN(ROM) + LENGTH(ROM));

SECTIONS
{
    .text :
    {
        *(.text.start)
        *(.text)
    } > ROM

    .rodata :
    {
        *(.rodata*)
    } > ROM

    .data :
    {
        __data_start = .;

        *(.data)

        __data_end = .;
    } > RAM AT > ROM

    .bss (NOLOAD) :
    {
        __bss_start = .;

        *(.bss)
        *(COMMON)

        __bss_end = .;
    } > RAM
}

PROVIDE(__data_load = LOADADDR(.data));
PROVIDE(__data_size = SIZEOF(.data));
```

---

# 三十三、为什么 `LOADADDR()` 特别重要？

因为：

```text
.data 的 `.`
```

表示的是：

```text
VMA
```

而：

```ld
LOADADDR(.data)
```

拿到的是：

```text
LMA
```

官方文档的例子也使用：

```ld
LOADADDR(.text1)
```

等表达式取得 Section 的加载地址。[Sourceware](https://sourceware.org/binutils/docs-2.38/ld.pdf?utm_source=chatgpt.com)

---

# 三十四、现在可以形成一个非常漂亮的启动代码模型

以后 MCU startup code 经常就是：

```c
extern char __data_load[];
extern char __data_start[];
extern char __data_end[];

memcpy(
    __data_start,
    __data_load,
    __data_end - __data_start
);
```

即：

```text
ROM
 │
 │ __data_load
 │
 ▼
┌────────────────┐
│ 42  100  200   │
└────────────────┘
        │
        │ memcpy
        ▼
RAM
 │
 │ __data_start
 ▼
┌────────────────┐
│ 42  100  200   │
└────────────────┘
```

这就是：

> **Linker Script + Startup Code**

第一次真正结合起来。

---

# 三十五、实验 35-8：`REGION_ALIAS`

现在进入一个很有意思的功能。

假设我们的代码写成：

```ld
.text > ROM
.data > RAM
```

那么：

```text
ROM
RAM
```

直接绑定在 linker script 中。

但是实际工程可能有：

```text
开发板 A：

FLASH
SRAM
```

开发板 B：

```text
QSPI
SRAM
```

开发板 C：

```text
ITCM
DTCM
```

如果每个 Section 都硬编码：

```ld
.text > ROM
.data > RAM
```

维护起来会很麻烦。

于是 GNU ld 提供：

```ld
REGION_ALIAS
```

---

# 三十六、定义别名

```ld
MEMORY
{
    FLASH (rx)  : ORIGIN = 0x00400000, LENGTH = 64K
    SRAM  (rwx) : ORIGIN = 0x00600000, LENGTH = 64K
}

REGION_ALIAS("REGION_TEXT", FLASH);
REGION_ALIAS("REGION_DATA", SRAM);
```

然后：

```ld
.text :
{
    *(.text*)
} > REGION_TEXT

.data :
{
    *(.data*)
} > REGION_DATA
```

于是：

```text
REGION_TEXT
      │
      ▼
    FLASH

REGION_DATA
      │
      ▼
    SRAM
```

---

# 三十七、为什么 `REGION_ALIAS` 很有价值？

可以把 linker script 设计成：

```text
逻辑区域
   │
   ├── REGION_TEXT
   ├── REGION_RODATA
   ├── REGION_DATA
   └── REGION_BSS
          │
          ▼
物理 Memory Region
   │
   ├── FLASH
   ├── SRAM
   ├── ITCM
   └── DTCM
```

这样：

```text
Section Layout
```

和：

```text
Hardware Memory Layout
```

开始解耦。

GNU ld 文档也明确说明，`REGION_ALIAS(alias, region)` 可以为已有 Memory Region 添加别名。[Sourceware](https://sourceware.org/binutils/docs-2.38/ld.pdf?utm_source=chatgpt.com)

---

# 三十八、实验 35-9：综合 ROM/RAM Image

现在把前面全部东西组合起来。

最终 linker：

```ld
ENTRY(_start)

MEMORY
{
    FLASH (rx)  : ORIGIN = 0x00400000, LENGTH = 64K
    SRAM  (rwx) : ORIGIN = 0x00600000, LENGTH = 64K
}

REGION_ALIAS("REGION_TEXT", FLASH);
REGION_ALIAS("REGION_RODATA", FLASH);
REGION_ALIAS("REGION_DATA", SRAM);
REGION_ALIAS("REGION_BSS", SRAM);

PROVIDE(__flash_start = ORIGIN(FLASH));
PROVIDE(__flash_end   = ORIGIN(FLASH) + LENGTH(FLASH));

PROVIDE(__ram_start = ORIGIN(SRAM));
PROVIDE(__ram_end   = ORIGIN(SRAM) + LENGTH(SRAM));

SECTIONS
{
    .text :
    {
        . = ALIGN(16);

        __text_start = .;

        *(.text.start)
        *(.text*)

        __text_end = .;
    } > REGION_TEXT

    .rodata :
    {
        . = ALIGN(16);

        __rodata_start = .;

        *(.rodata*)

        __rodata_end = .;
    } > REGION_RODATA

    .data :
    {
        . = ALIGN(16);

        __data_start = .;

        *(.data*)

        __data_end = .;
    } > REGION_DATA AT > REGION_TEXT

    .bss (NOLOAD) :
    {
        . = ALIGN(16);

        __bss_start = .;

        *(.bss*)
        *(COMMON)

        __bss_end = .;
    } > REGION_BSS
}

PROVIDE(__data_load = LOADADDR(.data));
PROVIDE(__data_size = SIZEOF(.data));
PROVIDE(__bss_size = SIZEOF(.bss));
```

这里特意保持我们前面课程纠正过的 `ALIGN()` 写法：

```ld
.text :
{
    . = ALIGN(16);
```

而不是错误地写：

```ld
.text ALIGN(16) :
```

这一点继续保持。

---

# 三十九、最终编译

```bash
gcc -ffreestanding -c start.S main.c
```

然后：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    -o firmware.elf \
    -Map=firmware.map
```

---

# 四十、第一轮验证：Section

```bash
readelf -SW firmware.elf
```

重点观察：

```text
.text
.rodata
.data
.bss
```

预期：

```text
.text
VMA ≈ 0x00400000

.rodata
VMA ≈ 0x0040....

.data
VMA ≈ 0x00600000

.bss
VMA > 0x00600000
```

---

# 四十一、第二轮验证：VMA/LMA

```bash
objdump -h firmware.elf
```

重点看：

```text
.text
.rodata
.data
.bss
```

形成：

```text
             VMA             LMA

.text        FLASH           FLASH

.rodata      FLASH           FLASH

.data        SRAM            FLASH

.bss         SRAM            不需要 ROM 镜像
```

这张表以后建议你直接记住：

| Section | VMA | LMA |
|---|---|---|
| `.text` | FLASH | FLASH |
| `.rodata` | FLASH | FLASH |
| `.data` | SRAM | FLASH |
| `.bss` | SRAM | 无需初始化镜像 |

---

# 四十二、第三轮验证：Symbol

```bash
nm -n firmware.elf
```

寻找：

```text
__flash_start
__flash_end

__ram_start
__ram_end

__text_start
__text_end

__data_start
__data_end
__data_load

__bss_start
__bss_end
```

这时候你已经可以通过 Symbol 反推出完整内存布局。

---

# 四十三、第四轮验证：Map

执行：

```bash
grep -E \
'(\.text|\.rodata|\.data|\.bss|__data_load|__flash_|__ram_)' \
firmware.map
```

Map 文件应该成为你的“总账”。

可以看到：

```text
FLASH
 ├── .text
 ├── .rodata
 └── .data LMA

SRAM
 ├── .data VMA
 └── .bss
```

---

# 四十四、这一次一定要学会区分三种地址

现在已经不能只说：

> “`.data` 在 0x00600000。”

因为这句话不完整。

正确说法应该是：

```text
.data

VMA:
0x00600000

LMA:
0x0040xxxx

ELF file offset:
某个 file offset
```

也就是说，一个 Section 至少存在三个非常重要的定位维度：

```text
        ELF File
           │
       File Offset
           │
           ▼
       Load Image
           │
           │
           ▼
          LMA
           │
           │ startup copy
           ▼
          VMA
           │
           ▼
       Runtime RAM
```

---

# 四十五、这也解释了你之前遇到的错误

之前你遇到过：

```text
address ... of section `.text'
is not within region `ROM'
```

现在可以从三个层次分析：

### 第一层

`.text` 的 VMA 到底是多少？

```bash
readelf -SW xxx.elf
```

### 第二层

它被分配到了哪个 MEMORY Region？

看：

```ld
.text > ROM
```

### 第三层

ROM 到底是什么？

```ld
MEMORY
{
    ROM : ORIGIN = ..., LENGTH = ...
}
```

所以最终形成：

```text
Section
  ↓
Output Section Address
  ↓
Memory Region
  ↓
ORIGIN
  ↓
LENGTH
```

如果任何一层不一致，就可能出现：

```text
not within region
```

---

# 四十六、再进一步：用 `ASSERT()` 给 Memory Layout 加保险

下一步我们马上就会进入你之前已经做过的：

```text
ASSERT()
```

现在可以提前看到它为什么非常适合 Memory Layout。

例如：

```ld
ASSERT(
    __data_end <= ORIGIN(SRAM) + LENGTH(SRAM),
    "ERROR: .data overflow SRAM"
);
```

或者：

```ld
ASSERT(
    __bss_end <= ORIGIN(SRAM) + LENGTH(SRAM),
    "ERROR: RAM overflow"
);
```

于是：

```text
MEMORY
   ↓
Section placement
   ↓
Symbol
   ↓
ASSERT
```

就形成了一个完整的：

> **Link-time Memory Safety Check**

---

# 四十七、本节最重要的知识图

到这里，你应该把 GNU ld 的内存模型理解成：

```text
                         MEMORY
                           │
             ┌─────────────┴─────────────┐
             │                           │
           FLASH                        SRAM
             │                           │
       ORIGIN/LENGTH              ORIGIN/LENGTH
             │                           │
             ▼                           ▼
       REGION_TEXT                 REGION_DATA
             │                           │
             ▼                           ▼
           .text                       .data
           .rodata                     .bss
             │                           │
             │                           │
             └──────────────┬────────────┘
                            │
                          ELF
                            │
                  ┌─────────┴─────────┐
                  │                   │
                 VMA                 LMA
                  │                   │
               Runtime            Load Image
```

而：

```text
.data > SRAM AT > FLASH
```

就是整个模型的核心表达式。

---

# 四十八、现在回头理解 `MEMORY` 的属性

我们写：

```ld
FLASH (rx)
SRAM  (rwx)
```

这些：

```text
r
w
x
```

不是简单装饰。

它们描述 Memory Region 的属性，尤其会影响 ld 对**没有显式映射的 Output Section** 的默认区域选择。GNU ld 文档明确说明，Memory Region 的属性可以帮助 linker 为未显式映射的 Output Section 选择兼容区域。[Sourceware](https://sourceware.org/binutils/docs-2.38/ld.pdf?utm_source=chatgpt.com)

所以：

```text
FLASH (rx)
```

可以理解成：

```text
read
execute
```

而：

```text
SRAM (rwx)
```

表示：

```text
read
write
execute
```

当然，实际硬件 MPU/MMU 权限最终还要看目标平台和 Program Header；不要把 linker script 中的 `(rx)` 直接等同于 CPU 最终页权限。

这点会在 **实验 36：PHDRS + Segment** 中彻底展开。

---

# 四十九、本节实验检查表

建议你实际执行下面这一整套：

```bash
# 1. 编译
gcc -ffreestanding -c start.S main.c

# 2. 链接
ld \
    -T linker.ld \
    start.o \
    main.o \
    -o firmware.elf \
    -Map=firmware.map

# 3. Section
readelf -SW firmware.elf

# 4. Section header
objdump -h firmware.elf

# 5. Symbol
nm -n firmware.elf

# 6. Map
less firmware.map

# 7. 找关键区域
grep -E '\.text|\.rodata|\.data|\.bss' firmware.map

# 8. 看 .data
objdump -s -j .data firmware.elf
```

---

# 五十、到这里，你已经跨过一个很重要的门槛

前面：

```text
实验 01～34
```

主要是在学习：

```text
Input Section
       ↓
Output Section
       ↓
Symbol
       ↓
Section Sorting
       ↓
KEEP
       ↓
GC
       ↓
ASSERT
```

而从今天开始：

```text
实验 35+
```

进入：

```text
Memory
  ↓
VMA
  ↓
LMA
  ↓
ROM/RAM
  ↓
Load Image
  ↓
Program Header
  ↓
Segment
  ↓
Firmware Image
```

这是从“会写 linker script”走向“能设计启动镜像”的分界线。

---

# 五十一、下一节：实验 36 —— `PHDRS` 真正登场

下一节我们会直接解决一个特别容易混淆的问题：

```text
Section ≠ Segment
```

我们将构造：

```text
ELF
│
├── ELF Header
│
├── Program Header Table
│
├── LOAD Segment 0
│      ├── .text
│      └── .rodata
│
├── LOAD Segment 1
│      └── .data
│
└── LOAD Segment 2
       └── .bss
```

然后自己写：

```ld
PHDRS
{
    text PT_LOAD FLAGS(5);
    data PT_LOAD FLAGS(6);
}
```

再用：

```bash
readelf -l firmware.elf
```

对比：

```bash
readelf -SW firmware.elf
```

真正看清楚：

```text
Section
   ↓
Segment
   ↓
Program Header
   ↓
Loader
```

并且会把你之前实验中遇到的：

```text
section '.bss' can't be allocated in segment
LOAD segment with RWX permissions
PHDRS
FILEHDR
PHDRS
AT()
```

串成一条完整的逻辑链。

这会是 GNU ld 实战课程从 **“Section 世界”进入“ELF Loader 世界”** 的下一大关。
