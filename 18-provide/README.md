# GNU ld 实战课程 · 实验 18

## `PROVIDE()` + `DEFINED()`：让 linker script 支持“默认符号 + 用户覆盖 + 条件布局”

上一节我们完成了：

```text
实验 16  OVERLAY
        ↓
多个 LMA
一个 VMA

实验 17  ASSERT()
        ↓
让 ld 主动检查
ROM / RAM / Stack / Overlay
```

这一节继续往前推进，而且会**直接解决我们之前遇到过的那个问题**：

> 为什么写了 `PROVIDE(__ram_end = ...)`，最后 `nm` 有时候却看不到 `__ram_end`？

这个现象不是 bug，而是 `PROVIDE()` 的设计语义。

GNU ld 当前官方文档（Binutils 2.47）明确说明：`PROVIDE(symbol = expression)` 只有在**该符号被引用且没有被输入对象定义**时才提供定义；如果没有引用它，最终符号表中可能看不到它。([Sourceware][1])

同时，本节会把：

```text
PROVIDE()
DEFINED()
ASSERT()
ORIGIN()
LENGTH()
ADDR()
LOADADDR()
SIZEOF()
```

第一次组合起来。

---

# 一、今天我们要解决什么问题？

假设 linker script 写：

```ld
PROVIDE(__ram_start = ORIGIN(RAM));
PROVIDE(__ram_end   = ORIGIN(RAM) + LENGTH(RAM));
```

然后：

```bash
nm -n xxx.elf
```

你却发现：

```text
__ram_start
```

或者：

```text
__ram_end
```

没有出现。

为什么？

因为：

```ld
PROVIDE()
```

不是：

```ld
普通符号定义
```

它实际上更接近：

> **“如果有人需要这个符号，而且别人没有定义它，我才提供一个默认定义。”**

所以：

```ld
PROVIDE(__ram_end = ...);
```

并不等于：

```ld
__ram_end = ...;
```

这是今天第一核心。

---

# 二、实验 18-1：普通符号 vs PROVIDE

建立：

```text
lab18/
├── main.c
├── start.S
└── linker.ld
```

`main.c`：

```c
int global_data = 123;

int main(void)
{
    return global_data;
}
```

`start.S`：

```asm
.global _start

.text

_start:
    call main
    hlt
```

---

# 三、linker.ld

先写最简单版本：

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
}

__ram_start = ORIGIN(RAM);
__ram_end   = ORIGIN(RAM) + LENGTH(RAM);
```

注意这里没有 `PROVIDE()`。

---

# 四、编译

```bash
gcc \
    -ffreestanding \
    -fno-pie \
    -fno-stack-protector \
    -c main.c \
    -o main.o
```

然后：

```bash
gcc -c start.S -o start.o
```

链接：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    -o normal.elf \
    -Map=normal.map
```

---

# 五、观察 Symbol

```bash
nm -n normal.elf
```

应该可以看到：

```text
00400000 T _start
...
00600000 D global_data
...
00610000 ? __ram_end
```

这里：

```ld
__ram_end = ...
```

是**强制创建的 linker symbol**。

所以：

```text
linker script
       ↓
__ram_end
       ↓
output symbol table
```

通常会保留下来。

---

# 六、实验 18-2：换成 PROVIDE

把：

```ld
__ram_start = ORIGIN(RAM);
__ram_end   = ORIGIN(RAM) + LENGTH(RAM);
```

改成：

```ld
PROVIDE(__ram_start = ORIGIN(RAM));
PROVIDE(__ram_end   = ORIGIN(RAM) + LENGTH(RAM));
```

重新链接：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    -o provide.elf \
    -Map=provide.map
```

然后：

```bash
nm -n provide.elf
```

你可能会发现：

```text
__ram_start
__ram_end
```

根本没有。

这就是我们之前遇到的现象。

---

# 七、为什么？

因为现在：

```text
没有任何代码引用：

__ram_start
__ram_end
```

所以：

```ld
PROVIDE(__ram_end = ...);
```

的逻辑可以理解成：

```text
如果：

