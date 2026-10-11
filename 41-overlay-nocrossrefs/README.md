# GNU ld 实战课程 · 实验 41
## `OVERLAY` + `NOCROSSREFS` + `NOCROSSREFS_TO()` + `ASSERT()` 综合实战

上一节实验 40，我们研究了默认链接脚本、数据段布局和 RELRO。

现在进入实验 41：**让 GNU ld 管理共享 RAM、安排多份程序镜像，并在链接阶段检查模块之间的引用关系。**

这次不再只研究一个 ELF 字段，而是搭建一个接近嵌入式固件的实际场景：

- FLASH 存放多个功能模块的镜像。
- RAM 只为这些模块预留一块共享的运行空间。
- 多个模块的 VMA 相同，但 LMA 不同。
- 使用 `NOCROSSREFS` 禁止 Overlay 模块之间直接引用。
- 使用 `NOCROSSREFS_TO()` 检查单向依赖。
- 使用 `ASSERT()` 检查内存容量和镜像边界。
- 使用 `readelf`、`objdump`、`nm` 和 Map 文件验证结果。

这些都是 GNU ld 的实际功能。官方文档明确规定了 `OVERLAY` 的布局规则，以及 `NOCROSSREFS`、`NOCROSSREFS_TO()` 的引用检查语义。[GNU Git Repositories](https://gnu.googlesource.com/binutils-gdb/%2B/cbe950e9fe8a56f788bcf985cc51733f18abb45b/ld/ld.texinfo?utm_source=chatgpt.com)

---

# 一、本节最终要实现什么？

假设我们正在设计一个嵌入式设备，其中有两个功能模块：

- `overlay_a`：数据采集模块。
- `overlay_b`：数据分析模块。

两个模块不会同时运行，因此没有必要同时占用两份 RAM。

传统布局：

```text
FLASH
0x00400000
    │
    ├── .text
    │
    ├── overlay_a 镜像
    │
    └── overlay_b 镜像

RAM
0x00600000
    │
    ├── overlay_a 运行区
    │
    └── overlay_b 运行区
```

如果分别为两个模块分配运行空间，就需要两份 RAM。

而 Overlay 布局是：

```text
                    FLASH
              ┌─────────────────┐
0x00400000    │ .text           │
              ├─────────────────┤
              │                 │
0x00410000    │ overlay_a 镜像  │
              │                 │
              ├─────────────────┤
              │                 │
              │ overlay_b 镜像  │
              │                 │
              └─────────────────┘


                    RAM
              ┌─────────────────┐
0x00600000    │ 普通运行数据    │
              ├─────────────────┤
0x00601000    │                 │
              │ 共享 Overlay 区 │
              │                 │
              │ overlay_a 或    │
              │ overlay_b       │
              │                 │
0x00602000    └─────────────────┘
```

关键点：

**两个模块的运行地址相同，存储镜像的地址不同。**

当程序需要执行 `overlay_a` 时，把它从 FLASH 复制到共享 RAM。

需要执行 `overlay_b` 时，再把 `overlay_b` 的镜像复制到同一块 RAM。

注意：GNU ld 只负责安排地址和生成符号，**不会自动生成负责复制和切换 Overlay 的运行时代码**。这个工作需要由启动代码或 Overlay 管理器完成。[GNU Git Repositories](https://gnu.googlesource.com/binutils-gdb/%2B/5f69414afa4c9f2f27b0d0cd46fe23e314180418/ld/ld.texinfo?utm_source=chatgpt.com)

---

# 二、实验路线

本节分成六个递进实验。

| 实验 | 内容 | 预期结果 |
|---|---|---|
| 41-1 | 基础 `OVERLAY` | 两个 Section 的 VMA 相同，LMA 不同 |
| 41-2 | `NOCROSSREFS` | 模块之间存在交叉引用时链接失败 |
| 41-3 | `NOCROSSREFS_TO()` | 验证单向依赖约束 |
| 41-4 | `ASSERT()` | 越过内存容量限制时链接失败 |
| 41-5 | ELF 验证 | 使用 `readelf`、`objdump` 和 `nm` 交叉检查 |
| 41-6 | Map 文件分析 | 解释链接器如何安排 Overlay |

实验环境采用 Linux x86-64、GCC 和 GNU ld。

下面的示例地址来自一个实际验证过的 x86-64 GNU ld 2.44 环境。你自己的工具链可能产生不同的文件偏移、Section 大小和对齐值，但关键布局关系应该一致。

---

# 三、实验目录

创建目录：

```bash
mkdir -p 41-overlay
cd 41-overlay
```

准备以下文件：

```text
41-overlay/
├── start.S
├── overlay_a.c
├── overlay_b_good.c
├── overlay_b_bad.c
├── overlay_a_calls_b.c
├── overlay_a_big.c
└── linker41.ld
```

其中：

- `overlay_b_good.c` 用于验证正常链接。
- `overlay_b_bad.c` 用于验证禁止交叉引用。
- `overlay_a_calls_b.c` 用于验证引用方向。
- `overlay_a_big.c` 用于触发 `ASSERT()`。

---

# 四、实验 41-1：编写最小启动代码

创建 `start.S`：

```asm
.global _start

.section .text.start,"ax",@progbits

.type _start,@function

_start:
1:
    jmp 1b

.size _start, .-_start

.section .note.GNU-stack,"",@progbits
```

这里暂时不真正执行 Overlay。

我们只需要一个有效的入口符号：

```text
_start
```

这样就可以让链接器生成 ELF 可执行文件，并专注观察 Section 布局。

最后的：

```asm
.section .note.GNU-stack,"",@progbits
```

用于声明目标文件不需要可执行栈，避免常见的 GNU ld 可执行栈警告。

---

# 五、编写两个独立模块

## 5.1 `overlay_a.c`

```c
__attribute__((section(".ovl_a"), noinline, used))
int overlay_a(int x)
{
    volatile int y = x + 3;

    return y;
}
```

这里最重要的是：

```c
__attribute__((section(".ovl_a")))
```

它要求编译器将函数放入输入 Section：

```text
.ovl_a
```

而不是通常的 `.text`。

`noinline` 用来避免函数内联，`used` 则要求编译器保留该函数。

## 5.2 `overlay_b_good.c`

```c
__attribute__((section(".ovl_b"), noinline, used))
int overlay_b(int x)
{
    volatile int y = x * 2;

    return y;
}
```

这个函数进入：

```text
.ovl_b
```

现在两个目标文件分别包含：

```text
overlay_a.o
└── .ovl_a

overlay_b_good.o
└── .ovl_b
```

接下来让 GNU ld 将它们安排到同一个运行地址。

---

# 六、编写核心 linker script

创建 `linker41.ld`：

```ld
ENTRY(_start)

MEMORY
{
    FLASH (rx)  : ORIGIN = 0x00400000, LENGTH = 256K
    RAM   (rwx) : ORIGIN = 0x00600000, LENGTH = 64K
}

SECTIONS
{
    . = ORIGIN(FLASH);

    .text : ALIGN(16)
    {
        *(.text.start)
        *(.text .text.*)
    } > FLASH

    .rodata : ALIGN(16)
    {
        *(.rodata .rodata.*)
    } > FLASH

    .data : ALIGN(16)
    {
        *(.data .data.*)
    } > RAM AT > FLASH

    .bss (NOLOAD) : ALIGN(16)
    {
        *(.bss .bss.*)
        *(COMMON)
    } > RAM

    /*
     * Overlay 运行地址：
     * RAM + 0x1000
     *
     * Overlay 镜像起始地址：
     * FLASH + 0x10000
     */
    OVERLAY ORIGIN(RAM) + 0x1000 :
        NOCROSSREFS
        AT(ORIGIN(FLASH) + 0x10000)
    {
        .ovl_a
        {
            *(.ovl_a)
            *(.ovl_a_payload)
        }

        .ovl_b
        {
            *(.ovl_b)
        }
    } > RAM

    /*
     * 显式导出 Overlay 运行区信息。
     */
    __overlay_start = ADDR(.ovl_a);

    __overlay_reserved_end =
        ADDR(.ovl_a) + 0x1000;

    /*
     * 检查每个模块是否超过 4 KiB。
     */
    ASSERT(
        SIZEOF(.ovl_a) <= 0x1000,
        "overlay A exceeds 4 KiB"
    )

    ASSERT(
        SIZEOF(.ovl_b) <= 0x1000,
        "overlay B exceeds 4 KiB"
    )

    /*
     * 两个模块必须使用相同的运行地址。
     */
    ASSERT(
        ADDR(.ovl_a) == ADDR(.ovl_b),
        "overlay VMA mismatch"
    )

    /*
     * 两个镜像的加载地址不得重叠。
     */
    ASSERT(
        LOADADDR(.ovl_b) >=
        LOADADDR(.ovl_a) + SIZEOF(.ovl_a),
        "overlay LMA overlap"
    )

    /*
     * 检查 Overlay 运行地址是否位于 RAM 内。
     */
    ASSERT(
        ADDR(.ovl_a) >= ORIGIN(RAM),
        "overlay starts below RAM"
    )

    ASSERT(
        __overlay_reserved_end <=
        ORIGIN(RAM) + LENGTH(RAM),
        "overlay exceeds RAM"
    )

    /*
     * 检查 Overlay 镜像是否位于 FLASH 内。
     */
    ASSERT(
        LOADADDR(.ovl_a) >= ORIGIN(FLASH),
        "overlay image starts below FLASH"
    )

    ASSERT(
        LOADADDR(.ovl_b) + SIZEOF(.ovl_b) <=
        ORIGIN(FLASH) + LENGTH(FLASH),
        "overlay image exceeds FLASH"
    )
}
```

这里有两个需要特别注意的地方。

### 1. Section 对齐写法

使用：

```ld
.text : ALIGN(16)
{
    *(.text.start)
    *(.text .text.*)
} > FLASH
```

这里的 `ALIGN(16)` 是输出 Section 的对齐属性。

本实验没有在每个空 Section 内部额外执行：

```ld
. = ALIGN(16);
```

这样可以避免仅为了对齐而在空输出 Section 内制造填充。

需要区分：

```ld
.text ALIGN(16) :
```

与：

```ld
.text : ALIGN(16)
```

两者在语法中的位置含义不同。本课程继续使用已经明确区分过的输出 Section 对齐写法。

### 2. Overlay 成员不能像普通输出 Section 那样独立指定地址

正确结构是：

```ld
OVERLAY 起始地址 : AT(加载地址)
{
    .ovl_a { ... }
    .ovl_b { ... }
} > RAM
```

而不是在每个成员中分别指定：

```ld
.ovl_a : AT(...)
```

或：

```ld
.ovl_a > RAM
```

Overlay 的成员共享运行地址，加载地址由整个 Overlay 布局安排。GNU ld 官方文档对此有明确说明。[GNU Git Repositories](https://gnu.googlesource.com/binutils-gdb/%2B/5f69414afa4c9f2f27b0d0cd46fe23e314180418/ld/ld.texinfo?utm_source=chatgpt.com)

---

# 七、理解 `OVERLAY` 的三个关键参数

先看这一行：

```ld
OVERLAY ORIGIN(RAM) + 0x1000 :
    NOCROSSREFS
    AT(ORIGIN(FLASH) + 0x10000)
```

它可以分成三部分。

## 7.1 Overlay 的 VMA

```ld
ORIGIN(RAM) + 0x1000
```

因为：

```text
ORIGIN(RAM) = 0x00600000
```

所以：

```text
Overlay VMA = 0x00601000
```

两个模块都从这个地址开始运行。

## 7.2 Overlay 的 LMA

```ld
AT(ORIGIN(FLASH) + 0x10000)
```

计算结果：

```text
Overlay 初始 LMA = 0x00410000
```

因此第一个模块从：

```text
0x00410000
```

开始存储。

第二个模块接在第一个模块的镜像之后。

## 7.3 `NOCROSSREFS`

```ld
NOCROSSREFS
```

用于禁止 Overlay 成员之间的交叉引用。

如果 `overlay_b` 直接调用 `overlay_a`，链接器将报告错误。

这样可以防止某个模块在另一个模块尚未加载到共享 RAM 时，直接访问它的代码。

---

# 八、编译目标文件

执行：

```bash
CFLAGS="-ffreestanding \
-fno-pie \
-fno-pic \
-fno-stack-protector \
-fno-asynchronous-unwind-tables \
-fno-unwind-tables \
-O0"

gcc $CFLAGS -c start.S -o start.o

gcc $CFLAGS -c overlay_a.c -o overlay_a.o

gcc $CFLAGS -c overlay_b_good.c -o overlay_b_good.o
```

现在检查输入 Section：

```bash
readelf -SW overlay_a.o
```

再检查：

```bash
readelf -SW overlay_b_good.o
```

预期可以分别找到：

```text
.ovl_a
```

以及：

```text
.ovl_b
```

然后执行：

```bash
objdump -h overlay_a.o
objdump -h overlay_b_good.o
```

这一步回答的是：

> 编译器有没有按照 `section` 属性把函数放进指定的输入 Section？

注意，此时还没有真正的 Overlay 地址。最终 VMA/LMA 是链接阶段决定的。

---

# 九、实验 41-1：第一次链接

执行：

```bash
ld \
    -T linker41.ld \
    start.o \
    overlay_a.o \
    overlay_b_good.o \
    -u __load_start_ovl_a \
    -u __load_stop_ovl_a \
    -u __load_start_ovl_b \
    -u __load_stop_ovl_b \
    -Map=overlay-good.map \
    -o overlay-good.elf
```

其中：

```bash
-u __load_start_ovl_a
```

等选项用于要求链接器保留并解析 Overlay 自动生成的加载地址符号。

为什么需要这些选项？

GNU ld 为 Overlay 成员提供：

```text
__load_start_ovl_a
__load_stop_ovl_a

__load_start_ovl_b
__load_stop_ovl_b
```

它们分别表示对应镜像的起始加载地址和结束加载地址。

但这类符号采用按需提供的机制。如果没有被引用，直接执行 `nm` 时可能看不到它们。这与你之前研究 `PROVIDE()` 符号是否出现在 `nm` 输出中的问题属于同一类现象。

---

# 十、实验 41-1：用 `readelf -SW` 检查 Section

执行：

```bash
readelf -SW overlay-good.elf
```

找到：

```text
.ovl_a
.ovl_b
```

在本实验的验证环境中，输出类似：

```text
[N] .ovl_a PROGBITS 0000000000601000 ...
[N] .ovl_b PROGBITS 0000000000601000 ...
```

重点是：

```text
.ovl_a VMA = 0x00601000
.ovl_b VMA = 0x00601000
```

两个 Section 的运行地址相同。

这就是 Overlay 最重要的特征。

如果只看 Section 名称，很容易误以为它们是两个普通的独立 Section。

实际上，它们描述的是同一块运行时内存的两种替代内容。

---

# 十一、实验 41-1：用 `objdump -h` 检查 VMA/LMA

执行：

```bash
objdump -h overlay-good.elf
```

在验证环境中，可以观察到类似结果：

| Section | Size | VMA | LMA |
|---|---:|---:|---:|
| `.text` | `0x2` | `0x00400000` | `0x00400000` |
| `.ovl_a` | `0x15` | `0x00601000` | `0x00410000` |
| `.ovl_b` | `0x14` | `0x00601000` | `0x00410015` |

这些数值是示例环境的实际布局，不是 GNU ld 对所有编译器版本的固定输出。

现在可以计算：

```text
.ovl_a VMA = 0x00601000
.ovl_b VMA = 0x00601000
```

但：

```text
.ovl_a LMA = 0x00410000
.ovl_b LMA = 0x00410015
```

因此：

```text
VMA 相同
LMA 不同
```

正是本实验需要验证的结果。

## 为什么 `.ovl_b` 的 LMA 接在 `.ovl_a` 后面？

因为：

```text
.ovl_a 大小 = 0x15
```

所以：

```text
0x00410000 + 0x15 = 0x00410015
```

因此：

```text
LOADADDR(.ovl_b)
=
LOADADDR(.ovl_a) + SIZEOF(.ovl_a)
```

在这个例子中，两个镜像是连续排列的。

---

# 十二、实验 41-1：用 `nm -n` 检查符号

执行：

```bash
nm -n overlay-good.elf
```

或者：

```bash
nm -n overlay-good.elf | \
grep -E 'overlay_|__load_(start|stop)|__overlay'
```

预期可以看到类似：

```text
0000000000410000 A __load_start_ovl_a
0000000000410015 A __load_stop_ovl_a

0000000000410015 A __load_start_ovl_b
0000000000410029 A __load_stop_ovl_b

0000000000601000 T overlay_a
0000000000601000 T overlay_b

0000000000601000 T __overlay_start
0000000000602000 A __overlay_reserved_end
```

注意：

```text
overlay_a = 0x00601000
overlay_b = 0x00601000
```

两个函数的符号地址相同。

这不是错误。

因为 Overlay 的设计目标就是让它们在不同时间使用相同的运行时地址。

另外：

```text
__load_start_ovl_a = 0x00410000
__load_stop_ovl_a  = 0x00410015
```

可以计算：

```text
镜像大小
=
__load_stop_ovl_a - __load_start_ovl_a
```

即：

```text
0x00410015 - 0x00410000
= 0x15
```

与：

```text
SIZEOF(.ovl_a)
```

一致。

---

# 十三、实验 41-1：用 `readelf -lW` 检查 Segment

现在执行：

```bash
readelf -lW overlay-good.elf
```

在当前验证环境中，关键部分类似：

```text
Program Headers:

Type  Offset   VirtAddr           PhysAddr
LOAD  0x001000 0x0000000000400000 0x0000000000400000
LOAD  0x002000 0x0000000000601000 0x0000000000410000
LOAD  0x003000 0x0000000000601000 0x0000000000410015
```

重点比较第二和第三个 `LOAD`：

| 字段 | Overlay A | Overlay B |
|---|---:|---:|
| `VirtAddr` | `0x00601000` | `0x00601000` |
| `PhysAddr` | `0x00410000` | `0x00410015` |
| `FileSiz` | `0x15` | `0x14` |
| `MemSiz` | `0x15` | `0x14` |

在这个 GNU ld ELF 示例中，`PhysAddr` 反映了链接器安排的加载地址。

因此，Segment 视角再次验证了：

```text
运行地址相同
加载地址不同
```

再查看：

```text
Section to Segment mapping
```

可以看到 `.ovl_a` 和 `.ovl_b` 分别被安排到独立的 `PT_LOAD` Segment 中。

注意：这里没有显式定义 `PHDRS`，是为了观察 GNU ld 的默认 Segment 生成行为。实际裸机固件是否需要自定义 `PHDRS`，还要根据目标平台和烧录工具的要求决定。

---

# 十四、实验 41-1：分析 Map 文件

打开：

```bash
less overlay-good.map
```

也可以直接：

```bash
grep -n -A12 -B2 \
-E '\.ovl_a|\.ovl_b|__load_start|__load_stop' \
overlay-good.map
```

重点观察：

```text
.ovl_a          0x0000000000601000       0x15 load address 0x0000000000410000
```

以及：

```text
.ovl_b          0x0000000000601000       0x14 load address 0x0000000000410015
```

每一行都同时给出了重要信息：

```text
Section 名称
VMA
Section 大小
LMA
```

由此可以建立完整映射：

```text
.ovl_a
  │
  ├── VMA = 0x00601000
  ├── LMA = 0x00410000
  └── SIZEOF = 0x15

.ovl_b
  │
  ├── VMA = 0x00601000
  ├── LMA = 0x00410015
  └── SIZEOF = 0x14
```

Map 文件中还会显示：

```text
PROVIDE (__load_start_ovl_a = LOADADDR (.ovl_a))
PROVIDE (__load_stop_ovl_a = ...)
```

这部分很值得关注。

它告诉你，GNU ld 不只是把 Section 放在某个地址，还自动提供了 Overlay 管理器可以使用的加载地址信息。

**到这里，基础 Overlay 已经完成。**

---

# 十五、实验 41-2：用 `NOCROSSREFS` 禁止模块之间互相引用

现在我们故意制造一个错误。

创建 `overlay_b_bad.c`：

```c
extern int overlay_a(int);

__attribute__((section(".ovl_b"), noinline, used))
int overlay_b(int x)
{
    return overlay_a(x) + 1;
}
```

这里：

```c
return overlay_a(x) + 1;
```

会生成对 `overlay_a` 的引用。

由于：

```text
overlay_a → .ovl_a
overlay_b → .ovl_b
```

所以这是一条：

```text
.ovl_b → .ovl_a
```

的跨 Section 引用。

## 15.1 编译

```bash
gcc $CFLAGS -c overlay_b_bad.c -o overlay_b_bad.o
```

检查目标文件中的重定位：

```bash
readelf -rW overlay_b_bad.o
```

再执行：

```bash
objdump -dr overlay_b_bad.o
```

在 x86-64 目标文件中，通常能看到与 `overlay_a` 有关的调用重定位，例如 `R_X86_64_PLT32`。

这一步很重要：

**先证明目标文件中确实存在跨模块引用，再观察链接器如何处理它。**

## 15.2 故意让链接失败

执行：

```bash
ld \
    -T linker41.ld \
    start.o \
    overlay_a.o \
    overlay_b_bad.o \
    -Map=overlay-bad.map \
    -o overlay-bad.elf
```

预期链接失败。

在验证环境中，GNU ld 输出类似：

```text
ld: overlay_b_bad.o: in function `overlay_b':
overlay_b_bad.c:(.ovl_b+0x11):
prohibited cross reference from .ovl_b to `overlay_a' in .ovl_a
```

这就是我们想看到的错误。

注意，链接器并不是因为函数地址相同就忽略了引用。

它仍然能识别：

```text
引用方所在的输出 Section
```

以及：

```text
被引用符号所在的输出 Section
```

从而判断这条引用违反了 Overlay 的限制。

## 15.3 为什么需要这种限制？

假设两个模块共享：

```text
0x00601000
```

当 `overlay_a` 被加载到这里时，`overlay_b` 并不存在于这块 RAM 中。

如果 `overlay_a` 直接调用 `overlay_b`，调用地址虽然可能被正确解析，但运行时该地址处的内容实际上属于 `overlay_a`。

因此，直接跨 Overlay 调用通常是不安全的。

GNU ld 官方文档指出，`NOCROSSREFS` 正是为了检测这类 Overlay 场景中的不允许引用。[Sourceware](https://sourceware.org/binutils/docs/ld/Miscellaneous-Commands.html?utm_source=chatgpt.com)

---

# 十六、实验 41-3：理解 `NOCROSSREFS_TO()`

上一实验的 `NOCROSSREFS` 比较严格。

它禁止指定 Section 之间的交叉引用。

但某些系统需要允许单向依赖。

例如：

```text
模块 A → 模块 B：允许

模块 B → 模块 A：禁止
```

这时就可以使用：

```ld
NOCROSSREFS_TO(.ovl_a .ovl_b)
```

它的含义是：

> 禁止从 `.ovl_b` 引用 `.ovl_a`。

注意方向：

```text
NOCROSSREFS_TO(目标 Section 来源 Section ...)
```

第一个 Section 是不允许被后续 Section 引用的目标。

因此：

```ld
NOCROSSREFS_TO(.ovl_a .ovl_b)
```

禁止：

```text
.ovl_b → .ovl_a
```

但不会仅仅因为这条规则而禁止：

```text
.ovl_a → .ovl_b
```

这是它与 `NOCROSSREFS` 的核心区别。[Sourceware](https://sourceware.org/binutils/docs/ld/Miscellaneous-Commands.html?utm_source=chatgpt.com)

## 16.1 创建新的 linker script

复制现有脚本：

```bash
sed \
    's/: NOCROSSREFS AT(/: AT(/' \
    linker41.ld > linker41-to.ld
```

然后在文件末尾添加：

```ld
NOCROSSREFS_TO(.ovl_a .ovl_b)
```

这个版本不再使用 Overlay 自身的 `NOCROSSREFS`，而是改用独立的方向性检查命令。

注意：这里需要的是**输出 Section 名称**：

```text
.ovl_a
.ovl_b
```

不是输入目标文件名：

```text
overlay_a.o
overlay_b_bad.o
```

---

# 十七、验证 `NOCROSSREFS_TO()` 的禁止方向

先执行：

```bash
ld \
    -T linker41-to.ld \
    start.o \
    overlay_a.o \
    overlay_b_bad.o \
    -Map=overlay-to-bad.map \
    -o overlay-to-bad.elf
```

预期失败。

错误信息仍然会指出：

```text
prohibited cross reference from .ovl_b to `overlay_a' in .ovl_a
```

因为：

```text
引用方：.ovl_b
目标：.ovl_a
```

正好违反：

```ld
NOCROSSREFS_TO(.ovl_a .ovl_b)
```

的规则。

---

# 十八、反过来验证：允许的引用方向

创建 `overlay_a_calls_b.c`：

```c
extern int overlay_b(int);

__attribute__((section(".ovl_a"), noinline, used))
int overlay_a(int x)
{
    return overlay_b(x) + 1;
}
```

这里引用方向变成：

```text
.ovl_a → .ovl_b
```

重新编译：

```bash
gcc $CFLAGS -c overlay_a_calls_b.c -o overlay_a_calls_b.o
```

然后链接：

```bash
ld \
    -T linker41-to.ld \
    start.o \
    overlay_a_calls_b.o \
    overlay_b_good.o \
    -Map=overlay-to-reverse.map \
    -o overlay-to-reverse.elf
```

在本实验环境中，这个方向的链接可以成功。

原因是：

```ld
NOCROSSREFS_TO(.ovl_a .ovl_b)
```

只禁止：

```text
.ovl_b → .ovl_a
```

而没有禁止：

```text
.ovl_a → .ovl_b
```

这里要特别强调：

**链接成功只表示该方向没有违反当前的链接期约束，不代表这两个 Overlay 在运行时可以直接互相调用。**

因为它们仍然共享相同的运行地址。若运行时没有额外的 Overlay 管理机制，单向调用也可能是不安全的。

所以实际项目中，只有在明确理解模块加载与调用机制之后，才应该使用这种单向约束。

---

# 十九、实验 41-4：用 `ASSERT()` 检查 Overlay 大小

现在让链接器替我们检查内存规划。

原来的脚本中有：

```ld
ASSERT(
    SIZEOF(.ovl_a) <= 0x1000,
    "overlay A exceeds 4 KiB"
)
```

意思是：

```text
SIZEOF(.ovl_a) 必须小于或等于 4096 字节
```

否则链接失败。

GNU ld 官方文档规定，`ASSERT(expression, message)` 会在表达式为零时报告错误并以非零状态退出。[Sourceware](https://sourceware.org/binutils/docs/ld/Miscellaneous-Commands.html?utm_source=chatgpt.com)

接下来我们故意破坏这个约束。

## 19.1 创建超大模块

创建 `overlay_a_big.c`：

```c
__attribute__((section(".ovl_a_payload"), used))
const unsigned char overlay_payload[0x1001] = {
    1
};
```

这个数组大小为：

```text
0x1001 = 4097 字节
```

而 Overlay 的容量限制为：

```text
0x1000 = 4096 字节
```

因此它一定超出容量限制。

由于 `linker41.ld` 中已经包含：

```ld
*(.ovl_a_payload)
```

所以该数组会进入 `.ovl_a` 输出 Section。

## 19.2 编译

```bash
gcc $CFLAGS -c overlay_a_big.c -o overlay_a_big.o
```

## 19.3 链接

```bash
ld \
    -T linker41.ld \
    start.o \
    overlay_a.o \
    overlay_b_good.o \
    overlay_a_big.o \
    -Map=overlay-too-big.map \
    -o overlay-too-big.elf
```

预期失败。

在验证环境中，错误信息为：

```text
ld: overlay A exceeds 4 KiB
```

这说明 `ASSERT()` 已经在链接阶段拦截了超出内存预算的模块。

## 19.4 为什么这比运行时检查更好？

如果没有链接期检查，模块超出共享 RAM 容量时，问题可能直到启动、复制镜像或执行模块时才出现。

有了：

```ld
ASSERT(
    SIZEOF(.ovl_a) <= 0x1000,
    "overlay A exceeds 4 KiB"
)
```

只要镜像变大并突破预算，链接就会立即失败。

这对嵌入式系统尤其有价值。

---

# 二十、实验 41-5：验证完整内存边界

现在重新审视脚本中的几条约束。

## 20.1 检查 Overlay 运行地址

```ld
ASSERT(
    ADDR(.ovl_a) >= ORIGIN(RAM),
    "overlay starts below RAM"
)
```

检查 Overlay 的运行地址没有落在 RAM 起始地址之前。

## 20.2 检查预留的 RAM 区域

```ld
ASSERT(
    __overlay_reserved_end <=
    ORIGIN(RAM) + LENGTH(RAM),
    "overlay exceeds RAM"
)
```

其中：

```ld
__overlay_reserved_end =
    ADDR(.ovl_a) + 0x1000;
```

如果：

```text
RAM 起始地址 = 0x00600000
Overlay 起始地址 = 0x00601000
Overlay 容量 = 0x1000
```

那么：

```text
Overlay 结束地址 = 0x00602000
```

而 RAM 结束地址为：

```text
0x00610000
```

所以这个约束成立。

## 20.3 检查镜像没有超出 FLASH

```ld
ASSERT(
    LOADADDR(.ovl_b) + SIZEOF(.ovl_b) <=
    ORIGIN(FLASH) + LENGTH(FLASH),
    "overlay image exceeds FLASH"
)
```

它检查的是：

```text
第二个镜像的 LMA + 大小
```

而不是 VMA。

因为镜像存储于 FLASH，而不是共享 RAM。

这再次说明，**内存规划中必须把运行地址与加载地址分开计算**。

---

# 二十一、实验 41-6：使用 `objdump -p` 检查 Program Header

执行：

```bash
objdump -p overlay-good.elf
```

重点查找：

```text
LOAD
```

然后对照：

```bash
readelf -lW overlay-good.elf
```

建议记录下面这张表：

| 字段 | 含义 | 在本实验中的用途 |
|---|---|---|
| `p_offset` | Segment 在 ELF 文件中的偏移 | 检查文件布局 |
| `p_vaddr` | Segment 运行虚拟地址 | 验证两个 Overlay 的 VMA |
| `p_paddr` | 物理地址字段 | 在当前 GNU ld 示例中辅助观察 LMA |
| `p_filesz` | Segment 文件大小 | 检查镜像内容大小 |
| `p_memsz` | Segment 内存大小 | 检查运行时内存需求 |
| `p_align` | Segment 对齐约束 | 检查 Segment 布局 |

特别注意：

在本实验的 ELF 文件中，两个 Overlay 的 `p_vaddr` 相同，但 `p_offset` 不同。

这意味着它们在文件中分别保存，却描述相同的运行地址。

**不要要求两个 Overlay 的 ELF 文件偏移也相同。**

如果两个 Section 在 ELF 文件中占据相同的文件偏移，就无法同时保存两份不同的模块镜像。

---

# 二十二、Map 文件的最终分析

现在把本节最重要的输出集中起来。

执行：

```bash
grep -n -A15 -B3 \
-E '\.ovl_a|\.ovl_b|ASSERT|__overlay' \
overlay-good.map
```

重点回答以下问题。

### 问题 1：两个模块的 VMA 是否相同？

检查：

```text
.ovl_a  0x00601000
.ovl_b  0x00601000
```

如果相同，说明它们共享运行地址。

### 问题 2：两个模块的 LMA 是否不同？

检查：

```text
.ovl_a load address 0x00410000
.ovl_b load address 0x00410015
```

如果不同，说明它们的镜像分别存储在不同位置。

### 问题 3：第二个模块的镜像是否接在第一个之后？

计算：

```text
LOADADDR(.ovl_a) + SIZEOF(.ovl_a)
```

与：

```text
LOADADDR(.ovl_b)
```

比较。

如果前者小于或等于后者，就满足脚本中的不重叠约束。

### 问题 4：RAM 预算是否满足？

检查：

```text
SIZEOF(.ovl_a)
SIZEOF(.ovl_b)
```

再分别与：

```text
0x1000
```

比较。

Map 文件可以告诉你 Section 的大小与地址；`ASSERT()` 则负责让这些规则在链接时自动生效。

---

# 二十三、真正的运行时 Overlay 管理器是什么样的？

到目前为止，我们只完成了链接器布局。

如果要在真实固件中运行这些模块，还需要复制代码镜像。

伪代码如下：

```c
#include <stddef.h>
#include <string.h>

extern unsigned char __overlay_start[];

extern unsigned char __load_start_ovl_a[];
extern unsigned char __load_stop_ovl_a[];

extern unsigned char __load_start_ovl_b[];
extern unsigned char __load_stop_ovl_b[];

static void load_overlay_a(void)
{
    size_t size =
        (size_t)(__load_stop_ovl_a - __load_start_ovl_a);

    memcpy(
        __overlay_start,
        __load_start_ovl_a,
        size
    );
}

static void load_overlay_b(void)
{
    size_t size =
        (size_t)(__load_stop_ovl_b - __load_start_ovl_b);

    memcpy(
        __overlay_start,
        __load_start_ovl_b,
        size
    );
}
```

这里的代码只是展示加载机制，并不是可以直接用于所有嵌入式目标的完整启动实现。

真实项目还需要考虑：

- 复制函数本身是否位于不会被覆盖的区域。
- Overlay 代码是否需要重定位。
- 指令缓存和数据缓存是否需要维护。
- 是否允许中断处理程序调用 Overlay 中的函数。
- 是否存在多个任务同时使用共享 Overlay 区的问题。
- 加载过程中是否需要互斥或禁止抢占。

尤其重要的是：

**不要在 `overlay_a` 还需要执行时，就把 `overlay_b` 复制到同一块 RAM 中。**

否则 `overlay_a` 的代码会被覆盖。

这也是为什么 Overlay 系统通常需要明确的生命周期和加载管理策略。

---

# 二十四、实验 41 的核心知识总结

现在回顾本节的四个核心命令。

## 1. `OVERLAY`

```ld
OVERLAY 起始地址 : AT(加载地址)
{
    .ovl_a { ... }
    .ovl_b { ... }
} > RAM
```

作用：

- 多个 Section 使用相同的 VMA。
- 各 Section 的 LMA 分别安排。
- 为 Overlay 成员提供加载地址相关符号。
- 在 Overlay 结束后，将位置计数器推进到最大成员占用空间之后。

官方文档：[GNU ld OVERLAY 文档](https://gnu.googlesource.com/binutils-gdb/%2B/5f69414afa4c9f2f27b0d0cd46fe23e314180418/ld/ld.texinfo?utm_source=chatgpt.com)

## 2. `NOCROSSREFS`

```ld
OVERLAY ... : NOCROSSREFS AT(...)
{
    .ovl_a { ... }
    .ovl_b { ... }
}
```

作用：

> 禁止指定 Section 之间的交叉引用。

适用于需要彼此独立的 Overlay 模块。

## 3. `NOCROSSREFS_TO()`

```ld
NOCROSSREFS_TO(.ovl_a .ovl_b)
```

作用：

> 禁止 `.ovl_b` 引用 `.ovl_a`，但不单凭这条命令禁止反方向的引用。

官方文档：[GNU ld NOCROSSREFS / NOCROSSREFS_TO 文档](https://sourceware.org/binutils/docs/ld/Miscellaneous-Commands.html?utm_source=chatgpt.com)

## 4. `ASSERT()`

```ld
ASSERT(
    SIZEOF(.ovl_a) <= 0x1000,
    "overlay A exceeds 4 KiB"
)
```

作用：

> 将内存容量、地址范围和布局要求转化为链接期检查。

官方文档：[GNU ld ASSERT 文档](https://sourceware.org/binutils/docs/ld/Miscellaneous-Commands.html?utm_source=chatgpt.com)

---

# 二十五、实验 41 最终验收命令

把下面这组命令保存下来，以后分析 Overlay 时可以直接复用。

```bash
# 输入 Section
readelf -SW overlay_a.o
readelf -SW overlay_b_good.o

# 输入重定位
readelf -rW overlay_b_bad.o
objdump -dr overlay_b_bad.o

# ELF Section
readelf -SW overlay-good.elf

# ELF Segment
readelf -lW overlay-good.elf

# Section 的 VMA / LMA
objdump -h overlay-good.elf

# Program Header
objdump -p overlay-good.elf

# 自动生成的加载地址符号
nm -n overlay-good.elf | \
grep -E 'overlay_|__load_(start|stop)|__overlay'

# Map 文件
grep -n -A15 -B3 \
-E '\.ovl_a|\.ovl_b|ASSERT|__overlay' \
overlay-good.map
```

然后进行三项故障测试：

```text
故障测试 A：
让 overlay_b 引用 overlay_a
预期：NOCROSSREFS 拒绝链接

故障测试 B：
使用 NOCROSSREFS_TO(.ovl_a .ovl_b)
让 overlay_b 引用 overlay_a
预期：拒绝链接

故障测试 C：
将 overlay_a 扩大到 4097 字节
预期：ASSERT 报告 overlay A exceeds 4 KiB
```

如果这三项都能复现，你就不只是会写 `OVERLAY`，而是已经掌握了如何让 GNU ld 在构建阶段主动检查模块依赖和内存规划。

---

# 二十六、下一节：实验 42

接下来进入：

## 实验 42 —— `EXTERN()` + `-u` + `KEEP()` + `--gc-sections`：控制符号引入与 Section 回收

实验 41 解决了：

```text
多个模块如何共享 RAM？
哪些模块之间允许引用？
如何让链接器检查容量限制？
```

实验 42 将解决另一个常见问题：

> 为什么明明写了某个函数或注册表，最终 ELF 文件里却没有它？

下一节将通过递进式实验研究：

1. `-ffunction-sections` 和 `-fdata-sections` 如何影响输入 Section。
2. `--gc-sections` 如何回收未使用 Section。
3. `KEEP()` 如何保护必须保留的 Section。
4. `EXTERN()` 与 `-u symbol` 如何强制引入符号。
5. `nm`、`readelf -SW`、Map 文件如何验证哪些 Section 被保留或回收。
6. 如何构建一个由 linker script 控制的插件注册表。

这会把课程从内存布局推进到另一个非常重要的主题：**链接器如何决定哪些代码和数据最终进入 ELF 文件。**
