# GNU ld 实战课程 · 实验 17

## `ASSERT()`：让 linker 在链接阶段自动检查 ROM、RAM、Stack 和 Overlay

上一节我们完成了 `OVERLAY`：

```text
多个模块
   ↓
不同 LMA
   ↓
相同 VMA
   ↓
共享一块 RAM
```

现在继续沿着原来的路线往前走。

这一节解决一个非常实际的问题：

> **能链接成功，不代表内存布局就是安全的。**

例如：

```text
ROM
├── .text
├── .rodata
├── .data 镜像
└── Overlay
        ↑
        │
        └── 可能已经挤爆 ROM

RAM
├── .data
├── .bss
├── Overlay
└── Stack
        ↑
        │
        └── 可能发生碰撞
```

如果不检查，可能直到固件运行时才发现问题。

GNU `ld` 提供：

```ld
ASSERT(expression, "message")
```

可以让 linker 在**链接阶段直接失败**。

今天我们就把 linker script 从：

```text
“描述内存布局”
```

升级成：

```text
“描述 + 验证内存布局”
```

---

# 一、今天的实验目标

本节完成：

```text
17-1   最简单的 ASSERT()
17-2   检查 .text 是否超过 ROM
17-3   检查 .data/.bss 是否超过 RAM
17-4   检查 Stack 与 RAM 是否碰撞
17-5   检查 Overlay 是否超过预留区域
17-6   检查 .data 的 LMA 是否超过 ROM
17-7   使用 ASSERT + SIZEOF + ADDR
17-8   故意制造错误，观察 ld 如何失败
```

最终我们希望：

```text
gcc
 ↓
.o
 ↓
ld
 ↓
ASSERT()
 ↓
┌───────────────┐
│ layout valid? │
└───────┬───────┘
        │
    ┌───┴───┐
    │       │
   YES      NO
    │       │
    ▼       ▼
  ELF      ld error
```

---

# 二、先建立一个非常重要的概念

我们前面已经学过：

```ld
MEMORY
{
    ROM (rx) : ORIGIN = 0x00400000, LENGTH = 64K
    RAM (rw) : ORIGIN = 0x00600000, LENGTH = 64K
}
```

这里：

```ld
ORIGIN(ROM)
```

得到：

```text
ROM 起始地址
```

而：

```ld
LENGTH(ROM)
```

得到：

```text
ROM 大小
```

因此：

```ld
ORIGIN(ROM) + LENGTH(ROM)
```

就是：

```text
ROM 结束地址
```

同理：

```ld
ORIGIN(RAM) + LENGTH(RAM)
```

就是：

```text
RAM 结束地址
```

---

# 三、实验 17-1：最简单的 ASSERT

先建立一个最小 linker script：

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

    .data :
    {
        *(.data)
    } > RAM

    .bss :
    {
        *(.bss)
    } > RAM
}

ASSERT(
    LENGTH(ROM) >= 0,
    "ROM length is invalid"
)
```

当然，这个检查实际上永远成立。

但它的意义是先认识：

```ld
ASSERT(
    expression,
    "error message"
);
```

如果：

```text
expression == 0
```

linker：

```text
失败
```

如果：

```text
expression != 0
```

继续链接。

---

# 四、`ASSERT()` 可以理解成 linker 里的 `if`

C：

```c
if (!(condition))
{
    error();
}
```

linker：

```ld
ASSERT(
    condition,
    "error"
);
```

例如：

```ld
ASSERT(
    SIZEOF(.text) <= LENGTH(ROM),
    "text section overflow"
);
```

意思：

```text
如果：

.text 大小 > ROM 大小

那么：

ld 报错
```

这就是我们今天最核心的思想。

---

# 五、实验 17-2：检查 `.text`

使用上一节的工程。

假设：

```text
ROM = 64 KB
```

增加：

```ld
ASSERT(
    SIZEOF(.text) <= LENGTH(ROM),
    "ERROR: .text exceeds ROM"
);
```

完整：

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
        _stext = .;

        *(.text)
        *(.text.*)

        _etext = .;
    } > ROM
}

ASSERT(
    SIZEOF(.text) <= LENGTH(ROM),
    "ERROR: .text exceeds ROM"
);
```

---

# 六、编译

还是：