__ram_end 被引用
        &&
没有其他地方定义 __ram_end

那么：

提供 __ram_end
```

而现在：

```text
__ram_end
```

没人需要。

于是 linker 没必要把它作为一个实际需要的符号提供出去。

GNU ld 官方文档就是这样定义 `PROVIDE` 的。([Sourceware][1])

---

# 八、实验 18-3：让 C 程序引用 `__ram_end`

修改：

```c
extern char __ram_end[];

int main(void)
{
    volatile char *p = __ram_end;

    return p != 0;
}
```

重新：

```bash
gcc \
    -ffreestanding \
    -fno-pie \
    -fno-stack-protector \
    -c main.c \
    -o main.o
```

链接：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    -o provide-ref.elf \
    -Map=provide-ref.map
```

现在：

```bash
nm -n provide-ref.elf
```

就应该看到：

```text
00610000 ? __ram_end
```

为什么？

因为：

```text
main.o
   │
   │ undefined reference
   ▼
__ram_end
   │
   ▼
ld 发现：
```

这个符号：

```text
被引用
```

并且：

```text
没有输入文件定义
```

于是：

```ld
PROVIDE(__ram_end = ...);
```

生效。

---

# 九、这就是 `PROVIDE()` 的真正语义

可以把它记成：

```text
PROVIDE(S = V)
```

相当于：

```text
如果 S 已经由程序定义
    ↓
    用程序自己的

否则如果 S 被引用
    ↓
    linker 提供 V

否则
    ↓
    可以不提供
```

因此：

```text
普通定义：

S = V
```

是：

> **我强制定义 S。**

而：

```text
PROVIDE(S = V)
```

是：

> **我给 S 一个默认值。**

这个区别非常重要。

---

# 十、实验 18-4：用户自己定义符号，覆盖 PROVIDE

现在：

```c
char __ram_end[1];
```

也就是程序自己定义：

```text
__ram_end
```

然后 linker：

```ld
PROVIDE(__ram_end =
    ORIGIN(RAM) + LENGTH(RAM));
```

重新链接。

最终：

```text
__ram_end
```

应该采用：

```text
main.o
```

里的定义。

这就是 `PROVIDE()` 的另一个核心特点：

> **允许用户自己的定义优先。**

GNU ld 官方文档也明确说明：如果输入对象已经定义了该符号，`PROVIDE` 不会覆盖它。([Sourceware][1])

---

# 十一、普通定义则不同

如果 linker 写：

```ld
__ram_end =
    ORIGIN(RAM) + LENGTH(RAM);
```

而 C 又写：

```c
char __ram_end[1];
```

那么就会产生：

```text
multiple definition
```

因为：

```text
普通定义
    ↓
强制占用符号名
```

而：

```text
PROVIDE
    ↓
默认值
```

这就是两者最大的区别。

---

# 十二、实验 18-5：第一次使用 `DEFINED()`

现在进入：

```ld
DEFINED(symbol)
```

它的语义可以理解为：

```text
symbol 是否已经定义？
```

例如：

```ld
DEFINED(__stack_size)
```

如果：

```text
__stack_size
```

存在：

```text
1
```

否则：

```text
0
```

于是我们可以写：

```ld
__stack_size =
    DEFINED(__stack_size)
    ? __stack_size
    : 8K;
```

不过这里有一个细节：

> 如果 linker script 自己正在给 `__stack_size` 赋值，就不能简单用这种写法，否则容易产生自引用问题。

更好的做法是：

```ld
PROVIDE(__stack_size = 8K);
```

然后让其他地方通过：

```ld
DEFINED(__stack_size)
```

判断。

---

# 十三、`DEFINED()` 最有价值的用途：用户可配置参数

例如：

```text
默认：

Stack = 8K
```

但某个产品：

```text
Stack = 16K
```

我们希望：

```text
linker script
       │
       ├── 默认 8K
       │
       └── 用户可以覆盖
```

这正是：

```ld
PROVIDE()
```

很适合做的事情。

---

