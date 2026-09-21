# GNU ld 实战课程 · 实验 22

## `ALIGN()` / `SUBALIGN()` / `ALIGN_WITH_INPUT()`：彻底搞懂对齐、Padding，以及“为什么地址突然跳了一大截”

这一节承接实验 21 的 `INSERT BEFORE / INSERT AFTER`，同时专门把你前面实验中遇到的那个坑彻底讲清楚：

```ld
.text ALIGN(16) :
```

和：

```ld
.text : ALIGN(16)
```

**不是一回事。**

前者的 `ALIGN(16)` 位于 **Output Section address** 位置，后者的 `ALIGN(16)` 位于 **Output Section attribute** 位置。

这正是你之前遇到：

```text
address 0x2d of custom.elf section `.text' is not within region `ROM'
```

以及：

```text
region `ROM' overflowed
```

这类问题的关键。

今天我们不靠记忆，而是用 ELF 实验把三层东西拆开：

```text
Input Section Alignment
        ↓
Output Section Alignment
        ↓
Section 内部 Subsection Alignment
```

最终搞清楚：

```text
ALIGN()
SUBALIGN()
ALIGN_WITH_INPUT()
```

分别控制什么。

---

# 一、今天的实验路线

```text
实验 22-1
观察 Input Section 自己的 alignment

实验 22-2
Output Section 的 ALIGN()

实验 22-3
证明：
.text ALIGN(16) :
与
.text : ALIGN(16)
不是一回事

实验 22-4
观察 *fill* padding

实验 22-5
输入 Section 自己的 alignment 如何影响布局

实验 22-6
SUBALIGN() 改变 Input Section alignment

实验 22-7
ALIGN_WITH_INPUT()

实验 22-8
ALIGN() + SUBALIGN() + ALIGN_WITH_INPUT() 对比

实验 22-9
Map + readelf + objdump 三重验证

实验 22-10
建立真正可用于 MCU 的对齐模型
```

---

# 二、先建立实验目录

```text
lab22/
├── start.S
├── main.c
├── a.c
├── b.c
├── c.c
├── linker.ld
└── Makefile
```

---

# 三、实验 22-1：先观察 Input Section 的 alignment

我们先不要碰 linker script。

创建 `a.c`：

```c
__attribute__((section(".foo")))
char foo_a = 0x11;
```

`b.c`：

```c
__attribute__((section(".bar"), aligned(16)))
char foo_b = 0x22;
```

`c.c`：

```c
__attribute__((section(".baz"), aligned(4096)))
char foo_c = 0x33;
```

注意这里故意制造：

```text
.foo     alignment = 1
.bar     alignment = 16
.baz     alignment = 4096
```

---

# 四、编译

```bash
gcc -ffreestanding -fno-pie -fno-stack-protector \
    -c a.c -o a.o

gcc -ffreestanding -fno-pie -fno-stack-protector \
    -c b.c -o b.o

gcc -ffreestanding -fno-pie -fno-stack-protector \
    -c c.c -o c.o
```

现在：

```bash
objdump -h a.o
```

```bash
objdump -h b.o
```

```bash
objdump -h c.o
```

重点看最后的：

```text
Algn
```

你应该看到类似：

```text
.foo    ...  2**0
.bar    ...  2**4
.baz    ...  2**12
```

也就是：

```text
2**0  = 1
2**4  = 16
2**12 = 4096
```

---

# 五、这一步非常重要

现在我们已经证明：

```text
Input Section
    │
    └── 自己带有 alignment 属性
```

例如：

```text
.foo
    alignment = 1

.bar
    alignment = 16

.baz
    alignment = 4096
```

所以 linker 并不是面对：

```text
foo
bar
baz
```

三个“普通字节块”。

它实际上看到的是：

```text
foo  + align 1
bar  + align 16
baz  + align 4096
```

这就是今天所有实验的基础。

---

# 六、实验 22-2：最简单的 Output Section

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
        *(.text)
        *(.text.*)
    } > ROM

    .custom :
    {
        *(.foo)
        *(.bar)
        *(.baz)
    } > ROM
}
```

这里没有：

```ld
ALIGN()
SUBALIGN()
```

---

# 七、最小启动代码

`start.S`：

```asm
.global _start

.text

_start:
    call main
    hlt
```

`main.c`：

```c
int main(void)
{
    return 0;
}
```

编译：

```bash
gcc -ffreestanding -fno-pie -fno-stack-protector \
    -c start.S -o start.o