```bash
gcc -ffreestanding -fno-pie -c main.c -o main.o
```

以及：

```bash
gcc -c start.S -o start.o
```

链接：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    -o assert.elf \
    -Map=assert.map
```

正常情况下：

```text
没有错误
```

---

# 七、故意让 `.text` 超过 ROM

现在把 ROM 改成：

```ld
ROM (rx) : ORIGIN = 0x00400000, LENGTH = 16
```

然后：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    -o assert.elf \
    -Map=assert.map
```

应该得到类似：

```text
ld: ERROR: .text exceeds ROM
```

同时 linker 很可能还会给出：

```text
region `ROM' overflowed by ...
```

这里非常有意思：

> `MEMORY` 本身已经具有区域溢出检查，而 `ASSERT()` 可以提供更符合工程语义的检查。

---

# 八、为什么还需要 ASSERT？

因为：

```text
region overflow
```

只能告诉你：

```text
ROM 爆了
```

而：

```ld
ASSERT(
    SIZEOF(.text) <= LENGTH(ROM),
    "ERROR: application code exceeds ROM budget"
);
```

可以表达：

```text
应用代码不能超过 ROM 预算
```

进一步可以做：

```ld
ASSERT(
    SIZEOF(.text) <= 48K,
    "ERROR: .text exceeds 48K application budget"
);
```

这不是简单的“物理内存够不够”。

而是：

> **工程约束。**

---

# 九、实验 17-3：检查 `.data` 的 RAM 使用

现在回到：

```text
.data
VMA → RAM
LMA → ROM
```

linker：

{
    _sdata = .;

    *(.data)
    *(.data.*)

    _edata = .;
} > RAM AT > ROM
```

我们已经有：

```text
_sdata
_edata
```

所以：

```ld
_edata - _sdata
```

就是：

```text
.data RAM size
```

因此：

```ld
ASSERT(
    (_edata - _sdata) <= LENGTH(RAM),
    "ERROR: .data exceeds RAM"
);
```

---

# 十、但这种检查还不够

因为 RAM 不只是：

```text
.data
```

还有：

```text
.bss
stack
heap
overlay
```

所以真正应该检查：

```text
.data
+
.bss
+
overlay
+
stack
<
RAM
```

这就进入今天真正有价值的部分。

---

# 十一、实验 17-4：构造完整 RAM 布局

我们先定义：

```text
RAM

0x00600000
│
├── .data
│
├── .bss
│
├── Overlay
│
└── Stack
    ↑
RAM_END
```

假设：

```text
Stack = 8 KB
```

定义：

```ld
__stack_size = 8K;
```

然后：

```ld
__stack_top = ORIGIN(RAM) + LENGTH(RAM);
__stack_start = __stack_top - __stack_size;
```

于是：

```text
RAM_END
    ↓
0x00610000

stack_start
    ↓
0x0060E000

stack size
    ↓
8 KB
```

---

# 十二、把 Stack 放到 RAM 顶部

加入：

```ld
__stack_size = 8K;

__stack_top =
    ORIGIN(RAM) + LENGTH(RAM);

__stack_start =
    __stack_top - __stack_size;
```

得到：

```text
RAM
0x00600000
│
│ .data
│
│ .bss
│
│ free RAM
│
├── 0x0060E000
│   stack_start
│
│   stack
│
└── 0x00610000
    stack_top
```

---

# 十三、现在可以检查 `.bss` 是否碰到 Stack

我们已经有：

```ld
_ebss
```

因此：

```ld
ASSERT(
    _ebss <= __stack_start,
    "ERROR: .bss overlaps stack"
);
```

这是一个非常有意义的 linker 检查。

因为它表达的是：

```text
.bss 的结束地址
        ≤
Stack 的开始地址
```

如果：

```text
_ebss > __stack_start
```

说明：

```text
RAM collision
```

---

# 十四、完整的 RAM 检查图

```text
RAM_START
    │
    ▼
┌─────────────────────┐
│ .data               │
├─────────────────────┤
│ .bss                │
├─────────────────────┤
│                     │
│   FREE RAM          │
│                     │
├─────────────────────┤ ← __stack_start
│ Stack               │
│                     │
├─────────────────────┤
│                     │
└─────────────────────┘ ← __stack_top
```