# 十四、实验 18-6：Stack 默认值

linker.ld：

```ld
PROVIDE(__stack_size = 8K);

__stack_top =
    ORIGIN(RAM) + LENGTH(RAM);

__stack_start =
    __stack_top - __stack_size;
```

这里：

```text
__stack_size
```

如果用户没有提供：

```text
默认 8K
```

然后：

```text
__stack_top
```

是：

```text
RAM_END
```

所以：

```text
__stack_start
=
RAM_END - 8K
```

---

# 十五、把 RAM 画出来

假设：

```text
RAM = 64K
```

那么：

```text
0x00600000
    │
    ├── .data
    │
    ├── .bss
    │
    ├── free RAM
    │
    ├── __stack_start
    │
    │   8K Stack
    │
    └── __stack_top
        0x00610000
```

数学关系：

```text
__stack_top
=
ORIGIN(RAM) + LENGTH(RAM)
```

以及：

```text
__stack_start
=
__stack_top - __stack_size
```

---

# 十六、实验 18-7：用 `DEFINED()` 做可选 Heap

现在加入：

```ld
PROVIDE(__heap_size = 8K);
```

然后：

```ld
__heap_start = .;
__heap_end =
    __heap_start + __heap_size;
```

于是：

```text
RAM

.data
.bss
heap
free
stack
```

---

# 十七、但这里出现一个真正的工程问题

如果：

```text
.data + .bss + heap + stack
```

超过：

```text
RAM
```

怎么办？

上一节我们已经学过：

```ld
ASSERT()
```

所以：

```ld
ASSERT(
    __heap_end <= __stack_start,
    "ERROR: heap overlaps stack"
);
```

现在：

```text
PROVIDE()
+
ASSERT()
```

开始真正发挥作用。

---

# 十八、完整 Heap / Stack 设计

建议先定义：

```ld
PROVIDE(__stack_size = 8K);
PROVIDE(__heap_size  = 8K);
```

然后：

```ld
__stack_top =
    ORIGIN(RAM) + LENGTH(RAM);

__stack_start =
    __stack_top - __stack_size;
```

在 `.bss` 后：

```ld
__heap_start = .;
__heap_end =
    __heap_start + __heap_size;
```

最后：

```ld
ASSERT(
    __heap_end <= __stack_start,
    "ERROR: heap overlaps stack"
);
```

于是：

```text
RAM
│
├── .data
│
├── .bss
│
├── heap
│
│
├── free RAM
│
├── stack
│
└── RAM_END
```

---

# 十九、实验 18-8：把 Heap 大小作为外部参数

现在我们希望：

```text
默认：

heap = 8K
```

但是某个产品可以：

```text
heap = 16K
```

最简单的方式之一是：

```ld
PROVIDE(__heap_size = 8K);
```

然后在某个输入对象中定义：

```c
char __heap_size;
```

不过这里要注意：

> C 对象符号和 linker script 中“大小常量”的表达方式并不适合直接这样设计。

更典型的工程方法是通过：

```text
不同 linker script
```

或者：

```text
预处理 linker script
```

注入配置。

这一点我们下一阶段会专门实验。

---

# 二十、实验 18-9：`DEFINED()` + 条件地址

现在来做一个更有价值的例子。

假设：

```text
默认：

heap = 8K
```

如果工程定义了：

```text
__NO_HEAP
```

则：

```text
heap = 0
```

linker script：

```ld
PROVIDE(__heap_size = 8K);

__heap_start = .;

__heap_end =
    DEFINED(__NO_HEAP)
    ? __heap_start
    : __heap_start + __heap_size;
```

于是：

```text
没有 __NO_HEAP

heap = 8K
```

而：

```text
有 __NO_HEAP

heap = 0
```

这就是：

# `DEFINED()` + 三目运算符

---

# 二十、注意 `DEFINED()` 判断的对象

例如：

```ld
DEFINED(__NO_HEAP)
```

判断的是：

```text
__NO_HEAP
```

是否已经定义。

它并不判断：

```text
section
```

也不判断：

