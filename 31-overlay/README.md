# GNU ld 实战课程 · 实验 31

# `OVERLAY` + `AT` + `LOADADDR()`：真正理解 VMA / LMA 与 Overlay

上一节实验 30，我们把 GNU `ld` 从“地址计算器”进一步升级成了**架构检查器**：

```text
ASSERT()
    ↓
容量约束

NOCROSSREFS()
    ↓
双向隔离

NOCROSSREFS_TO()
    ↓
单向依赖约束
```

这一节继续沿着之前的路线，进入 GNU ld 一个非常经典、也非常容易混淆的高级机制：

# `OVERLAY`

它把我们前面学过的：

```text
VMA
LMA
AT
LOADADDR()
SIZEOF()
NOCROSSREFS()
```

真正组合起来。

GNU ld 官方文档规定，`OVERLAY` 中的各个 Output Section **具有相同的起始运行地址（VMA）**，但它们的 Load Address（LMA）在存储介质中依次排列；linker 还会自动提供每个 overlay 的 `__load_start_<section>` 和 `__load_stop_<section>` 符号。([Sourceware][1])

---

# 一、先建立一个直觉

普通程序：

```text
Flash
┌──────────────────────┐
│ code A               │
├──────────────────────┤
│ code B               │
├──────────────────────┤
│ code C               │
└──────────────────────┘

RAM
┌──────────────────────┐
│ A                    │
├──────────────────────┤
│ B                    │
├──────────────────────┤
│ C                    │
└──────────────────────┘
```

A、B、C 同时占用 RAM。

但如果：

```text
A、B、C 永远不会同时运行
```

那么可以让它们：

```text
共用同一块 RAM
```

变成：

```text
Flash
┌──────────────────────┐
│ A image              │
├──────────────────────┤
│ B image              │
├──────────────────────┤
│ C image              │
└──────────────────────┘
          │
          │ copy A
          ▼
RAM
┌──────────────────────┐
│ Overlay Area         │
│                      │
│ A / B / C             │
│ 只能同时存在一个      │
└──────────────────────┘
```

这就是 Overlay。

GDB 对 Overlay 的定义也非常清晰：**mapped address** 就是运行时地址，也就是 VMA；**load address** 是存储镜像所在地址，也就是 LMA。([Sourceware][2])

---

# 二、实验 31 的最终目标

我们构造三个模块：

```text
overlay_a.c
overlay_b.c
overlay_c.c
```

它们分别进入：

```text
.ov_a
.ov_b
.ov_c
```

最终：

```text
VMA：

.ov_a ──────┐
.ov_b ──────┼── 0x00610000
.ov_c ──────┘
```

也就是说：

```text
运行地址完全相同
```

但是：

```text
LMA：

.ov_a → Flash + 0x0000
.ov_b → Flash + 0x0200
.ov_c → Flash + 0x0400
```

于是：

```text
VMA ≠ LMA
```

而且：

```text
VMA(.ov_a)
=
VMA(.ov_b)
=
VMA(.ov_c)
```

---

# 三、实验工程

建立：

```text
lab31/
├── start.S
├── main.c
├── overlay_a.c
├── overlay_b.c
├── overlay_c.c
└── linker.ld
```

---

# 四、实验 31-1：Overlay A

`overlay_a.c`：

```c
__attribute__((section(".ov_a")))
int overlay_a(void)
{
    return 1001;
}
```

---

# 五、Overlay B

`overlay_b.c`：

```c
__attribute__((section(".ov_b")))
int overlay_b(void)
{
    return 2002;
}
```

---

# 六、Overlay C

`overlay_c.c`：

```c
__attribute__((section(".ov_c")))
int overlay_c(void)
{
    return 3003;
}
```

注意：

三个函数都没有互相调用。

这一点非常重要。

因为 Overlay 的基本思想就是：

```text
A
B
C
```

可以在运行时：

```text
A loaded
B unloaded

或者：

B loaded
A unloaded
```

所以 Overlay 之间通常不能存在直接引用。

GNU ld 的 `OVERLAY ... NOCROSSREFS` 就是为这种情况设计的。官方文档明确指出，同一个 Overlay 内各 Section 使用相同运行地址，因此它们之间直接引用通常没有意义。([Sourceware][3])

---

# 七、`main.c`

先简单：

```c
int main(void)
{
    return 0;
}
```

---

# 八、`start.S`

继续使用我们的实验启动代码：

```asm
.global _start

.extern main

.text

_start:
    call main

.hang:
    hlt
    jmp .hang
```

---

# 九、编译

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
    -c overlay_a.c \
    -o overlay_a.o