gcc -ffreestanding -fno-pie -fno-stack-protector \
    -c main.c -o main.o
```

---

# 八、链接

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    a.o \
    b.o \
    c.o \
    -o align01.elf \
    -Map=align01.map
```

---

# 九、观察最终布局

```bash
readelf -S align01.elf
```

再：

```bash
objdump -h align01.elf
```

重点观察：

```text
.custom
```

以及：

```text
.foo
.bar
.baz
```

如果 `.custom` 内部依次包含：

```text
.foo
.bar
.baz
```

那么由于：

```text
.bar alignment = 16
.baz alignment = 4096
```

linker 必须满足这些 Input Section 的对齐要求。

因此可能出现：

```text
.foo
padding
.bar
padding
.baz
```

---

# 十、Map 文件是这里最重要的证据

打开：

```bash
less align01.map
```

找到：

```text
.custom
```

你可能看到类似：

```text
.custom         0x00400020
                0x00000001 a.o
                0x0000000f *fill*
                0x00000001 b.o
                0x00000fef *fill*
                0x00000001 c.o
```

具体数字取决于你的前面代码大小和工具链。

但是结构非常重要：

```text
.foo
   ↓
*fill*
   ↓
.bar
   ↓
*fill*
   ↓
.baz
```

这就是：

# Alignment 产生的 Padding

---

# 十一、`*fill*` 到底是什么？

Map 中看到：

```text
*fill*
```

不要把它理解成：

> “程序主动定义了一个 fill section。”

它实际上是在告诉你：

> linker 为了满足布局要求，插入了一段填充空间。

例如：

```text
当前位置：

0x400001

下一 Section 要求：

16-byte alignment
```

那么：

```text
0x400001
   ↓
0x400010
```

中间：

```text
0x400002
...
0x40000f
```

就必须被填掉。

于是 Map 里可能出现：

```text
*fill*
```

---

# 十二、用数学公式理解 Alignment

假设当前地址：

```text
A = 0x1003
```

要求：

```text
alignment = 16
```

那么下一个合法地址：

```text
align_up(A, 16)
```

结果：

```text
0x1010
```

Padding：

```text
0x1010 - 0x1003
=
0xD
=
13 bytes
```

所以：

```text
当前地址
    ↓
0x1003

13 bytes padding
    ↓

下一个 section
    ↓
0x1010
```

---

# 十三、实验 22-3：真正搞清楚两个 `ALIGN(16)`

现在来到最重要的实验。

比较：

```ld
.text ALIGN(16) :
{
    ...
}
```

和：

```ld
.text : ALIGN(16)
{
    ...
}
```

这两个**千万不要混为一谈**。

---

# 十四、第一种：`.text ALIGN(16) :`

```ld
.text ALIGN(16) :
{
    *(.text)
} > ROM
```

这里：

```text
.text
  ↓
Output Section name

ALIGN(16)
  ↓
Output Section address

:
  ↓
section body
```

也就是说：

```ld
.text ALIGN(16) :
```

相当于告诉 linker：

> `.text` 的地址表达式是 `ALIGN(16)`。

而：

```text
ALIGN(16)
```

的计算结果取决于当前地址。

**它不是在这里单纯声明“section alignment = 16”。**

---

# 十五、这正是你之前遇到的问题

假设：

```ld
MEMORY
{
    ROM (rx) : ORIGIN = 0x00400000, LENGTH = 64K
}
```

如果你写：

```ld
.text ALIGN(16) :
```

那么 linker 会把 `.text` 的地址表达式计算成：

```text
ALIGN(16)
```

如果当前 location counter 是：

```text
0
```

那么：

```text
ALIGN(16)
=
0x0
```

结果：

```text
.text
    address = 0
```

而：

```text
ROM
    0x00400000
```

于是：

```text
.text address = 0
```

显然：

```text
0 < 0x00400000
```

不在 ROM 中。

这正是之前类似：