检查：

```text
_ebss
  │
  ▼
  <=
  │
  ▼
__stack_start
```

---

# 十五、实验 17-5：Overlay 也纳入 RAM 检查

上一节我们的 Overlay：

```ld
OVERLAY 0x00602000 : ...
```

例如：

```text
Overlay Start
=
0x00602000
```

Overlay 最大大小：

```text
MAX(
    SIZEOF(.overlay_a),
    SIZEOF(.overlay_b),
    SIZEOF(.overlay_c)
)
```

于是 Overlay End：

```ld
__overlay_end =
    0x00602000
    +
    MAX(
        SIZEOF(.overlay_a),
        SIZEOF(.overlay_b),
        SIZEOF(.overlay_c)
    );
```

---

# 十六、检查 Overlay 与 Stack

于是：

```ld
ASSERT(
    __overlay_end <= __stack_start,
    "ERROR: overlay overlaps stack"
);
```

这就是实际工程非常有价值的检查。

最终：

```text
Overlay End
      │
      ▼
      <=
      │
      ▼
Stack Start
```

---

# 十七、完整 RAM 安全模型

现在：

```text
RAM

0x00600000
│
├── .data
│
├── .bss
│
├── Overlay
│
│
│ Free
│
├── Stack Start
│
└── Stack
    │
    ▼
0x00610000
```

检查：

```ld
ASSERT(
    _ebss <= __stack_start,
    "ERROR: .bss overlaps stack"
);

ASSERT(
    __overlay_end <= __stack_start,
    "ERROR: overlay overlaps stack"
);
```

---

# 十八、但还有一个隐藏问题

假设：

```text
.bss
```

已经到：

```text
0x00603000
```

而：

```text
Overlay
```

从：

```text
0x00602000
```

开始。

那么：

```text
.bss
```

和：

```text
Overlay
```

已经发生重叠。

即使它们都没有碰到 Stack：

```text
.bss
   ↓
0x00603000

Overlay
0x00602000
   ↓
```

仍然是错误的。

所以还需要：

```ld
ASSERT(
    _ebss <= __overlay_start,
    "ERROR: .bss overlaps overlay"
);
```

---

# 十九、于是 RAM 变成严格的三区域

```text
RAM

.data
   ↓
.bss
   ↓
Overlay
   ↓
Free RAM
   ↓
Stack
```

对应：

```text
_ebss
   <=
__overlay_start

__overlay_end
   <=
__stack_start

__stack_end
   <=
__stack_top
```

这已经很接近真实 MCU linker script 的内存保护逻辑。

---

# 二十、实验 17-6：检查 `.data` 的 LMA 是否超出 ROM

这是今天非常重要的一步。

注意：

```text
.data
```

有：

```text
VMA = RAM
LMA = ROM
```

所以检查：

```text
RAM 是否够
```

和：

```text
Flash 是否够
```

是两回事。

假设：

```text
.data LMA = 0x0040F000
.data size = 0x2000
```

那么：

```text
0x0040F000 + 0x2000
=
0x00411000
```

已经超过：

```text
ROM END
```

这时候：

```text
RAM
```

可能完全没问题。

但：

```text
Flash
```

已经爆了。

---

# 二十一、计算 `.data` 的 Flash 结束位置

定义：

```ld
__data_load_end =
    LOADADDR(.data) + SIZEOF(.data);
```

于是：

```ld
ASSERT(
    __data_load_end <=
    ORIGIN(ROM) + LENGTH(ROM),
    "ERROR: .data load image exceeds ROM"
);
```

这就是：

# VMA 检查和 LMA 检查分开。

---

# 二十二、这两个检查千万不要混

### RAM

```ld
ASSERT(
    ADDR(.data) + SIZEOF(.data)
        <=
    ORIGIN(RAM) + LENGTH(RAM),
    "RAM overflow"
);
```

### ROM

```ld
ASSERT(
    LOADADDR(.data) + SIZEOF(.data)
        <=
    ORIGIN(ROM) + LENGTH(ROM),
    "ROM overflow"
);
```

一个检查：

```text
VMA
```

一个检查：

```text
LMA
```

这正好对应我们之前学过的：

```text
ADDR()
LOADADDR()
SIZEOF()
```

---

# 二十三、现在加入 `.rodata`