```

```bash
gcc \
    -ffreestanding \
    -fno-pie \
    -fno-stack-protector \
    -ffunction-sections \
    -fdata-sections \
    -c overlay_b.c \
    -o overlay_b.o
```

```bash
gcc \
    -ffreestanding \
    -fno-pie \
    -fno-stack-protector \
    -ffunction-sections \
    -fdata-sections \
    -c overlay_c.c \
    -o overlay_c.o
```

---

# 十、实验 31-2：先看 Input Section

执行：

```bash
objdump -h overlay_a.o
```

重点：

```text
.ov_a
```

然后：

```bash
objdump -h overlay_b.o
```

应该看到：

```text
.ov_b
```

以及：

```bash
objdump -h overlay_c.o
```

看到：

```text
.ov_c
```

此时还是：

```text
Input Section
```

还没有 Overlay。

---

# 十一、先不用 `OVERLAY`

我们先手工做一个普通布局：

```ld
ENTRY(_start)

MEMORY
{
    ROM (rx) :
        ORIGIN = 0x00400000,
        LENGTH = 64K

    RAM (rwx) :
        ORIGIN = 0x00600000,
        LENGTH = 64K
}

SECTIONS
{
    .text :
    {
        *(.text)
        *(.text.*)
    } > ROM

    .ov_a :
    {
        *(.ov_a)
    } > RAM AT > ROM

    .ov_b :
    {
        *(.ov_b)
    } > RAM AT > ROM

    .ov_c :
    {
        *(.ov_c)
    } > RAM AT > ROM
}
```

---

# 十二、链接

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    overlay_a.o \
    overlay_b.o \
    overlay_c.o \
    -o normal-overlay.elf \
    -Map=normal-overlay.map
```

---

# 十三、观察 VMA / LMA

```bash
objdump -h normal-overlay.elf
```

你会发现：

```text
.ov_a
.ov_b
.ov_c
```

默认情况下会：

```text
VMA 递增
LMA 递增
```

类似：

```text
.ov_a
VMA = 0x00600000
LMA = 0x004000xx

.ov_b
VMA = 0x00600004
LMA = 0x004000xx

.ov_c
VMA = 0x00600008
LMA = 0x004000xx
```

所以：

```text
A
B
C
```

仍然占据不同的 RAM 地址。

---

# 十四、我们真正需要的是：

```text
.ov_a
VMA = 0x00610000

.ov_b
VMA = 0x00610000

.ov_c
VMA = 0x00610000
```

也就是：

```text
同一个运行地址。
```

但是：

```text
LMA：

A = Flash + 0
B = Flash + sizeof(A)
C = Flash + sizeof(A) + sizeof(B)
```

这就是：

# OVERLAY。

---

# 十五、实验 31-3：第一次使用 `OVERLAY`

修改 linker：

```ld
ENTRY(_start)

MEMORY
{
    ROM (rx) :
        ORIGIN = 0x00400000,
        LENGTH = 64K

    RAM (rwx) :
        ORIGIN = 0x00600000,
        LENGTH = 64K
}

SECTIONS
{
    .text :
    {
        *(.text)
        *(.text.*)
    } > ROM

    OVERLAY 0x00610000 :
    {
        .ov_a
        {
            *(.ov_a)
        }

        .ov_b
        {
            *(.ov_b)
        }

        .ov_c
        {
            *(.ov_c)
        }
    } AT(0x00401000) > RAM
}
```

这里有三个非常关键的数字：

```text
VMA = 0x00610000

LMA = 0x00401000
```

---

# 十六、注意 `OVERLAY` 的语法

这里：

```ld
OVERLAY 0x00610000 :
{
    .ov_a
    {
        *(.ov_a)
    }

    .ov_b
    {
        *(.ov_b)
    }
} AT(0x00401000) > RAM
```

不要写成：

```ld
.ov_a 0x00610000 :
```

因为 Overlay 内部 Section：

> **不能单独指定地址和 MEMORY Region。**

GNU ld 官方语法明确规定，Overlay 内部的 Section 定义不能自己指定地址或 Memory Region。([Sourceware][1])

---

# 十七、链接

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

# 十八、第一件事：`readelf -SW`

```bash
readelf -SW overlay.elf
```

找到：

```text
.ov_a
.ov_b
.ov_c
```

重点观察：

```text
Address
Offset
Size
```

你应该看到一个非常有意思的现象：

```text
.ov_a Address ≈ 0x00610000
.ov_b Address ≈ 0x00610000
.ov_c Address ≈ 0x00610000
```

三个 Section 的：

# VMA 相同。

---

# 十九、第二件事：`objdump -h`

```bash
objdump -h overlay.elf
```

这里比 `readelf -SW` 更适合直观看：

```text
VMA
LMA
Size
```

你应该看到类似：