```text
address ... section `.text' is not within region `ROM'
```

错误的根源。

---

# 十六、第二种：

```ld
.text : ALIGN(16)
{
    ...
}
```

这里的：

```ld
ALIGN(16)
```

已经位于：

```text
Output Section attribute
```

的位置。

它表达的是：

> **要求这个 Output Section 的 alignment 至少为 16。**

所以：

```ld
.text : ALIGN(16)
{
    ...
}
```

和：

```ld
.text ALIGN(16) :
```

语义完全不同。

这是本课程必须牢牢记住的一组语法。

---

# 十七、第三种：`. = ALIGN(16)`

还有第三种：

```ld
.text :
{
    . = ALIGN(16);

    *(.text)

}
```

这又是不同的。

这里：

```text
. = ALIGN(16)
```

操作的是：

# Location Counter

也就是：

```text
当前地址
```

---

# 十八、现在把三种形式并排放一起

这是实验 22 最重要的一张表：

| 写法                  | 控制对象                     |
| ------------------- | ------------------------ |
| `.text ALIGN(16) :` | Output Section **地址表达式** |
| `.text : ALIGN(16)` | Output Section **对齐属性**  |
| `. = ALIGN(16);`    | 当前 **Location Counter**  |

千万不要把它们当成三个写法随便替换。

---

# 十九、实验 22-4：验证 `.text ALIGN(16) :`

建立：

```ld
ENTRY(_start)

MEMORY
{
    ROM (rx) : ORIGIN = 0x00400000, LENGTH = 64K
}

SECTIONS
{
    .text ALIGN(16) :
    {
        *(.text)
    } > ROM
}
```

然后：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    -o bad-align.elf \
    -Map=bad-align.map
```

你很可能得到：

```text
ld: address 0x... of bad-align.elf section `.text'
is not within region `ROM'
```

或者类似的地址错误。

---

# 二十、实验 22-5：改成正确的 Output Section Alignment

改成：

```ld
.text : ALIGN(16)
{
    *(.text)
} > ROM
```

重新：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    -o align-ok.elf \
    -Map=align-ok.map
```

然后：

```bash
readelf -S align-ok.elf
```

观察：

```text
.text
```

的：

```text
Addr
```

应该仍然位于：

```text
0x00400000
```

附近，而不是：

```text
0x00000010
```

---

# 二十一、但是这里有一个更细的知识点

假设：

```text
当前地址 = 0x400003
```

你写：

```ld
.text : ALIGN(16)
```

这主要是告诉 linker：

```text
.text
alignment = 16
```

而 Output Section 实际开始位置仍然需要满足这个 alignment。

所以最终：

```text
0x400003
    ↓
0x400010
```

中间会产生：

```text
padding
```

也就是说：

```text
Output Section alignment
```

最终仍然会影响：

```text
Output Section VMA
```

只是它的语义不是：

```text
“把地址表达式写成 ALIGN(16)”
```

而是：

```text
“这个 Output Section 要满足 16-byte alignment”
```

---

# 二十二、实验 22-6：只给 Output Section 设置 Alignment

使用：

```ld
.custom : ALIGN(4096)
{
    *(.foo)
    *(.bar)
    *(.baz)
} > ROM
```

链接：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    a.o \
    b.o \
    c.o \
    -o align4096.elf \
    -Map=align4096.map
```

查看：

```bash
readelf -S align4096.elf
```

重点：

```text
.custom
```

的地址。

你会看到它被安排到：

```text
...000
```

这样的 4096 对齐地址。

---

# 二十三、用 Python/心算验证

如果地址：

```text
0x400123
```

要求：

```text
4096 = 0x1000
```

那么：

```text
ALIGN_UP(0x400123, 0x1000)
=
0x401000
```

padding：

```text
0x401000 - 0x400123
=
0xEDD
```

也就是：

```text
3805 bytes
```

这就是为什么一个看起来只有几十字节的 Section：

```text
```

有时候会让 ELF 突然多出几 KB。

真正占空间的可能不是数据：

```text
Section size
```

而是：

```text
Alignment padding
```

---

# 二十四、实验 22-7：输入 Section 自己的 Alignment

现在回到：

```text
.foo alignment = 1
.bar alignment = 16
.baz alignment = 4096
```

linker：

```ld
.custom :
{
    *(.foo)
    *(.bar)
    *(.baz)
} > ROM
```

注意：

我们没有：

```ld
ALIGN()
```

也没有：

```ld
SUBALIGN()
```

那么：

```text
Input Section 自己的 alignment
```

仍然会生效。

也就是说：

```text
.foo
    align 1

.bar
    align 16

.baz
    align 4096
```

linker 必须满足：

```text
bar 16-byte aligned
baz 4096-byte aligned
```

---