Flash 中通常：

```text
.text
.rodata
.data image
```

所以最终 ROM 使用量至少应该考虑：

```text
.text
+
.rodata
+
.data image
+
Overlay images
```

于是可以建立：

```ld
__rom_end_used =
    MAX(
        ADDR(.text) + SIZEOF(.text),
        ADDR(.rodata) + SIZEOF(.rodata),
        LOADADDR(.data) + SIZEOF(.data)
    );
```

不过对于复杂布局，更推荐直接检查每一个明确的结束位置，而不是把所有 section 简单相加。

---

# 二十四、为什么推荐“区间检查”而不是简单“大小相加”？

例如：

```text
.text
0x00400000 - 0x00401000

.rodata
0x00402000 - 0x00403000
```

中间存在：

```text
0x00401000 - 0x00402000
```

空洞。

所以：

```text
SIZE(.text) + SIZE(.rodata)
```

不能告诉你：

```text
最终最高地址在哪里。
```

而：

```text
ADDR(section) + SIZEOF(section)
```

可以告诉你：

```text
section end address
```

这也是 linker script 中：

```text
地址区间
```

思维非常重要的原因。

---

# 二十五、实验 17-7：加入 `ASSERT()` 到完整 linker script

现在给出本节的核心版本：

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

__stack_size = 8K;

SECTIONS
{
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
        _sdata = .;

        *(.data)
        *(.data.*)

        _edata = .;
    } > RAM AT > ROM :data

    _data_load = LOADADDR(.data);
    _data_load_end =
        LOADADDR(.data) + SIZEOF(.data);

    .bss :
    {
        _sbss = .;

        *(.bss)
        *(.bss.*)
        *(COMMON)

        _ebss = .;
    } > RAM :data

    . = ALIGN(16);

    __overlay_start = .;

    OVERLAY :
    {
        .overlay_a
        {
            *(.overlay_a)
        }

        .overlay_b
        {
            *(.overlay_b)
        }

        .overlay_c
        {
            *(.overlay_c)
        }
    } > RAM AT > ROM :data

    __overlay_end = .;

    __stack_top =
        ORIGIN(RAM) + LENGTH(RAM);

    __stack_start =
        __stack_top - __stack_size;
}
```

---

# 二十六、现在增加检查

放在 `SECTIONS` 后面：

```ld
ASSERT(
    SIZEOF(.text) <= LENGTH(ROM),
    "ERROR: .text exceeds ROM"
);

ASSERT(
    _data_load_end <=
        ORIGIN(ROM) + LENGTH(ROM),
    "ERROR: .data load image exceeds ROM"
);

ASSERT(
    _ebss <= __overlay_start,
    "ERROR: .bss overlaps overlay"
);

ASSERT(
    __overlay_end <= __stack_start,
    "ERROR: overlay overlaps stack"
);

ASSERT(
    __stack_start >= ORIGIN(RAM),
    "ERROR: stack exceeds RAM"
);
```

---

# 二十七、这里有一个非常值得注意的问题

第一条：

```ld
ASSERT(
    SIZEOF(.text) <= LENGTH(ROM),
    ...
);
```

虽然能检查：

```text
.text size <= ROM size
```

但它没有检查：

```text
.text 的起始地址
```

如果：

```text
.text
VMA = 0x00401000
SIZE = 0xF000
```

而：

```text
ROM
0x00400000
+
0x10000
=
0x00500000
```

那么真正应该检查的是：

```text
.text end
<=
ROM end
```

所以更严谨的写法：

```ld
ASSERT(
    ADDR(.text) + SIZEOF(.text)
        <=
    ORIGIN(ROM) + LENGTH(ROM),
    "ERROR: .text exceeds ROM"
);
```

---

# 二十八、这才是真正的“区间检查”

记住这个模式：

```ld
ASSERT(
    ADDR(section) + SIZEOF(section)
        <=
    ORIGIN(region) + LENGTH(region),
    "overflow"
);
```

也就是：

```text
Section End
    <=