```text
.ov_a
VMA = 0x00610000
LMA = 0x00401000

.ov_b
VMA = 0x00610000
LMA = 0x00401000 + SIZEOF(.ov_a)

.ov_c
VMA = 0x00610000
LMA = 0x00401000 + SIZEOF(.ov_a) + SIZEOF(.ov_b)
```

这就是 Overlay 的核心。

---

# 二十、Overlay 的内存模型

最终：

```text
             Flash / ROM

0x00401000
    │
    ├───────────────┐
    │ .ov_a         │
    │               │
    ├───────────────┤
    │ .ov_b         │
    │               │
    ├───────────────┤
    │ .ov_c         │
    │               │
    └───────────────┘


             RAM

0x00610000
    │
    ├───────────────┐
    │ Overlay Area  │
    │               │
    │ A OR B OR C   │
    │               │
    └───────────────┘
```

---

# 二十一、这就是 VMA / LMA 的真正意义

以前我们学：

```text
VMA
=
运行地址

LMA
=
加载地址
```

现在终于有了一个非常典型的实际应用。

对于 `.ov_b`：

```text
VMA:
0x00610000
```

表示：

> CPU 执行 `overlay_b()` 时，它应该位于这里。

而：

```text
LMA:
0x00401000 + size(A)
```

表示：

> Firmware 镜像中，B 的原始数据存放在那里。

---

# 二十二、实验 31-4：验证三个函数地址

```bash
nm -n overlay.elf
```

搜索：

```bash
nm -n overlay.elf | grep overlay_
```

你应该看到：

```text
0000000000610000 T overlay_a
0000000000610000 T overlay_b
0000000000610000 T overlay_c
```

这里非常震撼：

```text
三个不同函数
三个不同的 Section
同一个 VMA。
```

这正是 Overlay。

---

# 二十三、为什么不会产生 Symbol 地址冲突？

因为 Overlay 的设计就是：

```text
A 在运行时占用这里
```

然后：

```text
A unload
```

再：

```text
B load
```

于是：

```text
同一个地址
```

在不同时间代表：

```text
A
```

或者：

```text
B
```

或者：

```text
C
```

GDB 的 Overlay 文档也明确说明，多个 Overlay 可以共享同一个 mapped address，但同一时间通常只能有一个 Overlay 被映射到那里。([Sourceware][4])

---

# 二十四、实验 31-5：查看自动生成的 Overlay Symbol

这是这一节最重要的实验之一。

执行：

```bash
nm -n overlay.elf | grep __load
```

你应该看到类似：

```text
__load_start_ov_a
__load_stop_ov_a

__load_start_ov_b
__load_stop_ov_b

__load_start_ov_c
__load_stop_ov_c
```

GNU ld 会自动为 Overlay 中每个 Section 提供：

```text
__load_start_secname
__load_stop_secname
```

这些符号分别代表该 Overlay Section 的 LMA 起始和结束位置。([Sourceware][1])

---

# 二十五、用 `readelf -sW` 再验证一次

```bash
readelf -sW overlay.elf | grep __load
```

重点看：

```text
Value
Bind
Vis
Ndx
Name
```

例如：

```text
__load_start_ov_a
__load_stop_ov_a
```

这些就是：

# Overlay Runtime Copy API。

---

# 二十六、为什么叫 `__load_start`？

因为：

```text
__load_start_ov_a
```

不是：

```text
VMA
```

而是：

```text
LMA
```

也就是：

```text
Flash 中 A 的起始地址。
```

因此：

```c
extern char __load_start_ov_a;
extern char __load_stop_ov_a;
```

可以得到：

```text
Flash A image
```

的范围。

---

# 二十七、计算 Overlay 大小

```c
size_t size =
    &__load_stop_ov_a -
    &__load_start_ov_a;
```

得到：

```text
A 的镜像大小。
```

然后：

```c
memcpy(
    (void *)0x00610000,
    &__load_start_ov_a,
    size
);
```

就可以把：

```text
Flash A
```

复制到：

```text
RAM Overlay Area
```

---

# 二十八、这其实就是官方推荐模型

GNU ld 文档给出的 Overlay 示例本质就是：

```c
extern char __load_start_text1;
extern char __load_stop_text1;

memcpy(
    (char *)0x1000,
    &__load_start_text1,
    &__load_stop_text1 -
    &__load_start_text1
);
```

也就是说：

```text
LMA
 ↓
copy
 ↓
VMA
```

([Sourceware][5])

---

# 二十九、实验 31-6：自己定义 Overlay Manager

我们先不真正运行，因为当前实验使用的是 x86-64 ELF 裸链接环境。

但可以写出真实 Firmware 的伪代码：