```text
MEMORY region
```

所以：

```text
DEFINED()
```

本质上是：

```text
Symbol existence test
```

---

# 二十一、实验 18-10：使用 `-defsym`

这时候可以用 ld 的：

```bash
--defsym
```

例如：

```bash
ld \
    --defsym __NO_HEAP=1 \
    -T linker.ld \
    start.o \
    main.o \
    -o noheap.elf
```

然后：

```ld
DEFINED(__NO_HEAP)
```

就成立。

于是：

```text
heap size = 0
```

这就形成：

```text
命令行
   ↓
--defsym
   ↓
Symbol
   ↓
DEFINED()
   ↓
linker script
   ↓
改变布局
```

这是非常值得掌握的技巧。

---

# 二十二、实验 18-11：用 `--defsym` 修改 Stack

例如：

```bash
ld \
    --defsym __stack_size=16384 \
    -T linker.ld \
    start.o \
    main.o \
    -o stack16k.elf
```

但这里有一个重要细节：

如果 linker script 中：

```ld
PROVIDE(__stack_size = 8K);
```

那么：

```text
--defsym __stack_size=16384
```

提供了一个已有定义。

`PROVIDE()` 就不会覆盖它。

于是：

```text
默认：

8K
```

变成：

```text
外部定义：

16K
```

这就是：

# “默认值 + 外部覆盖”

---

# 二十三、这时候 `PROVIDE()` 的价值就非常明显了

可以设计：

```ld
PROVIDE(__stack_size = 8K);
PROVIDE(__heap_size  = 8K);
```

默认：

```text
Stack = 8K
Heap  = 8K
```

某个产品：

```bash
--defsym __stack_size=16384
```

变成：

```text
Stack = 16K
Heap  = 8K
```

另一个产品：

```bash
--defsym __heap_size=16384
```

变成：

```text
Stack = 8K
Heap  = 16K
```

而：

```ld
ASSERT()
```

负责保证：

```text
Heap + Stack + .data + .bss
```

不会爆掉。

---

# 二十四、实验 18-12：完整 Heap / Stack linker script

现在我们把前面的知识全部组合起来。

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

PROVIDE(__stack_size = 8K);
PROVIDE(__heap_size  = 8K);

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

    _data_load =
        LOADADDR(.data);

    _data_load_end =
        LOADADDR(.data)
        + SIZEOF(.data);

    .bss :
    {
        _sbss = .;

        *(.bss)
        *(.bss.*)
        *(COMMON)

        _ebss = .;
    } > RAM :data

    . = ALIGN(16);

    __heap_start = .;

    __heap_end =
        __heap_start + __heap_size;

    __stack_top =
        ORIGIN(RAM) + LENGTH(RAM);

    __stack_start =
        __stack_top - __stack_size;
}
```

然后：

```ld
ASSERT(
    __heap_end <= __stack_start,
    "ERROR: heap overlaps stack"
);

ASSERT(
    __stack_start >= ORIGIN(RAM),
    "ERROR: stack exceeds RAM"
);

ASSERT(
    __stack_top <= ORIGIN(RAM) + LENGTH(RAM),
    "ERROR: stack exceeds RAM"
);

ASSERT(
    _data_load_end <=
    ORIGIN(ROM) + LENGTH(ROM),
    "ERROR: .data image exceeds ROM"
);
```

---

# 二十五、现在进行第一次完整验证

链接：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    -o heap-stack.elf \
    -Map=heap-stack.map
```

然后：

```bash
nm -n heap-stack.elf
```

重点：

```text
_sdata
_edata

_sbss
_ebss

__heap_start
__heap_end

__stack_start
__stack_top
```

---

# 二十六、注意一个非常重要的现象

如果：

```text
__heap_start
__heap_end
__stack_start
__stack_top
```

是普通定义：

```ld
__heap_start = .;
```

那么：

```bash
nm -n
```

通常可以看到。

但如果写：

```ld
PROVIDE(__heap_start = .);
```

且程序没有引用：

```text
__heap_start
```

那么：