Region End
```

对于 RAM：

```ld
ASSERT(
    ADDR(.bss) + SIZEOF(.bss)
        <=
    ORIGIN(RAM) + LENGTH(RAM),
    "RAM overflow"
);
```

对于 ROM：

```ld
ASSERT(
    ADDR(.text) + SIZEOF(.text)
        <=
    ORIGIN(ROM) + LENGTH(ROM),
    "ROM overflow"
);
```

---

# 二十九、实验 17-8：故意制造 RAM 碰撞

把：

```ld
__stack_size = 8K;
```

改成：

```ld
__stack_size = 60K;
```

那么：

```text
RAM = 64K
Stack = 60K
```

如果 `.data + .bss + overlay` 还有空间需求：

```text
必然碰撞。
```

链接：

```bash
ld \
    -T linker.ld \
    start.o \
    init.o \
    main.o \
    overlay_a.o \
    overlay_b.o \
    overlay_c.o \
    -o assert.elf \
    -Map=assert.map
```

最终应该看到：

```text
ERROR: overlay overlaps stack
```

或者其他你定义的 ASSERT 信息。

这就是我们希望达到的效果：

```text
错误在 ld 阶段暴露
```

而不是：

```text
烧录
 ↓
启动
 ↓
随机崩溃
```

---

# 三十、实验 17-9：让 `.bss` 故意膨胀

修改 `main.c`：

```c
char huge_buffer[50000];

int initialized_value = 0x12345678;

int zero_value;

int main(void)
{
    huge_buffer[0] = 1;

    return initialized_value + zero_value;
}
```

编译：

```bash
gcc \
    -ffreestanding \
    -fno-pie \
    -fno-stack-protector \
    -c main.c \
    -o main.o
```

观察：

```bash
nm main.o
```

应该出现一个很大的：

```text
B huge_buffer
```

然后：

```bash
ld \
    -T linker.ld \
    start.o \
    init.o \
    main.o \
    overlay_a.o \
    overlay_b.o \
    overlay_c.o \
    -o assert.elf \
    -Map=assert.map
```

现在重点观察：

```text
.bss
```

以及：

```text
_ebss
__overlay_start
```

如果：

```text
_ebss > __overlay_start
```

那么：

```ld
ASSERT(
    _ebss <= __overlay_start,
    "ERROR: .bss overlaps overlay"
);
```

应该主动失败。

---

# 三十一、Map 文件在这里特别重要

打开：

```bash
less assert.map
```

找到：

```text
.bss
```

你会看到：

```text
.bss
    main.o
        huge_buffer
```

然后：

```text
.overlay_a
.overlay_b
.overlay_c
```

观察它们的地址。

最后找到：

```text
__stack_start
__stack_top
```

于是可以画出：

```text
RAM
│
├── .data
│
├── .bss
│      ↑
│      │
│      └── huge_buffer
│
├── Overlay
│
│
├── Stack
│
└── RAM_END
```

如果发生：

```text
.bss
   │
   └──────────┐
              ▼
           Overlay
```

Map 会非常直观地把问题暴露出来。

---

# 三十二、用 `nm` 验证 ASSERT 使用的符号

执行：

```bash
nm -n assert.elf
```

重点：

```text
_sdata
_edata

_sbss
_ebss

__overlay_start
__overlay_end

__stack_start
__stack_top
```

如果 linker 成功：

```text
这些符号都已经被解析。
```

然后你可以手工计算：

```text
_ebss <= __overlay_start
```

以及：

```text
__overlay_end <= __stack_start
```

这就是：

```text
nm
+
Map
+
ASSERT
```

三者的组合。

---

# 三十三、实验 17-10：给每个区域预留 Budget

实际工程里非常推荐给内存设置“预算”。

例如：

```ld
ASSERT(
    SIZEOF(.text) <= 48K,
    "ERROR: application text budget exceeded"
);
```

表示：

```text
虽然 ROM 有 64K

但规定：