```c
typedef void (*overlay_entry_t)(void);

extern char __load_start_ov_a;
extern char __load_stop_ov_a;

#define OVERLAY_RAM ((void *)0x00610000)

void load_overlay_a(void)
{
    size_t size =
        &__load_stop_ov_a -
        &__load_start_ov_a;

    memcpy(
        OVERLAY_RAM,
        &__load_start_ov_a,
        size
    );
}

void run_overlay_a(void)
{
    load_overlay_a();

    overlay_entry_t fn =
        (overlay_entry_t)OVERLAY_RAM;

    fn();
}
```

真实 MCU 中通常还会涉及：

```text
Instruction Cache
Data Cache
Memory Barrier
Flash controller
DMA
MMU/MPU
```

但 linker 层面的基础就是：

```text
__load_start
__load_stop
```

---

# 三十、实验 31-7：加入 `NOCROSSREFS`

现在把：

```ld
OVERLAY 0x00610000 :
```

改成：

```ld
OVERLAY 0x00610000 : NOCROSSREFS
```

完整：

```ld
OVERLAY 0x00610000 : NOCROSSREFS
{
    .ov_a
    {
        *(.ov_a)
    }

    .ov_b
    {
        *(.ov_b)
    }

    .ov_c
    {
        *(.ov_c)
    }
} AT(0x00401000) > RAM
```

---

# 三十一、为什么 Overlay 特别需要 `NOCROSSREFS`？

假设：

```text
.ov_a
    ↓
overlay_b()
```

那么运行：

```text
A
```

的时候：

```text
B
```

可能根本没有被加载。

但 A 却跳到：

```text
0x00610000
```

这时候：

```text
0x00610000
```

里面可能仍然是：

```text
A
```

而不是：

```text
B
```

于是：

```text
A → B
```

会直接跳到错误代码。

因此：

```ld
NOCROSSREFS
```

就是 Overlay 的天然安全检查。

GNU ld 官方文档也明确指出，Overlay 中各 Section 共享运行地址，因此不同 Overlay 之间直接引用通常没有意义；使用 `NOCROSSREFS` 可以让 linker 检测并拒绝这种引用。([Sourceware][1])

---

# 三十二、实验 31-8：故意制造 Overlay 交叉引用

修改 `overlay_a.c`：

```c
extern int overlay_b(void);

__attribute__((section(".ov_a")))
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
    -ffunction-sections \
    -fdata-sections \
    -c overlay_a.c \
    -o overlay_a.o
```

---

# 三十三、先看 relocation

```bash
readelf -rW overlay_a.o
```

找到：

```text
overlay_b
```

再：

```bash
objdump -dr overlay_a.o
```

应该看到：

```text
overlay_a
    ↓
relocation
    ↓
overlay_b
```

---

# 三十四、没有 `NOCROSSREFS` 会怎样？

如果删除：

```ld
NOCROSSREFS
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
    -o bad-overlay.elf \
    -Map=bad-overlay.map
```

可能仍然链接成功。

因为从普通 ELF 角度：

```text
A 调 B
```

没有语法错误。

但是从 Overlay 运行模型：

```text
A 与 B 共用 VMA
```

这是危险的。

---

# 三十五、加入 `NOCROSSREFS`

重新：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    overlay_a.o \
    overlay_b.o \
    overlay_c.o \
    -o bad-overlay.elf \
    -Map=bad-overlay.map
```

这时应该因为：

```text
.ov_a → .ov_b
```

而失败。

于是形成完整链路：

```text
C
 ↓
call overlay_b()
 ↓
relocation
 ↓
.ov_a → .ov_b
 ↓
OVERLAY NOCROSSREFS
 ↓
ld error
```

这正好把：

```text
实验 30
NOCROSSREFS
```

和：

```text
实验 31
OVERLAY
```

连接起来。

---

# 三十六、实验 31-9：分析 Map 文件

成功链接后：

```bash
less overlay.map
```

搜索：

```text
.ov_a
```

再：

```text
.ov_b
```

再：

```text
.ov_c
```

你应该重点看到：

```text
.ov_a
    VMA = 0x00610000
    LMA = 0x00401000

.ov_b
    VMA = 0x00610000
    LMA = 0x00401000 + SIZEOF(.ov_a)

.ov_c
    VMA = 0x00610000
    LMA = 0x00401000
             + SIZEOF(.ov_a)
             + SIZEOF(.ov_b)