```text
nm
```

可能看不到。

所以：

> **“linker script 中写了符号” ≠ “符号一定出现在最终符号表里”。**

尤其是：

```ld
PROVIDE()
```

一定要记住这一点。

---

# 二十七、实验 18-13：用 `EXTERN()` 强制触发 PROVIDE

这里再学习一个很漂亮的技巧。

GNU ld 提供：

```ld
EXTERN(symbol)
```

它相当于强制让 linker 把某个符号当成 undefined symbol。官方文档说明，`EXTERN` 与命令行 `-u/--undefined` 等价。([Sourceware][2])

所以：

```ld
EXTERN(__ram_end)
PROVIDE(__ram_end =
    ORIGIN(RAM) + LENGTH(RAM));
```

现在：

```text
EXTERN
 ↓
__ram_end 被认为需要
 ↓
PROVIDE
 ↓
提供默认定义
```

然后：

```bash
nm -n xxx.elf
```

就更容易观察到：

```text
__ram_end
```

---

# 二十八、但实际工程不一定需要 EXTERN

如果：

```text
startup.S
```

本来就有：

```asm
.extern __stack_top
```

或者 C：

```c
extern char __stack_top[];
```

那么已经产生了：

```text
undefined reference
```

此时：

```ld
PROVIDE()
```

自然会被触发。

所以：

```text
EXTERN()
```

主要用于：

> **明确告诉 linker：“这个符号就是我希望进入链接过程的。”**

---

# 二十九、实验 18-14：验证 `PROVIDE()` 的三个状态

这是本节最值得亲手做的实验。

## 情况 A：没人引用

```ld
PROVIDE(test_symbol = 0x1234);
```

然后：

```bash
nm xxx.elf | grep test_symbol
```

可能：

```text
无输出
```

---

## 情况 B：程序引用

C：

```c
extern char test_symbol[];

void *p = test_symbol;
```

然后：

```bash
nm xxx.elf | grep test_symbol
```

出现：

```text
00001234 ...
```

---

## 情况 C：程序自己定义

C：

```c
char test_symbol;
```

那么：

```text
PROVIDE(test_symbol = 0x1234)
```

不会覆盖它。

---

# 三十、这三个实验必须形成条件反射

```text
PROVIDE(S = V)
```

### ① S 没人引用

```text
→ 可以不出现
```

### ② S 被引用，但没人定义

```text
→ linker 提供 V
```

### ③ S 已经被用户定义

```text
→ 用户定义优先
```

这就是 `PROVIDE()`。

---

# 三十一、实验 18-15：`DEFINED()` + `ASSERT()` 联动

现在做一个很实用的检查：

```ld
ASSERT(
    DEFINED(__stack_size),
    "ERROR: __stack_size must be defined"
);
```

但是这里有一个细节：

如果你已经：

```ld
PROVIDE(__stack_size = 8K);
```

那么这个检查基本没有意义，因为 linker script 自己就提供了默认值。

真正适合：

```text
必须由产品工程提供
```

的参数，才应该：

```ld
ASSERT(
    DEFINED(__config_magic),
    "ERROR: __config_magic is missing"
);
```

例如：

```bash
ld \
    --defsym __config_magic=0x12345678 \
    -T linker.ld \
    ...
```

---

# 三十二、这形成了一个非常漂亮的配置机制

```text
Build system
     │
     │ --defsym
     ▼
Linker Symbol
     │
     ▼
DEFINED()
     │
     ▼
Linker Script
     │
 ┌───┴────┐
 ▼        ▼
layout   ASSERT
```

例如：

```bash
ld \
    --defsym PRODUCT_A=1 \
    -T linker.ld \
    ...
```

linker script：

```ld
ASSERT(
    DEFINED(PRODUCT_A),
    "PRODUCT_A configuration missing"
);
```

或者：

```ld
__feature_base =
    DEFINED(PRODUCT_A)
    ? 0x00608000
    : 0x00604000;
```

这已经开始接近大型嵌入式工程里的：