# 二十五、实验 22-8：`SUBALIGN()`

现在我们第一次使用：

```ld
SUBALIGN()
```

linker：

```ld
.custom : SUBALIGN(1)
{
    *(.foo)
    *(.bar)
    *(.baz)
} > ROM
```

这个意思是：

> **把这个 Output Section 中输入 section 的 alignment 统一限制为 1。**

于是原来的：

```text
.foo align 1
.bar align 16
.baz align 4096
```

在 `.custom` 内部可以被强制按照：

```text
1
1
1
```

进行子 section 对齐。

---

# 二十六、为什么 `SUBALIGN()` 非常重要？

假设：

```text
Input Sections：

foo:
    size = 1
    align = 1

bar:
    size = 1
    align = 4096

baz:
    size = 1
    align = 1
```

默认：

```text
foo
padding ~4095
bar
baz
```

可能非常浪费。

如果：

```ld
.custom : SUBALIGN(1)
{
    *(.foo)
    *(.bar)
    *(.baz)
}
```

那么：

```text
foo
bar
baz
```

可以紧密排列。

---

# 二十七、但是注意：不要无脑使用 `SUBALIGN(1)`

因为：

```text
Input Section
```

原本要求：

```text
4096-byte alignment
```

你强制：

```ld
SUBALIGN(1)
```

以后：

```text
这个 Input Section 自己原来的 alignment 约束
```

就被改变了。

所以如果那个 section 是：

```text
SIMD data
DMA buffer
page table
vector table
特殊硬件结构
```

贸然：

```ld
SUBALIGN(1)
```

可能造成严重问题。

---

# 二十八、`SUBALIGN()` 的思维方式

把：

```ld
.custom : SUBALIGN(1)
```

理解成：

```text
Output Section
        │
        ├── Input A
        ├── Input B
        └── Input C

原始：
A align 1
B align 4096
C align 16

SUBALIGN(1)

        ↓

A align 1
B align 1
C align 1
```

它主要控制：

# Output Section 内部 Input Section 的对齐。

而：

```ld
.custom : ALIGN(4096)
```

主要控制：

# Output Section 自身的对齐。

这两个层次必须分开。

---

# 二十九、实验 22-9：同时使用 `ALIGN()` 和 `SUBALIGN()`

```ld
.custom : ALIGN(4096) SUBALIGN(1)
{
    *(.foo)
    *(.bar)
    *(.baz)
} > ROM
```

现在：

```text
.custom
    ↓
Output Section 自身
    alignment = 4096

内部：
.foo
.bar
.baz
    alignment = 1
```

所以可能得到：

```text
ROM

0x400000
...
padding
...
0x401000
.custom
    foo
    bar
    baz
```

也就是：

```text
Section 外部
    4096 alignment

Section 内部
    1 alignment
```

这就是：

```text
ALIGN()
+
SUBALIGN()
```

组合的意义。

---

# 三十、实验 22-10：`ALIGN_WITH_INPUT()`

现在进入一个更特殊的功能：

```ld
ALIGN_WITH_INPUT
```

它的目标是：

> 让 Output Section 的 alignment 与输入 section 的 alignment 关系保持一致。

典型写法：

```ld
.custom :
ALIGN_WITH_INPUT
{
    *(.foo)
    *(.bar)
    *(.baz)
} > ROM
```

这个语法与：

```ld
.custom : ALIGN(16)
```

的思想完全不同。

---

# 三十一、为什么需要 `ALIGN_WITH_INPUT()`？

考虑：

```text
Input A:
alignment = 16

Input B:
alignment = 4096
```

如果 linker 把它们放进：

```text
.custom
```

那么：

```text
.custom
```

最终至少需要满足输入 section 所需的最大 alignment。

`ALIGN_WITH_INPUT` 可以用于让 Output Section alignment 不被简单地固定成一个常量，而是根据输入 section 的对齐关系处理。

它尤其适合：

```text
不同输入文件
不同 alignment
希望尽可能保留输入对齐语义
```

的情况。

---

# 三十二、这里先做一个非常重要的实验对比

准备：

```text
foo.o
    .foo
    align = 1

bar.o
    .bar
    align = 16

baz.o
    .baz
    align = 4096
```

分别建立三个 linker script。

---

## A：默认

```ld
.custom :
{
    *(.foo)
    *(.bar)
    *(.baz)
} > ROM
```

---

## B：固定 Output Alignment