.text 最多只能 48K
```

剩下：

```text
16K
```

给：

```text
.rodata
.data image
boot metadata
```

这是一种非常实用的工程管理方法。

---

# 三十四、甚至可以定义预算符号

例如：

```ld
__text_budget = 48K;
__stack_budget = 8K;
__overlay_budget = 16K;
```

然后：

```ld
ASSERT(
    SIZEOF(.text) <= __text_budget,
    "ERROR: .text budget exceeded"
);
```

```ld
ASSERT(
    __stack_size <= __stack_budget,
    "ERROR: stack budget exceeded"
);
```

```ld
ASSERT(
    __overlay_end - __overlay_start
        <=
    __overlay_budget,
    "ERROR: overlay budget exceeded"
);
```

于是 linker script 开始具有：

```text
配置
+
布局
+
验证
```

三种职责。

---

# 三十五、一个更漂亮的 Overlay 检查

上一节：

```text
Overlay
A
B
C
```

最大大小：

```text
max(
    SIZEOF(A),
    SIZEOF(B),
    SIZEOF(C)
)
```

所以：

```ld
ASSERT(
    (__overlay_end - __overlay_start) <= 16K,
    "ERROR: overlay exceeds 16K"
);
```

这样无论以后：

```text
A
B
C
```

谁变大，只要：

```text
max size > 16K
```

linker 就会失败。

---

# 三十六、为什么 ASSERT 对大型工程特别有价值？

假设你有：

```text
app
bootloader
drivers
network
filesystem
AI model
DSP
```

每次新增代码，都可能导致：

```text
.text ↑
.rodata ↑
.data ↑
.bss ↑
Overlay ↑
```

如果没有检查：

```text
开发者
    ↓
改代码
    ↓
链接成功
    ↓
烧录
    ↓
发现运行异常
```

有 ASSERT：

```text
开发者
    ↓
改代码
    ↓
ld
    ↓
ASSERT
    ↓
ERROR
```

问题在最早阶段被发现。

---

# 三十七、这一节最重要的 5 个表达式

### 1. Section 结束地址

```ld
ADDR(.text) + SIZEOF(.text)
```

---

### 2. Region 结束地址

```ld
ORIGIN(ROM) + LENGTH(ROM)
```

---

### 3. LMA 结束地址

```ld
LOADADDR(.data) + SIZEOF(.data)
```

---

### 4. RAM Stack 起始

```ld
ORIGIN(RAM) + LENGTH(RAM) - __stack_size
```

---

### 5. ASSERT

```ld
ASSERT(
    section_end <= region_end,
    "overflow"
);
```

把这五个组合起来，你已经可以写出相当实用的 linker script 检查系统。

---

# 三十八、推荐的最终检查区

建议以后把 linker script 的末尾固定成类似：

```ld
ASSERT(
    ADDR(.text) + SIZEOF(.text)
        <= ORIGIN(ROM) + LENGTH(ROM),
    "ERROR: .text exceeds ROM"
);

ASSERT(
    ADDR(.rodata) + SIZEOF(.rodata)
        <= ORIGIN(ROM) + LENGTH(ROM),
    "ERROR: .rodata exceeds ROM"
);

ASSERT(
    _data_load_end
        <= ORIGIN(ROM) + LENGTH(ROM),
    "ERROR: .data image exceeds ROM"
);

ASSERT(
    _ebss <= __overlay_start,
    "ERROR: .bss overlaps overlay"
);

ASSERT(
    __overlay_end <= __stack_start,
    "ERROR: overlay overlaps stack"
);

ASSERT(
    __stack_start >= ORIGIN(RAM),
    "ERROR: stack exceeds RAM"
);

ASSERT(
    __stack_top <= ORIGIN(RAM) + LENGTH(RAM),
    "ERROR: stack exceeds RAM end"
);
```

这已经是一个相当不错的：

# Linker Memory Safety Check

---

# 三十九、完整验证流程

以后每完成一次 linker script 修改，固定执行：

```bash
rm -f *.o *.elf *.map
```

编译：

```bash
gcc \
    -ffreestanding \
    -fno-pie \
    -fno-stack-protector \
    -c main.c \
    -o main.o

gcc \
    -ffreestanding \
    -fno-pie \
    -fno-stack-protector \
    -c init.c \
    -o init.o

gcc -c start.S -o start.o
```

Overlay：

```bash
gcc \
    -ffreestanding \
    -fno-pie \
    -fno-stack-protector \
    -c overlay_a.c \
    -o overlay_a.o

gcc \
    -ffreestanding \
    -fno-pie \
    -fno-stack-protector \
    -c overlay_b.c \
    -o overlay_b.o

gcc \
    -ffreestanding \
    -fno-pie \
    -fno-stack-protector \
    -c overlay_c.c \
    -o overlay_c.o