```text
产品变体
硬件版本
Flash/RAM 配置
功能裁剪
```

---

# 三十三、实验 18-16：完整内存布局

现在我们把之前的：

```text
OVERLAY
ASSERT
PROVIDE
DEFINED
```

全部结合。

目标：

```text
RAM
0x00600000
│
├── .data
│
├── .bss
│
├── Heap
│
├── Overlay
│
│
├── Free RAM
│
├── Stack
│
└── RAM_END
```

对应：

```text
.data
    ↓
.bss
    ↓
heap
    ↓
overlay
    ↓
stack
```

检查：

```ld
ASSERT(
    __heap_end <= __overlay_start,
    "ERROR: heap overlaps overlay"
);

ASSERT(
    __overlay_end <= __stack_start,
    "ERROR: overlay overlaps stack"
);
```

---

# 三十四、现在 Map 文件变得越来越重要

执行：

```bash
less heap-stack.map
```

重点找：

```text
Memory Configuration
```

然后：

```text
.text
.rodata
.data
.bss
```

再：

```text
__heap_start
__heap_end
__overlay_start
__overlay_end
__stack_start
__stack_top
```

最后自己画：

```text
RAM
│
├── .data
│
├── .bss
│
├── heap
│
├── overlay
│
│
├── free
│
├── stack
│
└── end
```

---

# 三十五、用 `readelf` 验证 Section

```bash
readelf -S heap-stack.elf
```

检查：

```text
.data
.bss
.overlay_a
.overlay_b
.overlay_c
```

---

# 三十六、用 `readelf -l` 验证 Segment

```bash
readelf -l heap-stack.elf
```

检查：

```text
PT_LOAD
R E

PT_LOAD
RW
```

然后：

```text
Section to Segment mapping
```

确认：

```text
.text
.rodata
```

进入：

```text
RX
```

而：

```text
.data
.bss
overlay
```

进入：

```text
RW
```

---

# 三十七、用 `objdump -h` 验证 VMA / LMA

```bash
objdump -h heap-stack.elf
```

重点：

```text
.text
.rodata
.data
.bss
.overlay_a
.overlay_b
.overlay_c
```

尤其是：

```text
.data
```

确认：

```text
VMA → RAM
LMA → ROM
```

以及 Overlay：

```text
.overlay_a
VMA = X
LMA = A

.overlay_b
VMA = X
LMA = B

.overlay_c
VMA = X
LMA = C
```

---

# 三十八、最后用 `nm` 做符号审计

```bash
nm -n heap-stack.elf
```

重点：

```text
_stext
_etext

_sdata
_edata

_sbss
_ebss

__heap_start
__heap_end

__overlay_start
__overlay_end

__stack_start
__stack_top
```

然后手算：

```text
heap size
=
__heap_end - __heap_start
```

```text
stack size
=
__stack_top - __stack_start
```

以及：

```text
overlay size
=
__overlay_end - __overlay_start
```

---

# 三十九、这一节最重要的知识关系

现在把三个命令放一起：

```text
PROVIDE()
DEFINED()
ASSERT()
```

分别回答：

### PROVIDE

> **没有用户定义时，我给你一个默认符号。**

```ld
PROVIDE(__stack_size = 8K);
```

---

### DEFINED

> **这个符号现在有没有定义？**

```ld
DEFINED(__NO_HEAP)
```

---

### ASSERT

> **这个条件必须成立。**

```ld
ASSERT(
    __heap_end <= __stack_start,
    "heap overlaps stack"
);
```

于是：

```text
PROVIDE
   ↓
默认配置

DEFINED
   ↓
条件判断

ASSERT
   ↓
约束验证
```

这三个组合起来以后，linker script 已经不仅是“布局文件”，而开始像一个小型的：

# 编译期配置与验证系统。

---

# 四十、实验 18 最终知识图