```ld
.custom : ALIGN(4096)
{
    *(.foo)
    *(.bar)
    *(.baz)
} > ROM
```

---

## C：Input-driven

```ld
.custom :
ALIGN_WITH_INPUT
{
    *(.foo)
    *(.bar)
    *(.baz)
} > ROM
```

分别链接：

```bash
ld -T align-a.ld ... -o a.elf -Map=a.map
ld -T align-b.ld ... -o b.elf -Map=b.map
ld -T align-c.ld ... -o c.elf -Map=c.map
```

---

# 三十三、然后比较

```bash
readelf -S a.elf
readelf -S b.elf
readelf -S c.elf
```

再：

```bash
objdump -h a.elf
objdump -h b.elf
objdump -h c.elf
```

最后：

```bash
grep -A 20 "\.custom" a.map
grep -A 20 "\.custom" b.map
grep -A 20 "\.custom" c.map
```

你真正要观察的不是：

```text
“哪个命令输出长什么样”
```

而是：

```text
Output Section alignment
Input Section alignment
padding
最终 VMA
```

四者之间的关系。

---

# 三十四、建立一张“对齐三层模型”

到这里，可以把 GNU ld 的 alignment 理解成三层：

```text
                    Alignment
                       │
        ┌──────────────┼──────────────┐
        ▼              ▼              ▼
Input Section    Output Section    Location Counter
    │                  │                 │
    │                  │                 │
objdump -h         ALIGN()          . = ALIGN()
    │                  │                 │
    ▼                  ▼                 ▼
  对齐要求          Section 对齐       当前地址
```

然后：

```text
SUBALIGN()
```

介入：

```text
Output Section
       │
       ├── Input Section A
       ├── Input Section B
       └── Input Section C
              ↑
           SUBALIGN
```

而：

```text
ALIGN_WITH_INPUT
```

则用于：

```text
Output Section
       ↑
Input Section alignment
```

之间建立关联。

---

# 三十五、实验 22-11：真正理解 `.`

GNU ld linker script 中：

```ld
.
```

是：

# Location Counter

例如：

```ld
.text :
{
    . = ALIGN(16);
    *(.text)
}
```

假设进入 `.text` 时：

```text
. = 0x400003
```

执行：

```ld
. = ALIGN(16);
```

以后：

```text
. = 0x400010
```

然后：

```ld
*(.text)
```

从：

```text
0x400010
```

开始。

---

# 三十六、所以：

```ld
.text : ALIGN(16)
```

和：

```ld
.text :
{
    . = ALIGN(16);
    *(.text)
}
```

也不是完全相同的层次。

第一种：

```text
Output Section alignment
```

第二种：

```text
修改 section body 内的 Location Counter
```

实际布局结果有时看起来一样，但**语义和影响范围不同**。

---

# 三十七、一个特别重要的实验

创建：

```ld
.test :
{
    BYTE(0x11);

    . = ALIGN(16);

    BYTE(0x22);
}
```

假设 `.test` 从：

```text
0x400000
```

开始。

第一字节：

```text
0x400000 = 0x11
```

然后：

```ld
. = ALIGN(16);
```

跳到：

```text
0x400010
```

于是：

```text
0x400001
...
0x40000f
```

出现：

```text
padding
```

然后：

```text
0x400010 = 0x22
```

---

# 三十八、用 `objdump -s` 验证

```bash
objdump -s \
    --section=.test \
    test.elf
```

你会看到：

```text
11
```

然后中间一段：

```text
00 00 00 ...
```

然后：

```text
22
```

这就是：

# Location Counter 手工跳跃产生的 padding。

---

# 三十九、这里就能解释 Map 中的 `*fill*`

Map：

```text
.test
    BYTE 0x11
    *fill* 0x0f
    BYTE 0x22
```

而：

```text
objdump -s
```

看到：

```text
11
00 00 00 ...
22
```

于是：

```text
Map
+
ELF 原始内容
```

完全对应。

这就是我们一直强调的：

> **Map 文件不是用来“猜”的，而是用来解释 ELF 的。**

---

# 四十、实验 22-12：`FILL()` 顺便一起掌握

现在：

```ld
.test :
{
    FILL(0xCC);

    BYTE(0x11);

    . = ALIGN(16);

    BYTE(0x22);
}
```

链接后：

```bash
objdump -s --section=.test test.elf
```

你可能看到：