```

---

# 三十七、Map 文件里最重要的三个问题

对于 Overlay，每次都问：

### ① VMA 是不是相同？

```text
.ov_a
.ov_b
.ov_c
```

应该：

```text
VMA(A)
=
VMA(B)
=
VMA(C)
```

---

### ② LMA 是不是连续？

应该：

```text
LMA(B)
=
LMA(A) + SIZEOF(A)
```

以及：

```text
LMA(C)
=
LMA(B) + SIZEOF(B)
```

---

### ③ 最大 Overlay 是否决定 location counter？

GNU ld 在 Overlay 结束之后，会把 location counter 设置到：

```text
Overlay start
+
largest section size
```

而不是：

```text
Overlay start
+
all section sizes
```

这是 Overlay 和普通 Section 布局非常重要的区别。([Sourceware][1])

---

# 三十八、实验 31-10：验证最大 Overlay 大小

现在故意把 A 做大：

```c
__attribute__((section(".ov_a")))
const char overlay_a_data[0x1000] = {1};
```

B：

```c
__attribute__((section(".ov_b")))
const char overlay_b_data[0x2000] = {2};
```

C：

```c
__attribute__((section(".ov_c")))
const char overlay_c_data[0x800] = {3};
```

于是：

```text
A = 0x1000
B = 0x2000
C = 0x0800
```

Overlay RAM 实际需要：

```text
MAX(
    0x1000,
    0x2000,
    0x0800
)
=
0x2000
```

而不是：

```text
0x1000
+
0x2000
+
0x0800
=
0x3800
```

这就是 Overlay 节省 RAM 的核心。

---

# 三十九、内存占用对比

普通布局：

```text
A 0x1000
B 0x2000
C 0x0800

RAM =
0x3800
```

Overlay：

```text
MAX(A,B,C)
=
0x2000
```

节省：

```text
0x3800 - 0x2000
=
0x1800
```

即：

```text
6144 bytes
```

---

# 四十、这就是 Overlay 的价值

它不是：

```text
“让 Flash 变小”
```

而主要是：

```text
“让运行时 RAM / Instruction Memory 需求变小”
```

Flash 中：

```text
A + B + C
```

全部需要保存。

但 RAM：

```text
MAX(A,B,C)
```

就够了。

---

# 四十一、实验 31-11：Overlay 的容量 ASSERT

我们可以加入：

```ld
ASSERT(
    MAX(
        SIZEOF(.ov_a),
        SIZEOF(.ov_b),
        SIZEOF(.ov_c)
    ) <= 0x4000,
    "ERROR: overlay area too small"
);
```

这样：

```text
最大 Overlay > 16K
```

直接：

```text
ld
 ↓
ERROR
```

---

# 四十二、但更好的方法

因为：

```text
OVERLAY
```

结束以后：

```text
.
```

已经推进到了：

```text
overlay_start + largest_overlay_size
```

所以可以记录：

```ld
__overlay_start = .;
```

然后：

```ld
OVERLAY ...
```

结束以后：

```ld
__overlay_end = .;
```

这样：

```ld
ASSERT(
    (__overlay_end - __overlay_start) <= 0x4000,
    "ERROR: overlay area too small"
);
```

更加直观。

---

# 四十三、实验 31-12：手动实现 `OVERLAY`

这一实验非常重要。

因为 GNU ld 官方文档明确说明：

> `OVERLAY` 本质上只是语法糖。

同样的效果可以用普通 Output Section + `AT()` + `LOADADDR()` + `SIZEOF()` 实现。([Sourceware][5])

例如：

```ld
.ov_a 0x00610000 :
{
    *(.ov_a)
}
AT(0x00401000)

.ov_b 0x00610000 :
{
    *(.ov_b)
}
AT(0x00401000 + SIZEOF(.ov_a))

.ov_c 0x00610000 :
{
    *(.ov_c)
}
AT(
    0x00401000
    + SIZEOF(.ov_a)
    + SIZEOF(.ov_b)
)

. =
    0x00610000
    + MAX(
        SIZEOF(.ov_a),
        SIZEOF(.ov_b),
        SIZEOF(.ov_c)
    );
```

这和：

```ld
OVERLAY
```

表达的是同一种布局逻辑。

---

# 四十四、这正好复习我们前面的知识

我们现在重新认识：

```ld
AT()
```

它决定：

```text
LMA
```

而：

```ld
section_address
```

决定：

```text
VMA
```

所以：

```ld
.ov_a 0x00610000 : ...
AT(0x00401000)
```

就是：

```text
VMA = 0x00610000
LMA = 0x00401000
```

---

# 四十五、实验 31-13：手动生成 `__load_start`

继续手动写：

```ld
PROVIDE(
    __load_start_ov_a =
    LOADADDR(.ov_a)
);

PROVIDE(
    __load_stop_ov_a =
    LOADADDR(.ov_a)
    + SIZEOF(.ov_a)
);
```

B：

```ld
PROVIDE(
    __load_start_ov_b =
    LOADADDR(.ov_b)
);

