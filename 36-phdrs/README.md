继续。上一节已经完成了 **实验 35：`MEMORY` → `ORIGIN/LENGTH` → `> REGION` → `VMA/LMA` → `AT > REGION` → `LOADADDR()` → `REGION_ALIAS`**。

现在正式进入下一大阶段：

# GNU ld 实战课程 · 实验 36

# `PHDRS`：从 Section 世界进入 Segment 世界

这一节非常重要，因为从这里开始，我们不再只研究：

```text
Section
```

而是开始研究 ELF 文件真正交给 Loader 的：

```text
Program Header / Segment
```

GNU ld 文档明确指出：ELF 的 Program Header 也就是 Segment，描述程序应该如何被加载到内存；如果 linker script 中出现 `PHDRS`，ld 就不会再自动创建其他 Program Header，而只使用你定义的那些。[sourceware.org](https://sourceware.org/binutils/docs-2.39/ld.pdf?utm_source=chatgpt.com)

---

# 一、本节要解决的核心问题

前面我们已经知道：

```text
.text
.rodata
.data
.bss
```

这些是：

```text
Section
```

但执行：

```bash
readelf -l firmware.elf
```

看到的却是：

```text
Program Headers:

  Type
  Offset
  VirtAddr
  PhysAddr
  FileSiz
  MemSiz
  Flg
  Align
```

为什么？

因为：

```text
ELF
├── Section Header Table
│     ├── .text
│     ├── .rodata
│     ├── .data
│     └── .bss
│
└── Program Header Table
      ├── LOAD
      ├── LOAD
      └── ...
```

两者解决的是不同问题。

---

# 二、Section 和 Segment 的本质区别

可以先记住这一句话：

> **Section 主要服务于链接器、编译器、调试器；Segment 主要服务于 Loader。**

例如：

```text
Section：

.text
.rodata
.data
.bss
```

而：

```text
Segment：

PT_LOAD
PT_LOAD
```

一个 Segment 可以包含多个 Section。

例如：

```text
LOAD RX
├── .text
└── .rodata

LOAD RW
├── .data
└── .bss
```

所以：

```text
Section
    ↓
可以被组织
    ↓
Segment
    ↓
Loader 根据 Segment 加载
```

GNU ld 官方文档也是按照这个模型定义 `PHDRS` 和 `:phdr` 的。[sourceware.org](https://sourceware.org/binutils/docs-2.41/ld.pdf?utm_source=chatgpt.com)

---

# 三、实验 36 的递进路线

这一节不要一次把所有 `PHDRS` 全部塞进去。

我们拆成：

```text
36-1  查看默认 Program Headers
  ↓
36-2  最小 PHDRS
  ↓
36-3  PT_LOAD
  ↓
36-4  :text / :data
  ↓
36-5  FLAGS()
  ↓
36-6  Section → Segment 映射
  ↓
36-7  FILEHDR / PHDRS
  ↓
36-8  AT() 与 Segment LMA
  ↓
36-9  :NONE
  ↓
36-10 解决 RWX Segment
  ↓
36-11 综合 ROM/RAM ELF
```

---

# 四、实验 36-1：先观察“默认行为”

先不要写 `PHDRS`。

使用上一节的工程。

目录：

```text
36-phdrs/
├── start.S
├── main.c
└── linker-default.ld
```

---

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

```c
volatile int counter = 42;

const char message[] = "GNU ld";

int main(void)
{
    counter++;
    return counter;
}
```

这里故意加入：

```c
const char message[] = "GNU ld";
```

这样可以产生：

```text
.rodata
```

同时：

```c
volatile int counter = 42;
```

产生：

```text
.data
```

---

# 五、基础 linker script

```ld
ENTRY(_start)

MEMORY
{
    FLASH (rx)  : ORIGIN = 0x00400000, LENGTH = 64K
    SRAM  (rwx) : ORIGIN = 0x00600000, LENGTH = 64K
}

SECTIONS
{
    .text :
    {
        *(.text.start)
        *(.text*)
    } > FLASH

    .rodata :
    {
        *(.rodata*)
    } > FLASH

    .data :
    {
        *(.data*)
    } > SRAM AT > FLASH

    .bss (NOLOAD) :
    {
        *(.bss*)
        *(COMMON)
    } > SRAM
}
```

---

# 六、编译

```bash
gcc -ffreestanding -c start.S main.c
```

然后：

```bash
ld \
    -T linker-default.ld \
    start.o \
    main.o \
    -o default.elf \
    -Map=default.map
```

---

# 七、第一次看 Program Header

执行：

```bash
readelf -l default.elf
```

或者：

```bash
objdump -p default.elf
```

重点观察：

```text
Program Headers:
```

以及：

```text
Section to Segment mapping:
```

这次先不要急着理解每一个字段。

你只需要发现：

```text
.text
.rodata
.data
.bss
```

最终被 ld 自动组织成了一些：

```text
LOAD
```

Segment。

这就是：

> **默认 Program Header。**

---

# 八、一个关键结论

没有：

```ld
PHDRS
```

的时候：

```text
ld
 │
 ├── 根据 Section
 │
 ├── 根据地址
 │
 ├── 根据权限
 │
 └── 自动生成 Program Headers
```

而一旦写：

```ld
PHDRS
{
    ...
}
```

就变成：

```text
ld
 │
 └── 使用你定义的 Program Headers
```

官方文档明确规定：使用 `PHDRS` 后，ld 不会再创建脚本之外的 Program Header。[sourceware.org](https://sourceware.org/binutils/docs-2.39/ld.pdf?utm_source=chatgpt.com)

这就是为什么：

> **`PHDRS` 是高级 linker script 的分水岭。**

---

# 九、实验 36-2：定义第一个 `PHDRS`

现在开始自己控制 Segment。

创建：

```text
linker-phdrs.ld
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
    data PT_LOAD FLAGS(6);
}

SECTIONS
{
    .text :
    {
        *(.text.start)
        *(.text*)
    } > FLASH :text

    .rodata :
    {
        *(.rodata*)
    } > FLASH :text

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

# 十、这里出现最重要的新语法

注意：

```ld
.text :
{
    ...
} > FLASH :text
```

最后这个：

```ld
:text
```

不是 Memory Region。

而是：

```text
PHDR 名称
```

也就是说：

```ld
PHDRS
{
    text PT_LOAD FLAGS(5);
}
```

定义：

```text
text
```

然后：

```ld
.text ... :text
```

表示：

> 把 `.text` 放入名为 `text` 的 Program Header / Segment。

官方语法就是 Output Section 后面的 `:phdr` 属性。[sourceware.org](https://sourceware.org/binutils/docs-2.39/ld.pdf?utm_source=chatgpt.com)

---

# 十一、为什么 `text` 不是 `.text`？

这是一个很容易混淆的地方。

这里存在两个完全不同的命名空间：

```text
.text
```

是：

```text
Output Section
```

而：

```text
text
```

是：

```text
PHDR name
```

所以：

```ld
PHDRS
{
    text PT_LOAD FLAGS(5);
}
```

和：

```ld
SECTIONS
{
    .text : ... :text
}
```

实际上是：

```text
Output Section
     │
     │ :text
     ▼
Program Header "text"
```

---

# 十二、`PT_LOAD` 是什么？

这里：

```ld
text PT_LOAD
```

表示：

```text
text Segment
      │
      ▼
PT_LOAD
```

`PT_LOAD` 的含义是：

> 这个 Program Header 描述一个应该从文件加载到内存的 Segment。

这是 ELF 最核心的 Segment 类型之一。[sourceware.org](https://sourceware.org/binutils/docs-2.41/ld.pdf?utm_source=chatgpt.com)

---

# 十三、`FLAGS(5)` 是什么？

这是本节另一个必须吃透的知识点。

ELF Segment Flags：

```text
PF_X = 1
PF_W = 2
PF_R = 4
```

因此：

```text
5 = 4 + 1
```

也就是：

```text
R + X
```

所以：

```ld
text PT_LOAD FLAGS(5);
```

表示：

```text
LOAD
R-X
```

而：

```ld
data PT_LOAD FLAGS(6);
```

因为：

```text
6 = 4 + 2
```

所以：

```text
R-W
```

最终：

```text
text → R-X
data → R-W
```

---

# 十四、为什么我们故意不用 `FLAGS(7)`？

因为：

```text
7 = R + W + X
```

也就是：

```text
RWX
```

这意味着：

```text
代码可执行
数据可写
```

全部在同一个 Segment 权限里。

现代 ELF/Linux 环境通常希望避免不必要的：

```text
RWX
```

Segment。

而我们前面实验中遇到的：

```text
LOAD segment with RWX permissions
```

就是这个问题。

现在终于可以自己控制它。

---

# 十五、重新链接

```bash
ld \
    -T linker-phdrs.ld \
    start.o \
    main.o \
    -o phdrs01.elf \
    -Map=phdrs01.map
```

---

# 十六、核心验证：`readelf -l`

```bash
readelf -lW phdrs01.elf
```

重点看：

```text
Program Headers:
```

应该出现类似：

```text
Type   Offset   VirtAddr   PhysAddr   FileSiz   MemSiz   Flg   Align

LOAD   ...      0x00400000 ...        ...       ...      R E   ...
LOAD   ...      0x00600000 ...        ...       ...      RW    ...
```

不同平台、binutils 版本以及你的实际 section 大小可能导致 Offset、Size、Align 不同，不要死记具体数字。

真正需要验证的是：

```text
LOAD #1
    R E
    .text
    .rodata

LOAD #2
    RW
    .data
    .bss
```

---

# 十七、`readelf -lW` 为什么比 `readelf -SW` 更重要？

现在做一个对照：

```bash
readelf -SW phdrs01.elf
```

这是：

```text
Section Header Table
```

而：

```bash
readelf -lW phdrs01.elf
```

这是：

```text
Program Header Table
```

所以：

```text
-S
```

回答：

> **有哪些 Section？**

而：

```text
-l
```

回答：

> **Loader 应该加载哪些 Segment？**

---

# 十八、建立这张核心对照表

| 工具 | 主要看什么 |
|---|---|
| `readelf -S` | Section |
| `readelf -l` | Segment / Program Header |
| `objdump -h` | Section + VMA/LMA |
| `objdump -p` | Program Header |
| `nm` | Symbol |
| `Map` | Linker 的完整布局账本 |

以后分析 ELF，建议固定执行：

```bash
readelf -SW xxx.elf
readelf -lW xxx.elf
objdump -h xxx.elf
objdump -p xxx.elf
nm -n xxx.elf
```

五个视角一起看。

---

# 十九、实验 36-3：Section → Segment 映射

执行：

```bash
readelf -lW phdrs01.elf
```

最后应该能看到：

```text
Section to Segment mapping:
  Segment Sections...
   00     .text .rodata
   01     .data .bss
```

这就是本实验真正的核心结果。

形成：

```text
.text
.rodata
    │
    ▼
 text PT_LOAD
    │
    ▼
 R-X

.data
.bss
    │
    ▼
 data PT_LOAD
    │
    ▼
 RW
```

---

# 二十、Map 文件再验证一次

```bash
grep -A20 -B3 '\.text' phdrs01.map
```

然后：

```bash
grep -A20 -B3 '\.data' phdrs01.map
```

你应该同时建立两个维度：

```text
Map
 ↓
Section Layout
```

以及：

```text
readelf -l
 ↓
Segment Layout
```

也就是说：

```text
Map
 └── 告诉你 Section 如何排

readelf -l
 └── 告诉你 Loader 如何看
```

---

# 二十一、实验 36-4：理解“继承”规则

这是 `PHDRS` 中一个很容易踩坑的地方。

假设：

```ld
.text : { *(.text*) } > FLASH :text

.rodata : { *(.rodata*) } > FLASH
```

注意：

`.rodata` 没有写：

```text
:text
```

会发生什么？

GNU ld 对 `:phdr` 有一个便利规则：

> 一旦一个 Output Section 被放入某个 Segment，后续没有明确指定 `:phdr` 的可分配 Section 会继续进入相同 Segment。

官方文档明确说明了这个继承行为。[sourceware.org](https://sourceware.org/binutils/docs-2.37/ld.pdf?utm_source=chatgpt.com)

所以：

```ld
.text : ... :text

.rodata : ...
```

实际上很可能形成：

```text
text LOAD
├── .text
└── .rodata
```

---

# 二十二、如果不想继承怎么办？

使用：

```ld
:NONE
```

例如：

```ld
.note :
{
    *(.note*)
} :NONE
```

意思：

> 这个 Section 不放进任何 Program Header。

官方文档也明确提供了 `:NONE` 用来覆盖默认 Segment 继承行为。[sourceware.org](https://sourceware.org/binutils/docs-2.37/ld.pdf?utm_source=chatgpt.com)

---

# 二十三、实验 36-5：`FILEHDR` 与 `PHDRS`

现在进入一个很重要的 ELF 结构问题。

ELF 文件开头：

```text
+----------------------+
| ELF Header           |
+----------------------+
| Program Header Table |
+----------------------+
| Sections...           |
+----------------------+
```

而：

```ld
FILEHDR
```

表示：

> 这个 Segment 包含 ELF File Header。

而：

```ld
PHDRS
```

表示：

> 这个 Segment 包含 Program Header Table。

官方文档明确规定了这两个关键字的含义。[sourceware.org](https://sourceware.org/binutils/docs-2.41/ld.pdf?utm_source=chatgpt.com)

---

# 二十四、尝试：

```ld
PHDRS
{
    text PT_LOAD FILEHDR PHDRS FLAGS(5);
    data PT_LOAD FLAGS(6);
}
```

然后：

```ld
.text :
{
    *(.text.start)
    *(.text*)
} > FLASH :text
```

这里：

```text
FILEHDR
PHDRS
```

告诉 ld：

```text
text Segment
 ├── ELF Header
 ├── Program Header Table
 └── .text / .rodata
```

---

# 二十五、这里有一个非常重要的约束

如果一个 `PT_LOAD` Segment 使用：

```ld
PHDRS
```

或者：

```ld
FILEHDR
```

相关布局，那么前面的 Load Segment 也必须满足相应的头部覆盖关系，否则 ld 可能拒绝布局。

这就是为什么你之前做：

```text
PHDRS
```

实验时容易出现：

```text
section can't be allocated in segment
```

或者：

```text
not enough room for program headers
```

之类的问题。

不要把它理解成“ld 很玄学”。

实际上是：

```text
ELF Header
Program Header Table
Section
Segment
地址
文件 Offset
对齐
```

这些约束互相打架了。

---

# 二十六、实验 36-6：观察 `AT()` 与 Program Header

上一节我们学：

```ld
.data > SRAM AT > FLASH
```

现在再向前一步。

我们知道：

```text
.data
VMA = SRAM
LMA = FLASH
```

那么：

```text
Program Header
```

也必须知道：

```text
File Offset
Physical Address
Virtual Address
File Size
Memory Size
```

所以：

```bash
readelf -lW phdrs01.elf
```

特别关注：

```text
VirtAddr
PhysAddr
FileSiz
MemSiz
```

你会开始看到：

```text
.data
```

对应的 Segment：

```text
VirtAddr ≈ SRAM
PhysAddr ≈ FLASH
```

具体是否显示成你预期的形式，取决于目标 ELF 类型及 linker script 的完整布局，所以这里不要机械记住字段值。

---

# 二十七、VMA/LMA 到 Program Header 的关系

现在把前面两个实验串起来：

```text
Section

.data
│
├── VMA
│     ↓
│    SRAM
│
└── LMA
      ↓
     FLASH
```

再往上：

```text
Segment

PT_LOAD
│
├── VirtAddr
│      ↓
│     SRAM
│
├── PhysAddr
│      ↓
│     FLASH
│
├── FileSiz
│      ↓
│     ROM image 中实际存在的数据
│
└── MemSiz
       ↓
      RAM 中运行时需要的空间
```

这一步非常关键。

因为：

```text
FileSiz
```

和：

```text
MemSiz
```

开始解释：

```text
.bss
```

为什么：

```text
.bss
```

没有实际文件内容，却需要运行时内存。

---

# 二十八、`.data` 和 `.bss` 的经典模型

例如：

```text
.data
FileSiz:
100 bytes

MemSiz:
100 bytes
```

而：

```text
.bss
FileSiz:
0

MemSiz:
400 bytes
```

所以 Segment 可能表现为：

```text
LOAD RW

File:
┌────────────────┐
│ .data 100 bytes│
└────────────────┘

Memory:
┌────────────────┐
│ .data 100      │
├────────────────┤
│ .bss  400      │
└────────────────┘
```

也就是说：

```text
MemSiz > FileSiz
```

多出来的部分由 Loader 在内存中提供。

这就是 ELF 世界中：

> **NOBITS / `.bss` 不占文件存储空间，但占运行时内存。**

---

# 二十九、实验 36-7：故意制造 RWX

现在做一个非常有价值的反例。

把：

```ld
PHDRS
{
    all PT_LOAD FLAGS(7);
}
```

然后：

```ld
.text : { *(.text*) } > FLASH :all

.rodata : { *(.rodata*) } > FLASH :all

.data : { *(.data*) } > SRAM AT > FLASH :all

.bss : { *(.bss*) } > SRAM :all
```

链接：

```bash
ld \
    -T linker-rwx.ld \
    start.o \
    main.o \
    -o rwx.elf \
    -Map=rwx.map
```

然后：

```bash
readelf -lW rwx.elf
```

你会看到：

```text
LOAD
RWE
```

或者相关的 RWX 权限表现。

这就是：

```text
一个 Segment
    ↓
代码
+
数据
+
可写
+
可执行
```

---

# 三十、为什么之前经常出现：

```text
LOAD segment with RWX permissions
```

现在答案非常清楚了。

并不是：

```text
.text
```

本身突然变成 RWX。

而是：

```text
.text
.data
.bss
```

被放进了：

```text
同一个 PT_LOAD
```

而这个 Segment：

```text
FLAGS(7)
```

所以最终：

```text
PT_LOAD
RWE
```

---

# 三十一、实验 36-8：正确拆成 RX + RW

恢复：

```ld
PHDRS
{
    text PT_LOAD FLAGS(5);
    data PT_LOAD FLAGS(6);
}
```

然后：

```ld
.text :
{
    *(.text.start)
    *(.text*)
} > FLASH :text

.rodata :
{
    *(.rodata*)
} > FLASH :text

.data :
{
    *(.data*)
} > SRAM AT > FLASH :data

.bss (NOLOAD) :
{
    *(.bss*)
    *(COMMON)
} > SRAM :data
```

最终：

```text
PT_LOAD #1
R E
├── .text
└── .rodata

PT_LOAD #2
RW
├── .data
└── .bss
```

这才是我们希望建立的基本模型。

---

# 三十二、为什么 `.rodata` 放 RX？

这里不要过度绝对化。

在我们这个实验里：

```text
.rodata
```

属于：

```text
FLASH
```

因此它跟：

```text
.text
```

一起进入：

```text
R-X
```

Segment。

但：

```text
.rodata
```

本质上并不需要执行权限。

更严格的系统可以继续拆：

```text
RX
├── .text

R
├── .rodata

RW
├── .data
└── .bss
```

那么就需要：

```text
3 个 PT_LOAD
```

这正好是后面实验的进阶方向。

---

# 三十三、实验 36-9：三个 Segment

尝试：

```ld
PHDRS
{
    text PT_LOAD FLAGS(5);
    ro   PT_LOAD FLAGS(4);
    data PT_LOAD FLAGS(6);
}
```

对应：

```ld
.text :
{
    *(.text*)
} > FLASH :text

.rodata :
{
    *(.rodata*)
} > FLASH :ro

.data :
{
    *(.data*)
} > SRAM AT > FLASH :data

.bss (NOLOAD) :
{
    *(.bss*)
    *(COMMON)
} > SRAM :data
```

最终：

```text
LOAD R-X
└── .text

LOAD R--
└── .rodata

LOAD RW-
├── .data
└── .bss
```

这是一个非常接近现代 ELF 权限隔离思想的布局。

---

# 三十四、但这里会遇到一个新的坑

你很可能发现：

```text
Segment
Segment
Segment
```

之间产生了：

```text
padding
```

或者：

```text
unexpected addresses
```

甚至出现：

```text
section ... can't be allocated in segment
```

不要马上认为 linker script 写错。

因为：

> **Segment 还受到文件 Offset、VMA、LMA、Alignment 的共同约束。**

特别是：

```text
p_align
```

会影响 Segment 的对齐。

执行：

```bash
readelf -lW xxx.elf
```

最后一个字段：

```text
Align
```

就是：

```text
p_align
```

---

# 三十五、实验 36-10：Map + readelf 双重分析法

这一节开始，建议以后所有复杂 linker 问题都采用这个流程：

### 第一步：Section

```bash
readelf -SW xxx.elf
```

回答：

```text
Section 在哪里？
多大？
什么权限？
```

---

### 第二步：VMA/LMA

```bash
objdump -h xxx.elf
```

回答：

```text
VMA？
LMA？
File Offset？
Size？
```

---

### 第三步：Segment

```bash
readelf -lW xxx.elf
```

回答：

```text
Segment？
VirtAddr？
PhysAddr？
FileSiz？
MemSiz？
Flags？
Align？
```

---

### 第四步：映射

看：

```text
Section to Segment mapping
```

回答：

```text
哪个 Section 进入哪个 Segment？
```

---

### 第五步：Map

```bash
less xxx.map
```

回答：

```text
这个地址到底是谁分配出来的？
```

---

# 三十六、形成一个完整的 ELF 分析链

以后看到任何奇怪的 ld 问题：

```text
              linker.ld
                  │
                  ▼
             ld 分配地址
                  │
       ┌──────────┴──────────┐
       ▼                     ▼
    Section                 Segment
       │                     │
       │                     │
       ▼                     ▼
readelf -S              readelf -l
       │                     │
       ▼                     ▼
 VMA / LMA               LOAD
       │                     │
       └──────────┬──────────┘
                  ▼
                ELF
                  │
                  ▼
              Loader
```

这就是以后分析：

```text
firmware
bootloader
kernel
UEFI
ELF executable
shared object
```

的基础。

---

# 三十七、一个非常重要的实验：`objdump -p`

除了：

```bash
readelf -lW
```

再执行：

```bash
objdump -p phdrs01.elf
```

你会看到 Program Header 相关信息。

因此：

```text
readelf -l
```

和：

```text
objdump -p
```

可以交叉验证。

推荐以后：

```bash
readelf -lW xxx.elf
objdump -p xxx.elf
```

一起看。

---

# 三十八、`PHDRS` 的语法总结

目前我们真正掌握的已经是：

```ld
PHDRS
{
    name type
        [FILEHDR]
        [PHDRS]
        [AT(address)]
        [FLAGS(flags)];
}
```

例如：

```ld
PHDRS
{
    text PT_LOAD FLAGS(5);
    ro   PT_LOAD FLAGS(4);
    data PT_LOAD FLAGS(6);
}
```

然后：

```ld
SECTIONS
{
    .text : { ... } :text

    .rodata : { ... } :ro

    .data : { ... } :data

    .bss : { ... } :data
}
```

建立：

```text
Section
   │
   │ :phdr
   ▼
PHDR
   │
   ▼
PT_LOAD
```

---

# 三十九、这一节最重要的四个符号

一定不要混淆：

```text
> FLASH
```

```text
AT > FLASH
```

```text
:text
```

```text
FLAGS(5)
```

它们分别属于四个完全不同的概念：

| 写法 | 含义 |
|---|---|
| `> FLASH` | Output Section 的运行 Memory Region |
| `AT > FLASH` | Output Section 的 Load Memory Region |
| `:text` | 把 Section 放入名为 `text` 的 PHDR |
| `FLAGS(5)` | Segment 的 ELF 权限 |

所以：

```ld
.data > SRAM AT > FLASH :data
```

可以完整翻译成：

> `.data` 运行在 SRAM，把初始化镜像放在 FLASH，并把它归入 `data` 这个 Program Header。

这一句话建议直接记下来。

---

# 四十、实验 36 最终综合版

最后建立：

```text
linker-final.ld
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

PROVIDE(__flash_start = ORIGIN(FLASH));
PROVIDE(__flash_end =
        ORIGIN(FLASH) + LENGTH(FLASH));

PROVIDE(__ram_start = ORIGIN(SRAM));
PROVIDE(__ram_end =
        ORIGIN(SRAM) + LENGTH(SRAM));

SECTIONS
{
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

注意这里继续使用我们之前纠正过的正确 `ALIGN()` 形式：

```ld
.text :
{
    . = ALIGN(16);
```

而不是：

```ld
.text ALIGN(16) :
```

---

# 四十一、完整实验命令

```bash
rm -f *.o *.elf *.map
```

编译：

```bash
gcc -ffreestanding -c start.S main.c
```

链接：

```bash
ld \
    -T linker-final.ld \
    start.o \
    main.o \
    -o firmware36.elf \
    -Map=firmware36.map
```

---

## Section

```bash
readelf -SW firmware36.elf
```

---

## Segment

```bash
readelf -lW firmware36.elf
```

---

## VMA/LMA

```bash
objdump -h firmware36.elf
```

---

## Program Header

```bash
objdump -p firmware36.elf
```

---

## Symbol

```bash
nm -n firmware36.elf
```

---

## Map

```bash
less firmware36.map
```

---

# 四十二、你最终应该得到的逻辑结构

```text
                         firmware36.elf
                               │
              ┌────────────────┴────────────────┐
              │                                 │
          Section Table                    Program Header
              │                                 │
      ┌───────┼────────┐              ┌─────────┼─────────┐
      │       │        │              │         │         │
    .text   .rodata   .data          text       ro        data
      │       │        │              │         │         │
      │       │        │              ▼         ▼         ▼
      │       │        │            PT_LOAD   PT_LOAD   PT_LOAD
      │       │        │              R-X       R--       RW-
      │       │        │
      │       │        └──── VMA → SRAM
      │       │
      │       └───────────── FLASH
      │
      └───────────────────── FLASH
```

其中：

```text
.data
```

尤其特殊：

```text
.data
 ├── VMA → SRAM
 └── LMA → FLASH
```

而对应的：

```text
data PT_LOAD
```

则负责告诉 Loader：

```text
文件中有多少数据？
运行时需要多少内存？
应该放到哪里？
```

---

# 四十三、这就是之前那些报错的“统一解释器”

你之前碰到过：

```text
LOAD segment with RWX permissions
```

现在：

```text
PHDRS + FLAGS
```

可以解释。

你之前碰到：

```text
section '.bss' can't be allocated in segment
```

现在：

```text
Section → Segment mapping
```

可以解释。

你之前碰到：

```text
not enough room for program headers
```

现在：

```text
ELF Header
Program Header Table
Segment
Address
Alignment
```

可以解释。

你之前碰到：

```text
.data
VMA/LMA
```

现在：

```text
AT > FLASH
```

可以解释。

也就是说，前面的 `MEMORY / AT / VMA / LMA` 和现在的 `PHDRS` 并不是两个独立章节，而是终于连接起来了。

---

# 四十四、实验 36 的“毕业题”

建议不要只运行成功就结束。

自己完成下面这个挑战：

要求最终生成：

```text
Segment 1:
R-X
.text

Segment 2:
R--
.rodata

Segment 3:
RW-
.data
.bss
```

并满足：

```text
.text   → FLASH
.rodata → FLASH

.data   → SRAM
.data LMA → FLASH

.bss    → SRAM
.bss    NOLOAD
```

然后用：

```bash
readelf -SW firmware36.elf
readelf -lW firmware36.elf
objdump -h firmware36.elf
objdump -p firmware36.elf
nm -n firmware36.elf
```

证明你的 linker script 确实实现了这一布局。

---

# 四十五、下一阶段路线

到这里，GNU ld 课程已经从：

```text
Section 操作
```

正式进入：

```text
ELF Segment / Loader
```

接下来继续递进：

```text
实验 37
PHDRS + FILEHDR + PHDRS + SIZEOF_HEADERS
        │
        ▼
ELF Header / Program Header Table
        │
        ▼
实验 38
PT_LOAD + AT() + VMA/LMA
        │
        ▼
实验 39
p_filesz / p_memsz / .bss
        │
        ▼
实验 40
Segment Alignment + MAXPAGESIZE
        │
        ▼
实验 41
解决 RWX / W^X
        │
        ▼
实验 42
多个 LOAD Segment 的精确布局
        │
        ▼
实验 43
OVERLAY
        │
        ▼
实验 44
NOCROSSREFS + ASSERT 综合约束
        │
        ▼
实验 45
启动代码 + .data 拷贝 + .bss 清零
        │
        ▼
实验 46
制作真正的 Bare-metal Firmware Image
        │
        ▼
实验 47
objcopy → BIN / HEX
        │
        ▼
实验 48
分析真实 MCU Linker Script
```

其中 **实验 37** 会特别值得做：我们将直接把 `readelf -lW` 输出中的：

```text
Elf file type
Entry point
Program Headers
PHDR
INTERP
LOAD
```

逐字段拆开，并自己控制：

```ld
FILEHDR
PHDRS
SIZEOF_HEADERS
```

然后再回头解释你之前遇到的 **“section `.bss` can't be allocated in segment”** 到底是 ld 在检查什么。

这一步之后，你基本就从“会用 linker script”进入到“能读懂复杂真实工程 linker script”的阶段了。 [sourceware.org](https://sourceware.org/binutils/docs/ld.pdf?utm_source=chatgpt.com)

### 官方参考

[GNU ld 官方 Linker Scripts 文档](https://sourceware.org/binutils/docs/ld/?utm_source=chatgpt.com)

其中 `PHDRS`、`PT_LOAD`、`FILEHDR`、`PHDRS` 和 `:phdr` 的定义与本实验一致。[sourceware.org](https://sourceware.org/binutils/docs-2.39/ld.pdf?utm_source=chatgpt.com)