```text
11 cc cc cc ...
22
```

这里就出现了：

```ld
FILL(0xCC)
```

它控制 padding 使用的填充值。

---

# 四十一、为什么这对固件特别有意义？

MCU Flash 中经常希望：

```text
padding
```

不是默认的：

```text
00
```

而是：

```text
FF
```

例如：

```ld
.text :
{
    FILL(0xFFFFFFFF);

    *(.text)
}
```

具体行为要结合 section 的实际填充位置和目标格式理解，但核心思想是：

```text
padding
    ↓
指定填充值
```

这在：

```text
Flash image
ROM image
Bootloader
Firmware header
固定长度镜像
```

中很有用。

---

# 四十二、实验 22-13：把 `INSERT` 和 Alignment 组合起来

上一节我们有：

```ld
SECTIONS
{
    .firmware_info :
    {
        KEEP(*(.firmware_info))
    }
}

INSERT AFTER .text;
```

现在升级：

```ld
SECTIONS
{
    .firmware_info :
        ALIGN(16)
    {
        . = ALIGN(16);

        KEEP(*(.firmware_info))

        . = ALIGN(16);
    }
}

INSERT AFTER .text;
```

这里同时存在：

```text
Output Section alignment
+
内部 Location Counter alignment
```

这就是非常真实的固件布局写法。

---

# 四十三、但是不要重复做无意义的 ALIGN

例如：

```ld
.firmware_info : ALIGN(16)
{
    . = ALIGN(16);

    KEEP(*(.firmware_info))

    . = ALIGN(16);
}
```

三个 alignment 的作用并不相同。

如果你只是需要：

> `.firmware_info` 起始地址 16 字节对齐。

通常：

```ld
.firmware_info : ALIGN(16)
{
    KEEP(*(.firmware_info))
}
```

就已经足够。

如果需要：

> Section 内部某个对象开始地址 16 字节对齐。

才需要：

```ld
. = ALIGN(16);
```

---

# 四十四、实验 22-14：真正分析一个“巨大空洞”

假设 Map：

```text
.text
    0x00400000
    size = 0x2D

.custom
    0x00401000
```

看到：

```text
.text size = 45 bytes
```

然后：

```text
.custom start = 0x401000
```

很多人第一反应：

> “怎么多了 4 KB？”

其实：

```text
0x40002D
     ↓
0x401000
```

padding：

```text
0x401000 - 0x40002D
=
0xFD3
=
4051 bytes
```

真正的原因是：

```text
.custom alignment = 4096
```

不是：

```text
.custom size = 4096
```

这是 linker 分析中非常重要的区别：

```text
Section Size
≠
Section Alignment
≠
Padding Size
```

---

# 四十五、实验 22-15：建立最终验证表

以后遇到任何 alignment 问题，直接做这张表：

| 层次             | 命令/位置                | 看什么                 |
| -------------- | -------------------- | ------------------- |
| Input Section  | `objdump -h foo.o`   | `Algn`              |
| Output Section | `readelf -S app.elf` | `Addr / Algn`       |
| Output Section | `objdump -h app.elf` | `VMA / Size / Algn` |
| Padding        | `map`                | `*fill*`            |
| 实际内容           | `objdump -s`         | padding 字节          |
| Segment        | `readelf -l`         | PT_LOAD             |
| 地址符号           | `nm -n`              | section 边界          |

这样你就不会再靠猜：

> “为什么这个地址是 0x401000？”

而是：

```text
Input Algn
     ↓
Output Algn
     ↓
Location Counter
     ↓
padding
     ↓
VMA
```

一步一步查。

---

# 四十六、今天必须掌握的语法区别

这是实验 22 的核心结论。

### ① Output Section Address

```ld
.text ALIGN(16) :
```

含义：

```text
ALIGN(16)
作为 Output Section address expression
```

**不是单纯设置 section alignment。**

---

### ② Output Section Alignment

```ld
.text : ALIGN(16)
{
    ...
}
```

含义：

```text
Output Section alignment = 16
```

---

### ③ Location Counter

```ld
.text :
{
    . = ALIGN(16);

    ...
}
```

含义：

```text
把当前 Location Counter
移动到 16-byte 对齐地址
```

---

### ④ Input Section Alignment

由：

```bash
objdump -h foo.o
```

中的：

```text
Algn
```

体现。

---

### ⑤ Input Section 的统一对齐