```text
                    linker.ld
                        │
        ┌───────────────┼────────────────┐
        │               │                │
        ▼               ▼                ▼
     MEMORY          SYMBOLS          SECTIONS
        │               │                │
        │        ┌──────┼──────┐         │
        │        ▼      ▼      ▼         │
        │    PROVIDE DEFINED ASSERT      │
        │        │      │      │         │
        │        │      │      │         │
        └────────┴──────┴──────┴─────────┘
                        │
                        ▼
                     ELF
                        │
          ┌─────────────┼─────────────┐
          ▼             ▼             ▼
      readelf -S    readelf -l    objdump -h
          │             │             │
          └─────────────┼─────────────┘
                        ▼
                       nm
                        │
                        ▼
                     Map file
```

---

# 四十一、把整个课程主线再往前推进一步

到现在已经形成：

```text
实验 01～10
基础链接
│
├── Input Section
├── Output Section
├── Symbol
├── Relocation
├── Archive
└── GC
        ↓
实验 11～14
地址与启动
│
├── VMA
├── LMA
├── AT()
├── LOADADDR()
├── SIZEOF()
├── .data copy
└── .bss clear
        ↓
实验 15
ELF Segment
│
├── PHDRS
├── PT_LOAD
├── R E
├── RW
└── Section → Segment
        ↓
实验 16
OVERLAY
│
├── same VMA
├── different LMA
├── load_start
├── load_stop
└── NOCROSSREFS
        ↓
实验 17
ASSERT
│
├── ROM check
├── RAM check
├── Heap/Stack collision
└── Overlay collision
        ↓
实验 18
PROVIDE / DEFINED
│
├── 默认符号
├── 用户覆盖
├── 条件布局
└── 编译期配置
```

这时候 GNU `ld` 的核心已经从“链接器命令”变成了一套非常完整的：

```text
输入文件
   ↓
Section
   ↓
Symbol
   ↓
Relocation
   ↓
地址空间
   ↓
Segment
   ↓
运行时镜像
   ↓
约束
   ↓
配置
```

---

# 四十二、下一节：实验 19 —— `SORT()` / `KEEP()` / `EXCLUDE_FILE()`：控制几十甚至上百个 Input Section 的最终排列

下一步继续深入一个实际工程里非常重要、但前面还没有系统展开的主题：

```text
很多 .o
    ↓
很多 Input Sections
    ↓
linker 怎么排序？
    ↓
谁必须保留？
    ↓
谁必须排除？
```

我们会构造：

```text
foo.o
    .text.foo
    .init.foo

bar.o
    .text.bar
    .init.bar

vector.o
    .isr_vector

init.o
    .init_array.100
    .init_array.200
```

然后学习：

```ld
SORT_BY_NAME()
SORT_BY_ALIGNMENT()
SORT_BY_INIT_PRIORITY()
KEEP()
EXCLUDE_FILE()
```

最终做一个真正接近 GCC/嵌入式启动机制的实验：

```text
.isr_vector
       ↓
KEEP()
       ↓
不能被 --gc-sections 删除

.init_array.*
       ↓
SORT()
       ↓
按照 priority 排列

某个特定 .o
       ↓
EXCLUDE_FILE()
       ↓
不允许进入某个 Output Section
```

而且我们会专门验证一个非常关键的区别：

```text
KEEP()
```

不是：

```text
“这个 Output Section 保留”
```

而是：

> **防止其中匹配到的 Input Section 被 section garbage collection 丢弃。**

到这里以后，再进入：

```text
实验 20：`INSERT AFTER/BEFORE`
实验 21：Orphan Sections
实验 22：`OVERLAY + PHDRS + ASSERT`
实验 23：完整 MCU linker.ld
实验 24：从 ELF 生成 BIN / HEX
实验 25：自己实现 startup + linker + firmware image
```

最终会把现在这套实验真正收束成一份：

```text
start.S
startup.c
main.c
memory.ld
Makefile
ELF
BIN
MAP
```

的完整“裸机固件链接工程”。

[1]: https://sourceware.org/binutils/docs/ld/PROVIDE.html?utm_source=chatgpt.com "PROVIDE (LD)"
[2]: https://sourceware.org/binutils/docs/ld.html?utm_source=chatgpt.com "LD"

