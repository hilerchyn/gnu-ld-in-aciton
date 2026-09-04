## 问题修复

编译过程中出现如下问题:

```shell
ubuntu@VM-24-13-ubuntu:~/work/gnu-ld-in-aciton/05-$ ld \
    -T linker.ld \
    start.o \
    main.o \
    -o custom.elf \
    -Map=custom.map
ld: address 0x2d of custom.elf section `.text' is not within region `ROM'
ld: custom.elf section `.eh_frame' will not fit in region `ROM'
ld: address 0x6c of custom.elf section `.data' is not within region `RAM'
ld: address 0x74 of custom.elf section `.bss' is not within region `RAM'
ld: address 0x2d of custom.elf section `.text' is not within region `ROM'
ld: address 0x6c of custom.elf section `.data' is not within region `RAM'
ld: address 0x74 of custom.elf section `.bss' is not within region `RAM'
ld: region `ROM' overflowed by 18446744073705291884 bytes
```


### 修复

这个错误非常好，因为它暴露了我们上一节实验里一个**关键但容易被忽略的问题**：

> **你的 `linker.ld` 很可能把 `ROM` / `RAM` 定义成了高地址，但 `.text`、`.data`、`.bss` 实际却从地址 `0` 开始计算。**

从错误里的：

```text
address 0x2d of custom.elf section `.text' is not within region `ROM'
address 0x6c of custom.elf section `.data' is not within region `RAM'
address 0x74 of custom.elf section `.bss' is not within region `RAM'
```

已经可以非常明确地看出来这一点。

而且这正好对应 GNU ld 手册对 `MEMORY`、输出 Section 地址以及 location counter `.` 的描述：如果输出 Section 没有明确地址，指定了内存区域后，ld 会尝试把它放到该区域的下一个可用地址；而 Section 地址本身就是 VMA。 

---

# 一、先看你的错误到底在说什么

你的错误：

```text
ld: address 0x2d of custom.elf section `.text' is not within region `ROM'

ld: custom.elf section `.eh_frame' will not fit in region `ROM'

ld: address 0x6c of custom.elf section `.data' is not within region `RAM'

ld: address 0x74 of custom.elf section `.bss' is not within region `RAM'

...

ld: region `ROM' overflowed by 18446744073705291884 bytes
```

最重要的是这几个地址：

```text
.text → 0x2d
.data → 0x6c
.bss  → 0x74
```

注意：

```text
0x2d
0x6c
0x74
```

都是非常小的地址。

而我们上一实验的 linker script 是：

```ld
MEMORY
{
    ROM (rx) : ORIGIN = 0x00400000, LENGTH = 64K
    RAM (rw) : ORIGIN = 0x00600000, LENGTH = 64K
}
```

所以理论上应该是：

```text
.text → 0x00400000 左右
.data → 0x00600000 左右
.bss  → 0x00600000 左右
```

而不是：

```text
.text → 0x0000002d
.data → 0x0000006c
.bss  → 0x00000074
```

---

# 二、为什么会出现这种情况？

这里要特别注意一个概念：

```text
MEMORY
```

和：

```text
SECTIONS
```

是两个层次。

例如：

```ld
MEMORY
{
    ROM (rx) : ORIGIN = 0x00400000, LENGTH = 64K
    RAM (rw) : ORIGIN = 0x00600000, LENGTH = 64K
}
```

只是告诉 linker：

```text
ROM
┌─────────────────────────────┐
│ 0x00400000                  │
│                             │
│          64 KB              │
│                             │
└─────────────────────────────┘

RAM
┌─────────────────────────────┐
│ 0x00600000                  │
│                             │
│          64 KB              │
│                             │
└─────────────────────────────┘
```

然后你还必须通过：

```ld
> ROM
> RAM
```

把 Output Section 放进去。

手册明确说明，可以通过 `>region` 将 Output Section 放入 `MEMORY` 定义的区域；如果区域中的 Section 总大小超过区域容量，ld 会报错。

---

# 三、先检查你当前的 linker.ld

你应该检查是不是类似下面这样：

```ld
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
    }

    .data :
    {
        *(.data)
    }

    .bss :
    {
        *(.bss)
    }
}
```

如果是这样，问题就在这里：

```ld
.text :
```

没有：

```ld
> ROM
```

`.data` 没有：

```ld
> RAM
```

`.bss` 也没有：

```ld
> RAM
```

---

# 四、正确写法