```ld
.custom : SUBALIGN(1)
{
    *(.foo)
    *(.bar)
}
```

控制：

```text
Output Section 内部
Input Section 的 alignment
```

---

### ⑥ Input-driven Alignment

```ld
.custom :
ALIGN_WITH_INPUT
{
    ...
}
```

用于让 Output Section 的对齐行为与 Input Section 的对齐关系保持一致。

---

# 四十七、把今天知识画成一张图

```text
                 GNU ld Alignment
                       │
        ┌──────────────┼──────────────┐
        │              │              │
        ▼              ▼              ▼
 Input Section    Output Section   Location Counter
     Algn             ALIGN()          .
        │              │               │
        │              │          . = ALIGN()
        │              │               │
        │              │               │
        └──────┬───────┴───────────────┘
               │
               ▼
             padding
               │
               ▼
             VMA
```

再加入：

```text
SUBALIGN()
```

就是：

```text
Output Section
      │
      ├── Input A
      ├── Input B
      └── Input C
             ↑
         SUBALIGN()
```

---

# 四十八、实验 22 最终版 linker script

可以把今天的实验浓缩成：

```ld
ENTRY(_start)

MEMORY
{
    ROM (rx) : ORIGIN = 0x00400000, LENGTH = 64K
}

SECTIONS
{
    .text : ALIGN(16)
    {
        *(.text)
        *(.text.*)
    } > ROM

    .custom : ALIGN(4096) SUBALIGN(1)
    {
        __custom_start = .;

        *(.foo)
        *(.bar)
        *(.baz)

        __custom_end = .;
    } > ROM

    ASSERT(
        (__custom_end - __custom_start) < 64K,
        "ERROR: custom section too large"
    );
}
```

这里：

```text
.text
    Output alignment = 16

.custom
    Output alignment = 4096
    Input alignment = 1

ASSERT
    检查最终大小
```

这已经是一个非常典型的 linker script 设计。

---

# 四十九、实验 22 的最终闭环

今天真正建立的是：

```text
C
│
├── __attribute__((section))
│
└── __attribute__((aligned))
          │
          ▼
       .o 文件
          │
          │ objdump -h
          ▼
   Input Section Alignment
          │
          ▼
     linker script
          │
    ┌─────┼─────┐
    │     │     │
 ALIGN SUBALIGN  .
    │     │     │
    └─────┼─────┘
          ▼
       padding
          │
          ▼
      Output Section
          │
          ▼
       ELF VMA
          │
     ┌────┴────┐
     ▼         ▼
  readelf    objdump
     │         │
     └────┬────┘
          ▼
        Map
```

这一步完成后，你已经不只是“知道 `ALIGN()` 怎么写”，而是可以从：

```text
Input Section
```

一路解释到：

```text
最终 ELF 地址
```

---

# 五十、下一实验：GNU ld 实战课程 · 实验 23

下一步我们进入一个非常漂亮、也非常实用的主题：

## `FILL()` + `AT()` + `LOADADDR()` + VMA/LMA：真正制作 ROM → RAM 的固件镜像

前面我们分别学过：

```text
VMA
LMA
AT()
LOADADDR()
.data
.bss
```

但还没有把它们组合成一个真正完整的：

```text
ROM
┌─────────────────────────────┐
│ .text                       │
│ .rodata                     │
│ .data LOAD IMAGE            │
│                             │
└─────────────────────────────┘
              │
              │ startup.S
              │ memcpy
              ▼
RAM
┌─────────────────────────────┐
│ .data                        │
│ .bss                         │
│ heap                         │
│ stack                        │
└─────────────────────────────┘
```

实验 23 会直接制作一个完整的：

```text
start.S
main.c
data.c
linker.ld
Makefile
```

并通过：

```bash
readelf -S
readelf -l
objdump -h
objdump -s
nm -n
objdump -d
```

以及：

```text
.map
```

逐字节验证：

```text
.data 的 VMA
.data 的 LMA
LOADADDR(.data)
ADDR(.data)
SIZEOF(.data)
AT(...)
```

最后让 `start.S` 真正执行：

```asm
memcpy(
    __data_start,
    __data_load_start,
    __data_size
);
```

这样就会把之前零散学习的：

```text
ALIGN
AT
LOADADDR
ADDR
SIZEOF
PROVIDE
ASSERT
VMA
LMA
```

第一次全部串成一个真正的**裸机启动流程**。