PROVIDE(
    __load_stop_ov_b =
    LOADADDR(.ov_b)
    + SIZEOF(.ov_b)
);
```

C：

```ld
PROVIDE(
    __load_start_ov_c =
    LOADADDR(.ov_c)
);

PROVIDE(
    __load_stop_ov_c =
    LOADADDR(.ov_c)
    + SIZEOF(.ov_c)
);
```

这就是 GNU ld 自动 Overlay Symbol 的本质。

---

# 四十六、Overlay 语法糖展开

因此：

```ld
OVERLAY 0x00610000 : AT(0x00401000)
{
    .ov_a { *(.ov_a) }
    .ov_b { *(.ov_b) }
    .ov_c { *(.ov_c) }
}
```

概念上可以理解为：

```text
.ov_a
    VMA = 0x00610000
    LMA = 0x00401000

.ov_b
    VMA = 0x00610000
    LMA = LMA(A) + SIZEOF(A)

.ov_c
    VMA = 0x00610000
    LMA = LMA(B) + SIZEOF(B)

location counter =
    VMA(start)
    +
    MAX(size(A), size(B), size(C))
```

---

# 四十七、实验 31-14：验证 `LOADADDR()`

执行：

```bash
readelf -sW overlay.elf |
grep __load
```

然后：

```bash
objdump -h overlay.elf
```

将：

```text
__load_start_ov_a
```

与：

```text
.ov_a LMA
```

进行比较。

应该：

```text
__load_start_ov_a
=
LMA(.ov_a)
```

同理：

```text
__load_stop_ov_a
=
LMA(.ov_a) + SIZEOF(.ov_a)
```

这就是一次非常完整的：

```text
Linker Symbol
+
Section
+
LMA
```

交叉验证。

---

# 四十八、实验 31-15：Overlay + Binary Image

生成：

```bash
objcopy \
    -O binary \
    overlay.elf \
    overlay.bin
```

然后：

```bash
ls -lh overlay.bin
```

这里要特别注意：

> ELF 中 Overlay 的 VMA 是相同的，但 Firmware 镜像中的 Overlay 内容必须根据 LMA 排列。

GDB 文档也特别指出，使用 Overlay 时，最终 executable 中必须包含每个 Overlay 的内容，并且这些内容位于它们的 load address，而符号和 relocation 按 mapped address 处理。([Sourceware][2])

---

# 四十九、一个非常重要的坑：不要把 VMA 当成 Flash Offset

例如：

```text
.ov_b
VMA = 0x00610000
LMA = 0x00401020
```

如果你看到：

```text
nm:
overlay_b = 0x00610000
```

不要误以为：

```text
“B 在 Flash 的 0x00610000”
```

错。

正确：

```text
0x00610000
    ↓
运行地址

0x00401020
    ↓
Flash 存储地址
```

---

# 五十、实验 31-16：完整 Overlay linker

这一版建议保存：

```ld
ENTRY(_start)

MEMORY
{
    ROM (rx) :
        ORIGIN = 0x00400000,
        LENGTH = 64K

    RAM (rwx) :
        ORIGIN = 0x00600000,
        LENGTH = 64K
}