先改成：

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
    } > ROM

    .rodata :
    {
        *(.rodata)
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

注意这四个：

```ld
.text   > ROM
.rodata > ROM
.data   > RAM
.bss    > RAM
```

这才是真正告诉 ld：

```text
.text
    ↓
ROM

.rodata
    ↓
ROM

.data
    ↓
RAM

.bss
    ↓
RAM
```

---

# 五、但是你马上会遇到第二个问题：`.eh_frame`

你的错误里面还有：

```text
custom.elf section `.eh_frame' will not fit in region `ROM'
```

这也是一个非常典型的 linker 学习问题。

为什么突然出现：

```text
.eh_frame
```

？

因为你用：

```bash
gcc -c main.c
```

编译 C 程序时，GCC 可能生成额外的异常/展开信息 section。

你可以直接检查：

```bash
readelf -S main.o
```

应该会看到：

```text
.text
.data
.bss
.eh_frame
...
```

而你的 linker script 没有显式处理：

```text
.eh_frame
```

所以它变成了一个 **orphan section**。

GNU ld 默认会尝试为没有被 linker script 明确描述的 Section 找一个合适的位置；手册称这种 Section 为 orphan section。

---

# 六、实验课程里，我们先把 `.eh_frame` 排除掉

因为我们现在是在学习：

```text
.text
.rodata
.data
.bss
```

而不是学习 GCC exception/unwind。

所以最简单的方法是：

```bash
gcc -fno-asynchronous-unwind-tables -fno-unwind-tables -c main.c -o main.o
```

然后：

```bash
readelf -S main.o
```

再次检查。

最好没有：

```text
.eh_frame
```

---

# 七、还有一个更值得学习的方法：在 linker script 中处理它

你也可以显式：

```ld
.eh_frame :
{
    *(.eh_frame)
} > ROM
```

但是对于我们现在这个实验，我更推荐：

```bash
gcc \
    -fno-asynchronous-unwind-tables \
    -fno-unwind-tables \
    -c main.c \
    -o main.o
```

因为我们当前的实验目标是理解：

```text
.text
.data
.bss
```

而不是让：

```text
.eh_frame
```

干扰实验。

---

# 八、为什么最后出现了一个“天文数字”？

这个：

```text
region `ROM' overflowed by 18446744073705291884 bytes
```

非常有意思。

不要被这个巨大数字吓到。

实际上它是一个**无符号整数下溢/环绕后的结果**。

你可以看到：

```text
18446744073705291884
```

接近：

```text
2^64
```

也就是：

```text
18446744073709551616
```

两者相减：

```text
18446744073709551616
-
18446744073705291884
=
4259732
```

也就是大约：

```text
0x410000
```

这和你的地址空间问题高度吻合。

也就是说：

> **真正的问题不是“ROM 真被用爆了 18 EB”，而是 Section 的地址跑到了 ROM 区域之外，导致 linker 的地址计算发生了无符号环绕。**

所以遇到这种：

```text
overflowed by 1844674407370...
```

不要第一反应认为：

> “我的程序怎么突然变成 18 EB 了？”

而应该立即检查：

```text
VMA
LMA
ORIGIN
LENGTH
.
```

---

# 九、我们现在做一次“定位实验”

重新编译：

```bash
rm -f *.o custom.elf custom.map

gcc \
    -fno-asynchronous-unwind-tables \
    -fno-unwind-tables \
    -c main.c \
    -o main.o

gcc -c start.S -o start.o
```

然后链接：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    -o custom.elf \
    -Map=custom.map
```

---

# 十、如果仍然报错，立刻做这个实验

执行：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    -o custom.elf \
    -Map=custom.map \
    --verbose
```

不过这里我们暂时不需要看全部输出。

更简单的是：

```bash
grep -E '\.text|\.rodata|\.data|\.bss|\.eh_frame' custom.map
```

以及：

```bash
head -100 custom.map
```

---

# 十一、最重要的一条命令：`readelf -S`

如果链接成功：

```bash
readelf -S custom.elf
```

你应该看到：

```text
.text
```

地址大约：

```text
0x00400000
```

而：

```text
.data
```

地址大约：

```text
0x00600000
```

`.bss` 则在：

```text
0x00600000 + sizeof(.data)
```

附近。

---

# 十二、然后用 `objdump -h`

```bash
objdump -h custom.elf
```

重点观察：

```text
Idx Name      Size      VMA
                   LMA
```

例如理想结果：

```text
.text
Size = ...
VMA  = 0000000000400000
LMA  = 0000000000400000

.data
Size = ...
VMA  = 0000000000600000
LMA  = 00000000004000xx

.bss
Size = ...
VMA  = 00000000006000xx
LMA  = ...
```

这里我们就重新回到了上一节的核心：

```text
.data

VMA
↓
RAM

LMA
↓
ROM
```

GNU ld 手册也明确说明：每个 Section 都有 VMA 和 LMA；`AT` / `AT>` 用于指定 LMA，而 `>region` 指定 Output Section 所在的内存区域。

---

# 十三、但这里还有一个重要修正

上一节课程中我们写过：

```ld
.data :
{
    _sdata = .;
    *(.data)
    _edata = .;
} > RAM AT > ROM
```

这是正确方向，但你现在这个错误说明我们需要进一步理解：

```text
VMA
LMA
MEMORY
location counter
```

它们之间不能混为一谈。

例如：

```ld
.data > RAM AT > ROM
```

意思是：

```text
.data 的运行地址
        ↓
RAM

.data 的加载地址
        ↓
ROM
```

手册对 `AT>` 的描述非常明确：它把 Section 的 LMA 放到指定 memory region 的下一个可用地址，并满足 Section alignment。

---

# 十四、建议你现在使用这个“实验稳定版”

我们暂时把 linker script 简化到最容易观察的版本：

```ld
ENTRY(_start)

MEMORY
{
    ROM (rx) : ORIGIN = 0x00400000, LENGTH = 64K
    RAM (rw) : ORIGIN = 0x00600000, LENGTH = 64K
}

SECTIONS
{
    .text ALIGN(16) :
    {
        _stext = .;

        *(.text)

        _etext = .;
    } > ROM

    .rodata ALIGN(8) :
    {
        *(.rodata)
    } > ROM

    .data ALIGN(8) :
    {
        _sdata = .;

        *(.data)

        _edata = .;
    } > RAM AT > ROM

    _sidata = LOADADDR(.data);

    .bss ALIGN(8) :
    {
        _sbss = .;

        *(.bss)
        *(COMMON)

        _ebss = .;
    } > RAM
}
```

这就是我们接下来课程的基础版本。

---

# 十五、注意 `.bss` 不应该放到 ROM

现在：

```ld
.bss > RAM
```

这是非常重要的。

因为：

```text
.data
```

有初始化值：

```c
int x = 123;
```

所以：

```text
ROM：
123
 │
 │ startup copy
 ▼
RAM：
123
```

而：

```text
.bss
```

例如：

```c
int y;
```

文件里面根本不需要保存：

```text
00000000
```

只需要：

```text
RAM
 ↓
清零
```

所以：

```text
.data
VMA → RAM
LMA → ROM

.bss
VMA → RAM
没有实际初始化文件内容
```

这也正是手册给出的 ROM→RAM `.data` 拷贝、`.bss` 清零启动代码模型。

---

# 十六、Map 文件是解决这种问题的第一现场

以后再遇到：

```text
section xxx is not within region yyy
```

不要先猜。

直接：

```bash
grep -n "\.text" custom.map
grep -n "\.data" custom.map
grep -n "\.bss" custom.map
grep -n "\.eh_frame" custom.map
```

你要回答四个问题：

```text
① Section 的 VMA 是多少？

② Section 的 LMA 是多少？

③ Section 被分配到了哪个 MEMORY region？

④ 是哪个 .o 文件贡献了它？
```

GNU ld 手册说明 `-Map` 会输出 object file 的内存映射、common symbol 分配以及符号值等信息。

---

# 十七、这次错误其实暴露了一个更深的知识点

我们之前一直在学习：

```text
linker.ld
    ↓
SECTIONS
```

现在你应该开始建立这样的思维：

```text
                 linker.ld
                     │
         ┌───────────┼───────────┐
         │           │           │
         ▼           ▼           ▼
      MEMORY      SECTIONS      PHDRS
         │           │           │
         │           │           │
         ▼           ▼           ▼
      地址范围     Section布局   Segment布局
         │           │           │
         └───────────┼───────────┘
                     ▼
                    ELF
```

其中：

```text
MEMORY
```

回答：

> **“哪里可以放？”**

```text
SECTIONS
```

回答：

> **“Section 怎么放？”**

```text
PHDRS
```

回答：

> **“loader 怎么加载？”**

---

# 十八、你的这个错误，对应到脑图就是这里

```text
MEMORY
│
├── ROM
│   ├── ORIGIN = 0x00400000
│   └── LENGTH = 64K
│
└── RAM
    ├── ORIGIN = 0x00600000
    └── LENGTH = 64K
           │
           ▼
       SECTIONS
           │
      ┌────┼────┐
      ▼    ▼    ▼
    .text .data .bss
      │    │     │
      ▼    ▼     ▼
     ROM  RAM   RAM
```

而你的错误实际上说明：

```text
.text
 ↓
0x0000002d
```

却要求：

```text
ROM
 ↓
0x00400000 ~ 0x00410000
```

所以：

```text
0x2d ∉ [0x400000, 0x410000)
```

自然报：

```text
section `.text' is not within region `ROM'
```

---

# 十九、现在不要急着进入实验 06

我们应该先把这个错误彻底解决。

请你把**当前正在使用的 `linker.ld` 完整内容**贴出来，尤其是：

```ld
MEMORY
{
    ...
}

PHDRS
{
    ...
}

SECTIONS
{
    ...
}
```

以及执行：

```bash
readelf -S main.o
```

把输出贴出来。

**我可以直接根据你的实际 `linker.ld + main.o`，逐行定位为什么 `.text` 会跑到 `0x2d`，然后把实验 05 修正成一个你机器上可以直接运行的版本。**

这比继续往实验 06 走更重要——因为我们现在正好碰到了学习 GNU `ld` 最有价值的一类问题：**“我明明定义了 MEMORY，为什么 Section 还是跑到了错误地址？”** 

