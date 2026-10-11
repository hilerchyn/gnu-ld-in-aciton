继续。上一节已经把 **VMA/LMA → `AT()` → `PT_LOAD` → `p_filesz/p_memsz` → `.bss/NOBITS`** 串起来了。现在进入下一层，也是 GNU ld 里非常容易出现“明明只放了几个字节，ELF 却突然变得很大”的地方。

# GNU ld 实战课程 · 实验 39

# 多 `PT_LOAD` + Segment 边界 + `p_align` + `MAXPAGESIZE`

本节核心不是再学一个孤立命令，而是搞清楚：

> **为什么两个 Segment 之间会出现巨大的空洞？**
>
> **`p_align` 到底是谁决定的？**
>
> **为什么 `.text` 明明只有几十字节，`.data` 却可能突然跑到 `0x200000` 之后？**
>
> **`MAXPAGESIZE`、`ALIGN()`、`p_offset`、`p_vaddr` 之间到底是什么关系？**

GNU ld 文档说明，Program Header 描述 Loader 如何加载 ELF；`PHDRS` 可以精确控制这些 Segment，而 `PT_LOAD` 是实际需要加载的 Segment 类型。[Sourceware](https://sourceware.org/binutils/docs/ld.pdf?utm_source=chatgpt.com)

---

# 一、本实验最终要得到的模型

最终我们要理解：

```text
                         ELF
                          │
              ┌───────────┴───────────┐
              │                       │
          PT_LOAD #1              PT_LOAD #2
             R-X                      RW
              │                       │
           .text                    .data
           .rodata                  .bss
              │                       │
              │                       │
              └─────── gap ──────────┘
                       ↑
                  page alignment
                       ↑
                  p_align / MAXPAGESIZE
```

关键关系：

```text
p_offset
p_vaddr
p_align
```

对于可加载 Segment，需要满足相应的 ELF 对齐约束；实际 Segment 的对齐要求可以直接从：

```bash
readelf -lW
```

里的：

```text
Align
```

观察。

---

# 二、实验 39 的递进路线

这一次仍然不一次把所有东西塞进去。

```text
39-1  两个 PT_LOAD，观察默认布局
  ↓
39-2  手动制造 Segment 边界
  ↓
39-3  观察 p_align
  ↓
39-4  查看 MAXPAGESIZE
  ↓
39-5  ALIGN(CONSTANT(MAXPAGESIZE))
  ↓
39-6  观察巨大的文件空洞
  ↓
39-7  -z max-page-size
  ↓
39-8  比较 2 MiB 与 4 KiB
  ↓
39-9  Map + readelf + objdump 三重验证
  ↓
39-10 建立“Segment 为什么会膨胀”的完整模型
```

---

# 三、实验目录

建立：

```text
39-segment-align/
├── start.S
├── main.c
├── data.c
├── linker39.ld
└── Makefile
```

这一次我们把 `.text`、`.rodata`、`.data`、`.bss` 的来源故意分开，方便观察 Map 文件。

---

# 四、源码

## 1. `start.S`

```asm
.global _start

.section .text.start

_start:
    call main

1:
    jmp 1b
```

---

# 五、`main.c`

```c
extern int initialized;
extern int uninitialized;

extern const char message[];

int main(void)
{
    initialized++;
    uninitialized = initialized;

    return message[0];
}
```

---

# 六、`data.c`

```c
int initialized = 0x12345678;

int uninitialized;

const char message[] =
    "GNU ld segment alignment experiment";
```

这样：

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

---

# 七、编译

建议：

```bash
gcc \
    -ffreestanding \
    -fno-pie \
    -fno-asynchronous-unwind-tables \
    -c start.S main.c data.c
```

得到：

```text
start.o
main.o
data.o
```

---

# 八、先看看目标文件

执行：

```bash
readelf -SW data.o
```

以及：

```bash
objdump -h data.o
```

你应该能看到：

```text
.text
.data
.bss
.rodata
```

注意：

> 这时候还没有 Segment。

因为：

```text
.o
```

主要还是 Section 世界。

---

# 九、实验 39-1：最基本的三个 PT_LOAD

建立：

```text
linker39-1.ld
```

内容：

```ld
ENTRY(_start)

MEMORY
{
    FLASH (rx)  : ORIGIN = 0x00400000, LENGTH = 8M
    SRAM  (rw)  : ORIGIN = 0x00600000, LENGTH = 8M
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

---

# 十、链接

```bash
ld \
    -T linker39-1.ld \
    start.o \
    main.o \
    data.o \
    -o seg39-1.elf \
    -Map=seg39-1.map
```

---

# 十一、第一次看 Segment

执行：

```bash
readelf -lW seg39-1.elf
```

重点看：

```text
Program Headers:

Type   Offset   VirtAddr   PhysAddr   FileSiz   MemSiz   Flg   Align
```

以及：

```text
Section to Segment mapping
```

理想情况下，你会看到类似：

```text
LOAD
R E
.text

LOAD
R
.rodata

LOAD
RW
.data
.bss
```

但是：

> **不要死记这里的 Offset 和 Align 数值。**

它们与：

- target architecture
- ld emulation
- binutils 版本
- 默认最大页大小

都有关系。

---

# 十二、现在关注一个新字段：`Align`

例如：

```text
LOAD  ...  R E  0x1000
LOAD  ...  R    0x1000
LOAD  ...  RW   0x1000
```

最后：

```text
0x1000
```

就是：

```text
p_align
```

它不是：

```text
Section alignment
```

而是：

> **Segment 的对齐要求。**

这两个概念一定要分开。

---

# 十三、Section Alignment 和 Segment Alignment

例如：

```ld
.text :
{
    . = ALIGN(16);
    *(.text*)
}
```

这里：

```text
ALIGN(16)
```

影响的是：

```text
.text
```

Section 内部布局。

而：

```text
readelf -lW
```

里面：

```text
Align
```

是：

```text
PT_LOAD.p_align
```

属于 Segment 层。

因此：

```text
Section Alignment
        ≠
Segment Alignment
```

这是本节第一个重要结论。

---

# 十四、实验 39-2：人为制造一个 Segment 边界

现在修改：

```text
linker39-2.ld
```

重点改：

```ld
.rodata :
{
    . = ALIGN(16);

    *(.rodata*)
} > FLASH :ro

. = ALIGN(0x1000);

.data :
{
    . = ALIGN(16);

    *(.data*)
} > SRAM AT > FLASH :data
```

这里：

```ld
. = ALIGN(0x1000);
```

表示：

> 把当前地址推进到下一个 4 KiB 边界。

---

# 十五、但是这里马上出现一个重要问题

注意：

```ld
.data > SRAM AT > FLASH
```

`.data` 的：

```text
VMA → SRAM
LMA → FLASH
```

因此：

```ld
. = ALIGN(0x1000);
```

究竟影响的是：

```text
VMA？
LMA？
```

这就开始进入 linker script 最容易混淆的地方：

> **Location Counter 操作与 LMA 分配不是同一个维度。**

所以不要简单认为：

```ld
. = ALIGN(...)
```

就是：

```text
“把 FLASH 镜像也对齐了”
```

真正结果必须用：

```bash
objdump -h
readelf -lW
```

验证。

---

# 十六、重新链接

```bash
ld \
    -T linker39-2.ld \
    start.o \
    main.o \
    data.o \
    -o seg39-2.elf \
    -Map=seg39-2.map
```

检查：

```bash
objdump -h seg39-2.elf
```

然后：

```bash
readelf -lW seg39-2.elf
```

最后：

```bash
grep -A20 "Memory Configuration" seg39-2.map
```

以及：

```bash
grep -A20 "\.data" seg39-2.map
```

---

# 十七、实验 39-3：真正研究 `MAXPAGESIZE`

现在我们暂时不修改 linker script。

直接询问 GNU ld 当前 target 的默认 linker script：

```bash
ld --verbose
```

输出很长，可以：

```bash
ld --verbose | grep -i MAXPAGESIZE
```

某些 GNU ld 版本会看到类似：

```text
MAXPAGESIZE = CONSTANT (MAXPAGESIZE)
```

或者在默认 linker script 中看到：

```ld
ALIGN(CONSTANT (MAXPAGESIZE))
```

注意：

> **具体 `MAXPAGESIZE` 数值不是所有平台都一样。**

例如某些 x86-64 GNU ld 配置通常采用：

```text
0x200000
```

也就是：

```text
2 MiB
```

而其它目标可能使用：

```text
0x1000
```

也就是：

```text
4 KiB
```

因此课程里不要写死：

```text
MAXPAGESIZE = 0x200000
```

应该先查询当前工具链。

---

# 十八、一个非常有价值的命令

执行：

```bash
ld --verbose > default-linker-script.txt
```

然后：

```bash
grep -n "MAXPAGESIZE" default-linker-script.txt
```

再：

```bash
grep -n "CONSTANT" default-linker-script.txt
```

你实际上是在偷看：

> **GNU ld 默认 linker script 是怎么处理 Segment 对齐的。**

这是学习 GNU ld 非常重要的技巧。

---

# 十九、实验 39-4：手动使用 `MAXPAGESIZE`

现在创建：

```text
linker39-maxpage.ld
```

核心：

```ld
ENTRY(_start)

MEMORY
{
    FLASH (rx)  : ORIGIN = 0x00400000, LENGTH = 16M
    SRAM  (rw)  : ORIGIN = 0x00600000, LENGTH = 16M
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
        *(.text.start)
        *(.text*)
    } > FLASH :text

    .rodata :
    {
        . = ALIGN(16);
        *(.rodata*)
    } > FLASH :ro

    /*
     * 强制新的 Segment 边界
     */
    . = ALIGN(CONSTANT (MAXPAGESIZE));

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

这里是本节第一个真正重要的新语法：

```ld
ALIGN(CONSTANT (MAXPAGESIZE))
```

---

# 二十、为什么写 `CONSTANT (MAXPAGESIZE)`？

GNU ld linker script 中：

```text
MAXPAGESIZE
```

是一个与目标相关的 linker 常量。

通过：

```ld
CONSTANT (MAXPAGESIZE)
```

读取它。

因此：

```ld
ALIGN(CONSTANT (MAXPAGESIZE))
```

表示：

> 按当前 target 的最大页面大小进行对齐。

GNU ld 官方文档的默认脚本示例也会使用 `SIZEOF_HEADERS`、`PHDRS` 等机制来控制 ELF Program Header 布局。[Sourceware](https://sourceware.org/binutils/docs-2.43/ld.pdf?utm_source=chatgpt.com)

---

# 二十一、重新链接

```bash
ld \
    -T linker39-maxpage.ld \
    start.o \
    main.o \
    data.o \
    -o maxpage.elf \
    -Map=maxpage.map
```

---

# 二十二、马上做三个检查

### ① Segment

```bash
readelf -lW maxpage.elf
```

### ② Section

```bash
readelf -SW maxpage.elf
```

### ③ VMA/LMA

```bash
objdump -h maxpage.elf
```

---

# 二十三、重点观察 `.data`

例如你的环境如果：

```text
MAXPAGESIZE = 0x200000
```

那么可能出现：

```text
.text
0x00400000 ...

.rodata
0x00400...

<data boundary>

.data
0x00600000 ...
```

这时候你可能突然发现：

```text
File offset
```

和：

```text
VMA
```

之间出现了很大的距离。

这就是：

# Segment alignment 带来的空洞

---

# 二十四、什么叫“文件空洞”？

假设：

```text
.text
文件 offset = 0x000000
大小 = 0x100
```

下一个 Segment 因为要求：

```text
p_align = 0x200000
```

所以必须从：

```text
0x200000
```

附近开始。

于是：

```text
0x000000
┌───────────────┐
│ ELF + .text   │
└───────────────┘
        │
        │
        │   大量未使用空间
        │
        ▼
0x200000
┌───────────────┐
│ .data         │
└───────────────┘
```

这就是所谓：

```text
padding / hole
```

---

# 二十五、但是要特别注意：空洞不一定真的占用磁盘空间

这里非常容易误解。

如果 ELF 文件中这段区域只是：

```text
seeked hole
```

那么：

```text
st_size
```

可能很大，

但：

```text
实际磁盘 blocks
```

并不一定同样大。

使用：

```bash
ls -lh maxpage.elf
```

看逻辑文件大小。

再：

```bash
du -h maxpage.elf
```

看实际占用空间。

这两个值可能不同。

---

# 二十六、实验 39-5：证明文件真的出现大间隙

执行：

```bash
ls -lh maxpage.elf
```

然后：

```bash
du -h maxpage.elf
```

再：

```bash
readelf -lW maxpage.elf
```

比较：

```text
LOAD #1
Offset
FileSiz

LOAD #2
Offset
FileSiz
```

计算：

```text
第二个 Segment Offset
-
第一个 Segment 结束 Offset
```

这个差值就是：

```text
Segment 间文件布局间隙
```

---

# 二十七、Map 文件再验证

执行：

```bash
grep -n -A15 -B5 "\.text" maxpage.map
```

然后：

```bash
grep -n -A15 -B5 "\.data" maxpage.map
```

你会看到：

```text
.text
...
.rodata
...
.data
```

地址之间可能突然跳得非常大。

这时候不要只看 Map。

一定要同时看：

```bash
readelf -lW maxpage.elf
```

因为：

> Map 主要告诉你 Section 布局；Segment 的对齐与文件 Offset 要以 Program Header 为核心验证。

---

# 二十八、实验 39-6：真正理解 `p_align`

执行：

```bash
readelf -lW maxpage.elf
```

例如可能出现：

```text
Type   Offset      VirtAddr    PhysAddr
LOAD   0x000000    0x00400000  0x00400000
       ...
       Align 0x200000

LOAD   0x200000    0x00600000  0x004xxxxx
       ...
       Align 0x200000
```

这里：

```text
Align = 0x200000
```

就是：

```text
p_align
```

---

# 二十九、为什么 Segment 要这么大对齐？

ELF Loader 通常希望：

```text
p_offset
```

与：

```text
p_vaddr
```

满足：

```text
p_offset ≡ p_vaddr (mod p_align)
```

例如：

```text
p_align = 0x1000
```

那么：

```text
p_offset % 0x1000
=
p_vaddr % 0x1000
```

如果：

```text
p_align = 0x200000
```

则对应：

```text
p_offset % 0x200000
=
p_vaddr % 0x200000
```

因此 Segment 边界可能被强制推到：

```text
0x200000
```

边界。

---

# 三十、这就是为什么：

```ld
ALIGN(16)
```

与：

```ld
ALIGN(CONSTANT(MAXPAGESIZE))
```

差别巨大。

前者：

```text
16 bytes
```

主要解决 Section 内部布局。

后者可能：

```text
4 KiB
64 KiB
2 MiB
...
```

影响的是：

```text
Segment / page mapping
```

所以一定不要把两者混为一谈。

---

# 三十一、实验 39-7：用 `-z max-page-size` 控制最大页面大小

现在进入一个非常实用的技巧。

先执行：

```bash
ld \
    -T linker39-maxpage.ld \
    start.o \
    main.o \
    data.o \
    -o maxpage-default.elf \
    -Map=maxpage-default.map
```

然后再执行：

```bash
ld \
    -z max-page-size=0x1000 \
    -T linker39-maxpage.ld \
    start.o \
    main.o \
    data.o \
    -o maxpage-4k.elf \
    -Map=maxpage-4k.map
```

---

# 三十二、两个 ELF 对比

执行：

```bash
readelf -lW maxpage-default.elf
```

再：

```bash
readelf -lW maxpage-4k.elf
```

重点比较：

```text
Offset
VirtAddr
PhysAddr
FileSiz
MemSiz
Align
```

尤其：

```text
Align
```

---

# 三十三、再比较文件大小

```bash
ls -lh maxpage-default.elf
ls -lh maxpage-4k.elf
```

然后：

```bash
du -h maxpage-default.elf
du -h maxpage-4k.elf
```

如果当前 target 默认：

```text
MAXPAGESIZE = 0x200000
```

而你指定：

```text
-z max-page-size=0x1000
```

那么 Segment 边界可能从：

```text
2 MiB
```

下降到：

```text
4 KiB
```

文件布局中的大间隙也可能明显缩小。

---

# 三十四、但有一个非常重要的注意事项

不要把：

```bash
-z max-page-size=0x1000
```

理解成：

> “无条件把所有 Segment 的 `p_align` 改成 4 KiB。”

实际结果仍然取决于：

- target
- linker script
- Segment 布局
- ABI
- ld emulation
- 其它对齐约束

所以正确的验证方式永远是：

```bash
readelf -lW xxx.elf
```

而不是：

> “我指定了 0x1000，所以肯定就是 0x1000。”

---

# 三十五、实验 39-8：做一个“巨大空洞”的对照组

创建：

```text
linker39-hole.ld
```

核心：

```ld
SECTIONS
{
    . = ORIGIN(FLASH) + SIZEOF_HEADERS;

    .text :
    {
        *(.text*)
    } > FLASH :text

    .rodata :
    {
        *(.rodata*)
    } > FLASH :ro

    /*
     * 故意制造 Segment 边界
     */
    . = ALIGN(CONSTANT (MAXPAGESIZE));

    .data :
    {
        *(.data*)
    } > SRAM AT > FLASH :data

    .bss (NOLOAD) :
    {
        *(.bss*)
        *(COMMON)
    } > SRAM :data
}
```

---

# 三十六、编译两个版本

### 默认 max page size

```bash
ld \
    -T linker39-hole.ld \
    start.o \
    main.o \
    data.o \
    -o hole-default.elf \
    -Map=hole-default.map
```

### 4 KiB

```bash
ld \
    -z max-page-size=0x1000 \
    -T linker39-hole.ld \
    start.o \
    main.o \
    data.o \
    -o hole-4k.elf \
    -Map=hole-4k.map
```

---

# 三十七、用 `readelf` 进行定量比较

```bash
readelf -lW hole-default.elf
```

以及：

```bash
readelf -lW hole-4k.elf
```

可以把：

```text
LOAD #1
```

和：

```text
LOAD #2
```

的：

```text
Offset
```

记下来。

计算：

```text
gap =
LOAD2.p_offset
-
(LOAD1.p_offset + LOAD1.p_filesz)
```

这个值就是：

> 两个 Segment 之间文件内容没有实际 Section 数据覆盖的间隔。

---

# 三十八、用 Python 计算会更直观

例如从 `readelf` 得到：

```text
LOAD1:
offset = 0x000000
filesz = 0x1000

LOAD2:
offset = 0x200000
```

那么：

```text
gap
=
0x200000
-
0x1000
=
0x1ff000
```

也就是：

```text
2 MiB - 4 KiB
```

绝大部分文件地址空间都没有实际 Section 内容。

---

# 三十九、Map 文件怎么看这个问题？

这里非常值得注意：

```text
map
```

可能看起来：

```text
.text       0x004000e8
.rodata     0x00400120
.data       0x00600000
```

你看到：

```text
0x00400120
        ↓
0x00600000
```

会觉得：

> “为什么 `.data` 跑这么远？”

Map 已经告诉你：

```text
.data VMA
```

但它不能单独解释：

> 为什么 ELF 文件 Offset 也产生了巨大的间隔？

这时候必须：

```bash
readelf -lW
```

因为真正原因在：

```text
PT_LOAD
p_offset
p_vaddr
p_align
```

---

# 四十、实验 39-9：三个视角联合分析

以后看到这种问题，固定做：

## 视角一：Map

```bash
grep -A15 -B5 "\.data" hole-default.map
```

回答：

```text
.data 的 Section 地址是多少？
```

---

## 视角二：Section

```bash
objdump -h hole-default.elf
```

回答：

```text
VMA
LMA
File offset
Size
```

---

## 视角三：Segment

```bash
readelf -lW hole-default.elf
```

回答：

```text
p_offset
p_vaddr
p_paddr
p_filesz
p_memsz
p_align
```

三个工具必须串起来。

---

# 四十一、实验 39-10：自己验证 `p_offset % p_align`

现在拿 `readelf -lW` 中的数据。

例如：

```text
p_offset = 0x200000
p_vaddr  = 0x00600000
p_align  = 0x200000
```

计算：

```text
0x200000 % 0x200000 = 0
```

以及：

```text
0x600000 % 0x200000 = 0
```

所以：

```text
p_offset % p_align
=
p_vaddr % p_align
```

---

# 四十二、再做一个非零余数的例子

假设：

```text
p_align = 0x1000

p_offset = 0x2100
p_vaddr  = 0x602100
```

那么：

```text
0x2100 % 0x1000
=
0x100
```

而：

```text
0x602100 % 0x1000
=
0x100
```

同样满足：

```text
p_offset ≡ p_vaddr (mod p_align)
```

所以不要机械地认为：

```text
p_offset
```

一定是：

```text
p_align
```

的整数倍。

真正重要的是：

```text
两者的模相等。
```

---

# 四十三、实验 39-11：为什么 `MAXPAGESIZE` 会影响文件大小？

现在把因果关系完整写出来：

```text
MAXPAGESIZE
      │
      ▼
Segment Alignment
      │
      ▼
p_align
      │
      ▼
p_offset / p_vaddr 对齐约束
      │
      ▼
Segment 起始位置
      │
      ▼
Segment 之间产生 padding
      │
      ▼
ELF 文件可能变大
```

所以：

> **不是 `MAXPAGESIZE` 本身把 ELF 文件变大。**

而是：

```text
MAXPAGESIZE
    ↓
Segment alignment
    ↓
为了满足对齐
    ↓
产生 padding / hole
```

---

# 四十四、一个非常重要的区分

现在比较：

```ld
. = ALIGN(0x1000);
```

与：

```ld
. = ALIGN(CONSTANT (MAXPAGESIZE));
```

第一种：

```text
固定 4 KiB
```

第二种：

```text
使用 target 的最大页大小
```

因此：

```text
ALIGN(0x1000)
```

是：

> 我明确要求 4 KiB。

而：

```text
ALIGN(CONSTANT(MAXPAGESIZE))
```

是：

> 我要求按照当前 target 的最大页面大小进行布局。

---

# 四十五、实验 39-12：观察默认 linker script

这个实验我强烈建议你实际做。

执行：

```bash
ld --verbose > default.ld.txt
```

然后：

```bash
grep -n "MAXPAGESIZE" default.ld.txt
```

再：

```bash
grep -n "DATA_SEGMENT_ALIGN" default.ld.txt
```

以及：

```bash
grep -n "ALIGN(CONSTANT" default.ld.txt
```

你会开始看到 GNU ld 自己生成的默认布局逻辑。

这一步非常重要，因为以后读：

```text
Linux
glibc
musl
U-Boot
kernel
bare-metal
```

的 linker script 时，你会发现很多写法其实就是在手工控制默认 linker script 原本帮你做的事情。

---

# 四十六、实验 39-13：用 `--verbose` 找到真正的默认页大小

不同版本的 GNU ld 输出格式可能不同，所以推荐：

```bash
ld --verbose | grep -Ei \
    'MAXPAGESIZE|COMMONPAGESIZE'
```

你可能看到：

```text
MAXPAGESIZE
COMMONPAGESIZE
```

它们不要混淆。

概念上：

```text
MAXPAGESIZE
    ↓
Segment / ELF 最大页对齐相关

COMMONPAGESIZE
    ↓
系统常用页大小相关
```

二者不是简单的同义词。

---

# 四十七、实验 39-14：`p_align` 与 Section `ALIGN()` 的终极对照

做一个表：

| 层次 | 示例 | 控制什么 |
|---|---|---|
| 输入 Section | `.data` | 输入内容 |
| Output Section | `.data` | Section 布局 |
| `ALIGN(16)` | 16 字节 | Section 起始位置 |
| Memory Region | `> SRAM` | VMA |
| `AT > FLASH` | FLASH | LMA |
| PHDR | `:data` | Segment 归属 |
| `FLAGS(6)` | RW | Segment 权限 |
| `p_align` | 0x1000/0x200000 | Segment 对齐 |
| `MAXPAGESIZE` | target-dependent | 最大页面对齐依据 |

这张表非常值得保存。

---

# 四十八、实验 39-15：最终综合 linker script

现在写最终版本：

```text
linker39-final.ld
```

```ld
ENTRY(_start)

MEMORY
{
    FLASH (rx)  : ORIGIN = 0x00400000, LENGTH = 16M
    SRAM  (rw)  : ORIGIN = 0x00600000, LENGTH = 16M
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
    /*
     * ELF Header + Program Header Table
     */
    . = ORIGIN(FLASH) + SIZEOF_HEADERS;

    /*
     * RX Segment
     */
    .text :
    {
        . = ALIGN(16);

        __text_start = .;

        *(.text.start)
        *(.text*)

        __text_end = .;
    } > FLASH :text

    /*
     * R Segment
     */
    .rodata :
    {
        . = ALIGN(16);

        __rodata_start = .;

        *(.rodata*)

        __rodata_end = .;
    } > FLASH :ro

    /*
     * 新 Segment 的边界
     */
    . = ALIGN(CONSTANT (MAXPAGESIZE));

    /*
     * RW Segment
     *
     * VMA -> SRAM
     * LMA -> FLASH
     */
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

# 四十九、完整编译命令

```bash
rm -f *.o *.elf *.map
```

编译：

```bash
gcc \
    -ffreestanding \
    -fno-pie \
    -fno-asynchronous-unwind-tables \
    -c start.S main.c data.c
```

链接：

```bash
ld \
    -T linker39-final.ld \
    start.o \
    main.o \
    data.o \
    -o segment39.elf \
    -Map=segment39.map
```

然后再做一个 4 KiB 版本：

```bash
ld \
    -z max-page-size=0x1000 \
    -T linker39-final.ld \
    start.o \
    main.o \
    data.o \
    -o segment39-4k.elf \
    -Map=segment39-4k.map
```

---

# 五十、最终验证清单

## ① ELF Header

```bash
readelf -h segment39.elf
```

关注：

```text
Start of program headers
Number of program headers
Size of program headers
```

---

## ② Section

```bash
readelf -SW segment39.elf
```

关注：

```text
.text
.rodata
.data
.bss
```

---

## ③ Segment

```bash
readelf -lW segment39.elf
```

重点：

```text
LOAD
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
readelf -lW segment39.elf
```

查看：

```text
Section to Segment mapping
```

应该建立：

```text
.text
   ↓
RX

.rodata
   ↓
R

.data
   ↓
RW

.bss
   ↓
RW
```

---

## ⑤ Section VMA/LMA

```bash
objdump -h segment39.elf
```

特别观察：

```text
.data
VMA
LMA
```

---

## ⑥ Program Header

```bash
objdump -p segment39.elf
```

---

## ⑦ Symbol

```bash
nm -n segment39.elf | grep -E \
    '__data|__bss|__text|__rodata'
```

---

## ⑧ Map

```bash
less segment39.map
```

或者：

```bash
grep -A15 -B5 '\.text' segment39.map
grep -A15 -B5 '\.rodata' segment39.map
grep -A15 -B5 '\.data' segment39.map
grep -A15 -B5 '\.bss' segment39.map
```

---

# 五十一、最终实验：自己算出 Segment 空洞

拿：

```bash
readelf -lW segment39.elf
```

记录：

```text
LOAD #1
p_offset
p_filesz

LOAD #2
p_offset
p_filesz
```

计算：

```text
gap =
LOAD2.p_offset
-
(LOAD1.p_offset + LOAD1.p_filesz)
```

再拿：

```bash
readelf -lW segment39-4k.elf
```

做同样计算。

最后比较：

```text
默认 max-page-size
        VS
0x1000
```

你应该能亲眼看到：

```text
MAXPAGESIZE
     ↓
p_align
     ↓
Segment boundary
     ↓
p_offset
     ↓
ELF 文件布局
```

---

# 五十二、这节最容易犯的 5 个错误

## 错误 1：认为 `ALIGN(16)` 控制 Segment

错。

```ld
. = ALIGN(16);
```

主要控制当前 Section 的位置。

Segment 的：

```text
p_align
```

要从：

```bash
readelf -lW
```

确认。

---

## 错误 2：认为 `MAXPAGESIZE` 是固定值

错。

它与目标工具链有关。

必须实际查询：

```bash
ld --verbose
```

以及最终：

```bash
readelf -lW
```

---

## 错误 3：认为文件巨大一定代表磁盘真的用了那么多空间

错。

检查：

```bash
ls -lh xxx.elf
du -h xxx.elf
```

---

## 错误 4：只看 Map 文件

不够。

Map：

```text
Section
Symbol
VMA/LMA
```

而 Segment：

```text
p_offset
p_vaddr
p_filesz
p_memsz
p_align
```

必须：

```text
Map + readelf -l + objdump -h
```

联合分析。

---

## 错误 5：看到 `.data` 在 SRAM，就认为 ELF 中没有 `.data`

错。

因为：

```ld
.data > SRAM AT > FLASH
```

意味着：

```text
运行：
SRAM

初始化镜像：
FLASH
```

这一点正是上一节实验 38 的核心。

---

# 五十三、实验 39 的最终脑图

现在整个模型应该变成：

```text
                         GNU ld
                           │
             ┌─────────────┼─────────────┐
             │             │             │
          MEMORY        SECTIONS        PHDRS
             │             │             │
             │             │             │
             │          VMA / LMA        │
             │             │             │
             │             ▼             │
             │          Section          │
             │             │             │
             └─────────────┼─────────────┘
                           ▼
                     PT_LOAD Segment
                           │
              ┌────────────┼────────────┐
              │            │            │
           p_offset     p_vaddr     p_filesz
              │            │            │
              │            │            │
              └──────┬─────┴────────────┘
                     │
                  p_align
                     │
                     ▼
               Segment 边界
                     │
                     ▼
             MAXPAGESIZE / 对齐
                     │
                     ▼
              padding / hole
```

而：

```text
.data
```

又形成：

```text
.data
 │
 ├── VMA → SRAM
 │
 ├── LMA → FLASH
 │
 └── PT_LOAD RW
        │
        ├── p_filesz
        │
        └── p_memsz
```

---

# 五十四、这一节真正要记住的 8 句话

### 1.

```text
Section alignment ≠ Segment alignment
```

### 2.

```text
p_align 是 Segment 属性。
```

### 3.

```text
MAXPAGESIZE 是 target-dependent 的 linker 常量。
```

### 4.

```ld
ALIGN(CONSTANT (MAXPAGESIZE))
```

可以用来显式制造符合最大页大小的布局边界。

### 5.

```text
p_offset
```

描述 Segment 在 ELF 文件中的位置。

### 6.

```text
p_vaddr
```

描述 Segment 的运行虚拟地址。

### 7.

对于可加载 Segment，要特别关注：

```text
p_offset ≡ p_vaddr (mod p_align)
```

### 8.

巨大的 ELF 空洞通常不是：

```text
“ld 莫名其妙浪费空间”
```

而是：

```text
Segment alignment
        ↓
p_align
        ↓
page boundary
        ↓
padding
```

---

# 五十五、下一节：实验 40

下一步就可以继续进入：

# 实验 40 —— `MAXPAGESIZE`、`COMMONPAGESIZE`、`DATA_SEGMENT_ALIGN()` 与数据段布局

这一节会把目前还没有真正拆开的：

```text
MAXPAGESIZE
COMMONPAGESIZE
DATA_SEGMENT_ALIGN()
DATA_SEGMENT_RELRO_END()
DATA_SEGMENT_END()
```

全部放到真实实验中。

尤其会做一个非常有价值的对照：

```text
默认 ld linker script
        VS
自己手写 linker script
```

然后解释为什么 GNU ld 默认脚本里经常能看到类似：

```ld
. = DATA_SEGMENT_ALIGN(CONSTANT (MAXPAGESIZE),
                       CONSTANT (COMMONPAGESIZE));
```

以及：

```ld
. = DATA_SEGMENT_RELRO_END(0, .);
```

这些看起来“很奇怪”的表达式到底在解决什么问题。

这会把课程从目前的：

```text
PHDRS / PT_LOAD
```

推进到：

```text
ELF Segment 布局策略
        +
Linux/Unix 默认 linker script
        +
RELRO
        +
Data Segment
```

也会为后面的 **实验 41：`OVERLAY`、`NOCROSSREFS`、`ASSERT` 综合约束**做好铺垫。GNU ld 官方手册明确说明了 `PHDRS` 可以覆盖默认 Program Header 生成规则，而默认 linker script 本身就是研究这些布局机制的最好“参考答案”。[Sourceware](https://sourceware.org/binutils/docs/ld.pdf?utm_source=chatgpt.com)

**官方 GNU ld 文档：** [GNU ld Linker Scripts 文档](https://sourceware.org/binutils/docs/ld/?utm_source=chatgpt.com)