SECTIONS
{
    .text :
    {
        __text_start = .;

        *(.text)
        *(.text.*)

        __text_end = .;
    } > ROM


    /*
     * Overlay runtime area:
     *
     * VMA = 0x00610000
     * LMA starts at 0x00401000
     */

    OVERLAY 0x00610000 : NOCROSSREFS
    {
        .ov_a
        {
            *(.ov_a)
        }

        .ov_b
        {
            *(.ov_b)
        }

        .ov_c
        {
            *(.ov_c)
        }
    } AT(0x00401000) > RAM


    /*
     * Normal RAM
     */

    .data :
    {
        __data_start = .;

        *(.data)
        *(.data.*)

        __data_end = .;
    } > RAM AT > ROM


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

# 五十一、实验 31-17：完整验证命令

## 1. Input Section

```bash
objdump -h overlay_a.o
objdump -h overlay_b.o
objdump -h overlay_c.o
```

---

## 2. Relocation

```bash
readelf -rW overlay_a.o
readelf -rW overlay_b.o
readelf -rW overlay_c.o
```

---

## 3. 最终 Section

```bash
readelf -SW overlay.elf
```

---

## 4. VMA / LMA

```bash
objdump -h overlay.elf
```

---

## 5. Symbol

```bash
nm -n overlay.elf | grep overlay_
```

---

## 6. Overlay Load Symbol

```bash
nm -n overlay.elf | grep __load
```

---

## 7. 精确 Symbol Table

```bash
readelf -sW overlay.elf |
grep __load
```

---

## 8. Segment

```bash
readelf -lW overlay.elf
```

---

## 9. Map

```bash
less overlay.map
```

---

# 五十二、最终应该形成这样一张表

| Section |          VMA |                  LMA | Size |
| ------- | -----------: | -------------------: | ---: |
| `.ov_a` | `0x00610000` |         `0x00401000` |  `A` |
| `.ov_b` | `0x00610000` |     `0x00401000 + A` |  `B` |
| `.ov_c` | `0x00610000` | `0x00401000 + A + B` |  `C` |

然后：

```text
Overlay RAM requirement
=
MAX(A, B, C)
```

而：

```text
Flash requirement
=
A + B + C
```

这就是 Overlay 最核心的数学关系。

---

# 五十三、实验 31-18：Overlay 与普通 `AT > ROM` 的区别

普通：

```ld
.foo :
{
    *(.foo)
} > RAM AT > ROM
```

表示：

```text
.foo
    一个 Section
    VMA = RAM
    LMA = ROM
```

而：

```ld
OVERLAY :
{
    .foo { ... }
    .bar { ... }
    .baz { ... }
}
```

表示：

```text
.foo
.bar
.baz

VMA 相同
LMA 连续
```

所以：

```text
AT > ROM
```

解决：

```text
一个 Section 的
VMA ≠ LMA
```

而：

```text
OVERLAY
```

进一步解决：

```text
多个 Section
共享 VMA
但 LMA 分开
```

---

# 五十四、实验 31-19：为什么 Overlay 是“节省 RAM”，不是“节省 Flash”

假设：

```text
A = 20 KB
B = 30 KB
C = 10 KB
```

普通：

```text
RAM =
20 + 30 + 10
=
60 KB
```

Overlay：

```text
RAM =
MAX(20,30,10)
=
30 KB
```

但 Flash：

```text
20 + 30 + 10
=
60 KB
```

因此：

```text
节省 RAM = 30 KB
Flash 不节省
```

这是理解 Overlay 最关键的性能/容量模型。

---

# 五十五、实验 31-20：Overlay 的运行时约束

Overlay 不是“免费午餐”。

GDB 官方文档明确指出，Overlay 会增加几个全局约束，例如：调用 Overlay 中函数之前必须确保对应 Overlay 已经映射，否则可能跳到正确地址却执行了错误 Overlay 的代码；同时还需要考虑加载成本。([Sourceware][2])

因此：

```text
Overlay
```

意味着：

```text
RAM 节省
+
运行时管理复杂度增加
```

---

# 五十六、真实 MCU 的 Overlay Manager

最终可能形成：

```text
                 Overlay Manager
                       │
        ┌──────────────┼──────────────┐
        ▼              ▼              ▼
     load(A)        load(B)        load(C)
        │              │              │
        ▼              ▼              ▼
   Flash A image  Flash B image  Flash C image
        │              │              │
        └──────────────┼──────────────┘
                       ▼
                 Overlay RAM
                  0x00610000
```

运行：

```text
A
```

之前：

```text
load(A)
```

运行：

```text
B
```

之前：

```text
load(B)
```

---

# 五十七、Overlay 和 `NOCROSSREFS` 的关系

现在把两节课程连接起来：

## 实验 30

```text
NOCROSSREFS(.boot .app)
```

用于：

```text
架构隔离
```

---

## 实验 31

```text
OVERLAY ... NOCROSSREFS
```

用于：

```text
Overlay 隔离
```

本质上都是：

```text
禁止不安全的跨 Section 依赖。
```

这就是为什么 GNU ld 把：

```text
OVERLAY
+
NOCROSSREFS
```

设计在一起。([Sourceware][3])

---

# 五十八、实验 31 最核心的五个公式

### ① 运行地址

```text
VMA(.ov_a)
=
VMA(.ov_b)
=
VMA(.ov_c)
```

---

### ② 第一个 LMA

```text
LMA(.ov_a)
=
OVERLAY_LMA
```

---

### ③ 第二个 LMA

```text
LMA(.ov_b)
=
LMA(.ov_a)
+
SIZEOF(.ov_a)
```

---

### ④ 第三个 LMA

```text
LMA(.ov_c)
=
LMA(.ov_b)
+
SIZEOF(.ov_b)
```

---

### ⑤ Overlay RAM 大小

```text
Overlay_RAM
=
MAX(
    SIZEOF(.ov_a),
    SIZEOF(.ov_b),
    SIZEOF(.ov_c)
)
```

把这五条真正理解，`OVERLAY` 基本就不会再神秘了。

---

# 五十九、这一节的最终知识图

```text
                  OVERLAY
                     │
         ┌───────────┴───────────┐
         │                       │
        VMA                     LMA
         │                       │
         ▼                       ▼
   same address              consecutive
         │                       │
         │                       │
         ▼                       ▼
   .ov_a / .ov_b / .ov_c    Flash image
         │                       │
         └───────────┬───────────┘
                     ▼
             __load_start_xxx
             __load_stop_xxx
                     │
                     ▼
               runtime copy
                     │
                     ▼
                 Overlay RAM
```

再加：

```text
NOCROSSREFS
      ↓
防止 Overlay 互相调用
```

---

# 六十、从实验 01 到实验 31，我们已经形成了一条完整主线

现在可以把整个 GNU ld 实战课程理解成：

```text
                    GNU ld
                       │
       ┌───────────────┼────────────────┐
       │               │                │
    Sections         Symbols         Memory
       │               │                │
       ▼               ▼                ▼
   Input/Output     PROVIDE          MEMORY
       │             HIDDEN             │
       ▼               │                ▼
   GC / KEEP           │              VMA
       │               │                │
       ▼               ▼                ▼
   SORT/DISCARD    ABSOLUTE          LMA / AT
       │                              │
       └──────────────┬───────────────┘
                      ▼
                   PHDRS
                      │
                      ▼
                    ELF
                      │
            ┌─────────┴─────────┐
            ▼                   ▼
         ASSERT             OVERLAY
                                │
                                ▼
                          NOCROSSREFS
```

这已经从基础的：

```text
“如何写 linker.ld”
```

进入：

```text
“如何设计 Firmware 的链接架构”
```

---

# 六十一、下一阶段：实验 32

下一节建议进入：

# `INSERT AFTER / INSERT BEFORE` + 修改默认 linker script

这是非常重要的一个转折点。

到现在我们一直在：

```text
-T linker.ld
```

里从头定义：

```text
SECTIONS
```

但真实的大型工程经常**不希望重写整个 GNU 默认 linker script**。

例如：

```text
系统默认：

.text
.rodata
.eh_frame
.data
.bss
...
```

我们只想额外插入：

```text
.firmware_header
```

那么可以研究：

```ld
SECTIONS
{
    .firmware_header :
    {
        KEEP(*(.firmware_header))
    }
}
INSERT BEFORE .text;
```

或者：

```ld
INSERT AFTER .rodata;
```

GNU ld 文档明确支持 `INSERT AFTER` / `INSERT BEFORE`，并且这种方式会把自定义 Output Section 插入到默认脚本指定的位置，而不必完全复制默认 linker script。([Sourceware][6])

下一节将继续按同样的递进实验方式拆：

```text
实验 32-1
ld --verbose 查看默认 linker script

实验 32-2
复制默认脚本

实验 32-3
INSERT BEFORE .text

实验 32-4
INSERT AFTER .rodata

实验 32-5
自定义 .firmware_header

实验 32-6
KEEP + INSERT

实验 32-7
默认 .eh_frame / .init_array / .fini_array

实验 32-8
Map 文件比较“默认脚本 vs INSERT”

实验 32-9
readelf/objdump 验证插入前后变化

实验 32-10
为什么 `-T`、`-T` + `INSERT` 和 `-dT` 的行为不同
```

然后再进入下一层：

```text
实验 33
SORT / SORT_BY_NAME / SORT_BY_ALIGNMENT

实验 34
EXCLUDE_FILE / KEEP / wildcard 深入组合

实验 35
CONSTRUCTORS / .init_array / .fini_array

实验 36
CTOR/D TOR 与 C/C++ 初始化

实验 37
RELRO / GOT / PLT / 动态链接脚本

实验 38
PIE / PIC / PHDRS / 动态装载

实验 39
TLS / .tdata / .tbss

实验 40
最终 Firmware Linker Framework
```

其中 **实验 31 的 Overlay** 是一个非常关键的分水岭：从这里开始，课程不再只是学习 linker script 语法，而是在学习如何利用 GNU `ld` **设计和约束整个程序的内存与运行时架构**。

[1]: https://sourceware.org/binutils/docs/ld.pdf?utm_source=chatgpt.com "The GNU linker"
[2]: https://www.sourceware.org/gdb/current/onlinedocs/gdb.html/How-Overlays-Work.html?utm_source=chatgpt.com "How Overlays Work (Debugging with GDB)"
[3]: https://sourceware.org/binutils/docs-2.39/ld.pdf?utm_source=chatgpt.com "The GNU linker"
[4]: https://www.sourceware.org/gdb/current/onlinedocs/gdb?utm_source=chatgpt.com "Debugging with GDB"
[5]: https://sourceware.org/binutils/docs-2.41/ld.pdf?utm_source=chatgpt.com "The GNU linker"
[6]: https://sourceware.org/binutils/docs-2.40/ld.pdf?utm_source=chatgpt.com "The GNU linker"