```

链接：

```bash
ld \
    -T linker.ld \
    start.o \
    init.o \
    main.o \
    overlay_a.o \
    overlay_b.o \
    overlay_c.o \
    -o final.elf \
    -Map=final.map
```

---

# 四十、验证四件套

### ① Section

```bash
readelf -S final.elf
```

### ② Segment

```bash
readelf -l final.elf
```

### ③ VMA/LMA

```bash
objdump -h final.elf
```

### ④ Symbol

```bash
nm -n final.elf
```

最后：

```bash
less final.map
```

---

# 四十一、这次 Map 文件应该怎么看？

建立下面这个分析顺序：

```text
1. Memory Configuration
       ↓
2. .text
       ↓
3. .rodata
       ↓
4. .data
       ↓
5. .bss
       ↓
6. .overlay_a/b/c
       ↓
7. __stack_start
       ↓
8. __stack_top
```

然后自己回答：

```text
.text 最后地址？
.rodata 最后地址？
.data VMA？
.data LMA？
.data 镜像结束地址？
.bss 最后地址？
Overlay 起始？
Overlay 结束？
Stack 起始？
RAM 最后地址？
```

最后验证：

```text
ROM：

.text end
.rodata end
.data LMA end
Overlay LMA end

        ↓
全部 <= ROM_END
```

RAM：

```text
.data
  ↓
.bss
  ↓
Overlay
  ↓
Stack
  ↓
RAM_END
```

这才是完整的内存布局审计。

---

# 四十二、今天的核心知识已经形成一个闭环

```text
                 MEMORY
                    │
          ┌─────────┴─────────┐
          ▼                   ▼
         ROM                  RAM
          │                   │
          │                   │
      .text                .data
      .rodata              .bss
      data image           overlay
          │                   │
          │                   │
          ▼                   ▼
       LMA End             Stack
          │                   │
          └────────┬──────────┘
                   ▼
                ASSERT()
                   │
          ┌────────┴────────┐
          ▼                 ▼
        valid             invalid
          │                 │
          ▼                 ▼
        ELF              ld error
```

---

# 四十三、从实验 11 到实验 17，主线已经非常清晰

我们一路走过：

```text
Section
   ↓
Input Section
   ↓
Output Section
   ↓
Symbol
   ↓
Relocation
   ↓
VMA
   ↓
LMA
   ↓
AT()
   ↓
LOADADDR()
   ↓
SIZEOF()
   ↓
.data copy
   ↓
.bss clear
   ↓
PHDRS
   ↓
Segment
   ↓
OVERLAY
   ↓
multiple VMA / LMA
   ↓
ASSERT()
```

也就是说，现在已经从：

> “GNU ld 怎么链接？”

进入了：

> **“如何设计、验证并约束一个完整的 ELF / 固件内存系统？”**

---

# 四十四、下一节：实验 18 —— `PROVIDE()`、`DEFINED()` 与条件式链接脚本

下一步我们会继续解决一个很有意思的问题：

```text
linker script
        │
        ├── 默认提供符号
        │
        ├── 用户可以覆盖
        │
        └── 根据符号是否存在改变布局
```

重点实验：

```ld
PROVIDE()
DEFINED()
```

例如：

```ld
PROVIDE(__heap_start = .);
PROVIDE(__heap_end = __stack_start);
```

然后研究：

```text
为什么有时候 nm 看不到 PROVIDE 符号？
```

这也正好接上我们之前碰到过的：

```text
PROVIDE(__ram_start = ...)
PROVIDE(__ram_end = ...)
PROVIDE(__stack_top = ...)
```

以及：

```text
为什么 PROVIDE 定义的符号在 nm 里有时不出现？
```

下一节会把这个现象彻底解释清楚，并进一步做一个：

```text
┌──────────────────────────────┐
│          RAM                 │
│                              │
│ .data                        │
│ .bss                         │
│ heap                         │
│      ↓                       │
│      free                    │
│      ↓                       │
│ stack                        │
└──────────────────────────────┘
```

的 **Heap/Stack 自动边界 linker script**。

到那一步，`MEMORY + SECTIONS + SYMBOLS + ASSERT + PROVIDE + DEFINED` 就会第一次组合成一个真正可以拿去改造成 MCU 工程的 linker script。

