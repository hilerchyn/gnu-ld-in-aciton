# GNU ld 实战课程 · 实验 29

# `PROVIDE()`、`PROVIDE_HIDDEN()`、`HIDDEN()`、`ABSOLUTE()`：彻底搞懂 Linker Symbol

上一节实验 28，我们解决了：

```text
--gc-sections
      ↓
Input Section 垃圾回收
      ↓
KEEP()
      ↓
保护 Firmware Header / Driver Table
```

现在进入一个非常容易“看起来会写、实际上经常踩坑”的主题：

> **Linker Script 中定义的符号，到底是什么符号？为什么有的 `nm` 能看到，有的看不到？为什么 `PROVIDE()` 有时不生效？**

这一节专门把你之前遇到的：

```ld
PROVIDE(__ram_start = ORIGIN(RAM));
PROVIDE(__ram_end   = ORIGIN(RAM) + LENGTH(RAM));
PROVIDE(__stack_top = ORIGIN(RAM) + LENGTH(RAM));
```

然后：

```bash
nm -n memory-symbols.elf
```

却看不到某些符号的问题彻底实验清楚。

---

# 一、实验 29 的学习目标

这一节完成：

```text
① 普通 linker symbol

② PROVIDE()

③ PROVIDE_HIDDEN()

④ HIDDEN()

⑤ ABSOLUTE()

⑥ SECTION-relative symbol

⑦ Absolute symbol

⑧ Local / Global / Hidden

⑨ nm 与 readelf -sW 的区别

⑩ 把这些机制应用到 Firmware Memory API
```

最终得到：

```text
                Linker Script
                      │
        ┌─────────────┼──────────────┐
        ▼             ▼              ▼
     Symbol        PROVIDE        HIDDEN
        │             │              │
        └─────────────┼──────────────┘
                      ▼
                 ELF Symbol
                      │
          ┌───────────┼───────────┐
          ▼           ▼           ▼
        nm         readelf      objdump
          │           │           │
          └───────────┼───────────┘
                      ▼
              Firmware Symbol API
```

---

# 二、先建立实验工程

目录：

```text
lab29/
├── start.S
├── main.c
├── linker.ld
└── Makefile
```

这一节故意把代码做得很小。

---

# 三、`start.S`

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

# 四、`main.c`

```c
int global_value = 1234;

int main(void)
{
    return global_value;
}
```

---

# 五、编译

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

---

# 六、实验 29-1：最普通的 Linker Symbol

先写：

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
        __text_start = .;

        *(.text)
        *(.text.*)

        __text_end = .;
    } > ROM

    .data :
    {
        __data_start = .;

        *(.data)
        *(.data.*)

        __data_end = .;
    } > RAM
}
```

注意：

```ld
__text_start = .;
```

是一个普通 Symbol 定义。

---

# 七、链接

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    -o symbols.elf \
    -Map=symbols.map
```

然后：

```bash
nm -n symbols.elf
```

你应该看到类似：

```text
00400040 T __text_start
004000...
004000... T __text_end

00600000 D __data_start
00600004 D __data_end
```

具体地址依赖你的 ELF Header、对齐以及 binutils 版本。

---

# 八、`__text_start` 到底是什么？

这里非常重要。

它不是：

```text
一个 C 变量
```

也不是：

```text
一个机器指令
```

它是：

# Linker Defined Symbol

也就是：

> **由 linker 在最终地址布局确定之后创建的符号。**

因此：

```text
C compiler
    ↓
不知道最终地址

ld
    ↓
确定 Section 布局

ld
    ↓
创建 __text_start
```

---

# 九、实验 29-2：查看 Symbol Table

执行：

```bash
readelf -sW symbols.elf
```

你会看到类似：

```text
Num:    Value          Size Type    Bind   Vis      Ndx Name
...
...
__text_start
__text_end
__data_start
__data_end
```

重点关注：

```text
Value
Type
Bind
Vis
Ndx
```

这几个字段。

---

# 十、`nm` 和 `readelf -sW` 的区别

`nm` 更适合：

```text
快速看 Symbol
```

例如：

```bash
nm -n symbols.elf
```

而：

```bash
readelf -sW symbols.elf
```

能够看到更加完整的：

```text
Symbol Table
    ↓
Value
Size
Type
Bind
Vis
Ndx
```

所以以后分析：

```text
PROVIDE
HIDDEN
PROVIDE_HIDDEN
```

优先：

```bash
readelf -sW
```

不要只依赖：

```bash
nm
```

---

# 十一、实验 29-3：定义 Absolute Symbol

现在在 linker script 最后增加：

```ld
__firmware_magic = 0x46574D47;
```

重新链接：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    -o absolute.elf \
    -Map=absolute.map
```

然后：

```bash
nm -n absolute.elf | grep firmware
```

你会看到类似：

```text
0000000046574d47 A __firmware_magic
```

重点是：

```text
A
```

代表：

# Absolute

---

# 十二、Absolute Symbol 是什么意思？

例如：

```ld
__firmware_magic = 0x46574D47;
```

它不是：

```text
某个 Section 中的地址
```

而是：

```text
Symbol Value = 0x46574D47
```

因此：

```text
Ndx = ABS
```

或者 `nm` 显示：

```text
A
```

---

# 十三、实验 29-4：Section-relative Symbol

现在：

```ld
.text :
{
    __text_start = .;

    *(.text)

    __text_end = .;
} > ROM
```

这里：

```text
__text_start
__text_end
```

与：

```text
.text
```

存在 Section 关系。

所以：

```bash
readelf -sW symbols.elf
```

观察：

```text
Ndx
```

通常会显示对应的 Section，而不是：

```text
ABS
```

这就是：

```text
Section-relative Symbol
```

---

# 十四、两种 Symbol 对比

### Section-relative

```ld
.text :
{
    __text_start = .;
}
```

概念：

```text
__text_start
    =
.text + offset
```

---

### Absolute

```ld
__magic = 0x12345678;
```

概念：

```text
__magic
    =
0x12345678
```

两者在：

```bash
readelf -sW
```

中可以明确区分。

---

# 十五、实验 29-5：`ABSOLUTE()`

现在我们故意制造一个区别。

```ld
.text :
{
    __text_start = .;

    *(.text)

    __text_end = .;

    __text_end_abs = ABSOLUTE(.);
} > ROM
```

重新链接：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    -o absolute2.elf \
    -Map=absolute2.map
```

查看：

```bash
readelf -sW absolute2.elf
```

重点比较：

```text
__text_end
__text_end_abs
```

---

# 十六、为什么需要 `ABSOLUTE()`？

在 linker script 中：

```ld
__text_end = .;
```

当它处于：

```ld
.text :
{
    ...
}
```

内部时，它通常是：

```text
.text-relative
```

而：

```ld
__text_end_abs = ABSOLUTE(.);
```

明确要求：

> **把当前地址作为 Absolute Symbol 的值处理。**

也就是说：

```text
普通：

symbol = section-relative value


ABSOLUTE：

symbol = absolute address
```

这在某些需要：

```text
真正物理绝对地址
```

的场景特别有用。

---

# 十七、实验 29-6：`PROVIDE()` 第一次登场

现在删除：

```ld
__text_start = .;
```

换成：

```ld
PROVIDE(__text_start = .);
```

例如：

```ld
.text :
{
    PROVIDE(__text_start = .);

    *(.text)

    PROVIDE(__text_end = .);
} > ROM
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
nm -n provide.elf | grep __text
```

这里你可能发现：

```text
什么？
有时候能看到。
```

而这正是本节最重要的问题。

---

# 十八、`PROVIDE()` 的真正语义

不要把：

```ld
PROVIDE(symbol = value);
```

理解成：

> “定义 symbol。”

更准确的是：

> **如果这个符号没有在其他地方定义，且被需要时，提供这个符号。**

也就是说：

```ld
PROVIDE(__foo = .);
```

具有一种：

```text
fallback definition
```

的性质。

---

# 十九、实验 29-7：让 C 代码引用 `PROVIDE()` Symbol

在 `main.c` 中：

```c
extern char __text_start[];

int main(void)
{
    return __text_start != 0;
}
```

重新编译：

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

重新链接：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    -o provide-ref.elf \
    -Map=provide-ref.map
```

然后：

```bash
nm -n provide-ref.elf | grep __text_start
```

现在应该能看到：

```text
__text_start
```

---

# 二十、这里就是你之前遇到问题的根源

假设：

```ld
PROVIDE(__ram_end = ORIGIN(RAM) + LENGTH(RAM));
```

但是整个程序：

```text
没有任何地方引用 __ram_end
```

那么：

```text
__ram_end
```

可能不会以你预期的方式出现在最终 Symbol Table 中。

而如果：

```c
extern char __ram_end[];

void foo(void)
{
    (void)__ram_end;
}
```

程序产生了对它的引用，那么：

```text
PROVIDE(__ram_end = ...)
```

就有了实际需求。

这就是为什么：

```text
“linker script 中写了 PROVIDE”
```

并不等价于：

```text
“nm 一定能看到这个 symbol”
```

---

# 二十一、实验 29-8：最直观的验证

准备两个版本。

## Version A

```ld
PROVIDE(__ram_end = ORIGIN(RAM) + LENGTH(RAM));
```

C 代码不引用。

执行：

```bash
nm -n provide-no-ref.elf | grep __ram_end
```

---

## Version B

C：

```c
extern char __ram_end[];

int main(void)
{
    return (int)(long)__ram_end;
}
```

执行：

```bash
nm -n provide-ref.elf | grep __ram_end
```

比较两个结果。

这就是：

# `PROVIDE()` 的实验性证明。

---

# 二十二、为什么 Firmware 工程通常不建议滥用 `PROVIDE()`？

因为我们往往希望：

```text
__ram_start
__ram_end
__stack_top
__heap_start
```

成为：

# 明确存在的 Linker API

那么直接：

```ld
__ram_start = ORIGIN(RAM);
__ram_end = ORIGIN(RAM) + LENGTH(RAM);
__stack_top = __ram_end;
```

更直接。

这样：

```bash
nm -n
readelf -sW
```

都能稳定看到。

---

# 二十三、什么时候适合 `PROVIDE()`？

非常适合：

```text
“允许用户覆盖默认值”
```

例如：

```ld
PROVIDE(__stack_size = 0x1000);
```

如果用户没有定义：

```text
__stack_size
```

就采用默认值。

如果其他对象或 linker command line 已经提供：

```text
__stack_size
```

就可以使用已有定义。

因此：

```text
PROVIDE
=
默认定义
```

这个理解非常重要。

---

# 二十四、实验 29-9：模拟可覆盖配置

Linker：

```ld
PROVIDE(__stack_size = 0x1000);
```

然后：

```ld
__stack_top = ORIGIN(RAM) + LENGTH(RAM);

__stack_bottom =
    __stack_top - __stack_size;
```

于是：

```text
RAM
┌───────────────────────┐
│                       │
│ heap                  │
│                       │
├───────────────────────┤
│ stack                 │
│                       │
└───────────────────────┘
                 ↑
             __stack_top
```

并：

```text
__stack_bottom
```

由：

```text
__stack_size
```

计算。

---

# 二十五、实验 29-10：`PROVIDE_HIDDEN()`

现在：

```ld
PROVIDE_HIDDEN(__internal_start = .);
```

重新链接：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    -o hidden.elf \
    -Map=hidden.map
```

然后：

```bash
readelf -sW hidden.elf
```

观察：

```text
Bind
Vis
```

---

# 二十六、`PROVIDE_HIDDEN()` 的核心区别

可以把：

```ld
PROVIDE(__foo = ...);
```

理解为：

```text
默认提供一个普通 Symbol
```

而：

```ld
PROVIDE_HIDDEN(__foo = ...);
```

相当于：

```text
默认提供一个 Hidden Symbol
```

所以：

```text
PROVIDE
       ↓
Symbol 可被其他对象正常看到

PROVIDE_HIDDEN
       ↓
Symbol 存在
但具有 Hidden visibility
```

---

# 二十七、实验 29-11：`HIDDEN()`

再实验：

```ld
__normal_symbol = .;

HIDDEN(__hidden_symbol = .);
```

重新链接。

然后：

```bash
readelf -sW hidden2.elf
```

观察：

```text
__normal_symbol
__hidden_symbol
```

重点看：

```text
Vis
```

你应该能够看到：

```text
DEFAULT
HIDDEN
```

这样的差异。

---

# 二十八、`HIDDEN()` 和 `PROVIDE_HIDDEN()` 的关系

可以简单理解为：

```text
HIDDEN(symbol = value)
```

相当于：

> 无条件创建一个 Hidden Symbol。

而：

```text
PROVIDE_HIDDEN(symbol = value)
```

相当于：

> 以 PROVIDE 的“默认提供”语义创建一个 Hidden Symbol。

所以：

```text
HIDDEN
    =
普通定义 + Hidden Visibility

PROVIDE_HIDDEN
    =
PROVIDE + Hidden Visibility
```

---

# 二十九、为什么需要 Hidden Symbol？

这是链接器内部实现中非常重要的机制。

例如你有：

```text
__internal_start
__internal_end
```

这些符号：

```text
只给当前 ELF 内部使用
```

并不希望成为：

```text
对外可见 ABI
```

那么：

```ld
HIDDEN(__internal_start = .);
```

就非常合适。

---

# 三十、实验 29-12：观察 `nm`

执行：

```bash
nm -a hidden2.elf | grep hidden
```

再：

```bash
readelf -sW hidden2.elf | grep hidden
```

你会发现：

```text
nm
```

和：

```text
readelf
```

的展示方式可能并不完全相同。

因此这一节有一个非常重要的经验：

> **当你研究 Symbol Binding / Visibility 时，以 `readelf -sW` 为主要依据。**

---

# 三十一、实验 29-13：`ABSOLUTE()` + `PROVIDE()`

组合起来：

```ld
PROVIDE(__rom_start =
    ABSOLUTE(ORIGIN(ROM)));

PROVIDE(__rom_end =
    ABSOLUTE(ORIGIN(ROM) + LENGTH(ROM)));
```

但对于：

```text
ORIGIN(ROM)
LENGTH(ROM)
```

这种本身就是地址计算的情况：

```text
ABSOLUTE()
```

通常不是必须的。

这一点很重要：

> **不要为了“高级”而到处使用 `ABSOLUTE()`。**

真正需要的时候才使用。

---

# 三十二、实验 29-14：真正的 Firmware Symbol API

现在我们建立：

```ld
__rom_start = ORIGIN(ROM);
__rom_end   = ORIGIN(ROM) + LENGTH(ROM);

__ram_start = ORIGIN(RAM);
__ram_end   = ORIGIN(RAM) + LENGTH(RAM);
```

然后：

```ld
.text :
{
    __text_start = .;

    *(.text)
    *(.text.*)

    __text_end = .;
} > ROM
```

然后：

```ld
.rodata :
{
    __rodata_start = .;

    *(.rodata)
    *(.rodata.*)

    __rodata_end = .;
} > ROM
```

`.data`：

```ld
.data :
{
    __data_start = .;

    *(.data)
    *(.data.*)

    __data_end = .;
} > RAM AT > ROM
```

然后：

```ld
__data_load_start = LOADADDR(.data);
__data_size = SIZEOF(.data);
```

`.bss`：

```ld
.bss :
{
    __bss_start = .;

    *(.bss)
    *(.bss.*)
    *(COMMON)

    __bss_end = .;
} > RAM
```

---

# 三十三、加入 Heap / Stack

```ld
. = ALIGN(16);

__heap_start = .;

__stack_top = __ram_end;
```

进一步：

```ld
PROVIDE(__stack_size = 0x1000);

__stack_bottom =
    __stack_top - __stack_size;
```

形成：

```text
RAM
0x00600000
│
├── .data
│
├── .bss
│
├── __heap_start
│
│
│   heap / free RAM
│
│
├── __stack_bottom
│
├── stack
│
└── __stack_top
    0x00610000
```

---

# 三十四、实验 29-15：用 `nm` 建立 Memory Report

执行：

```bash
nm -n firmware.elf
```

然后：

```bash
nm -n firmware.elf |
grep -E '__rom|__ram|__text|__rodata|__data|__bss|__heap|__stack'
```

你应该能够看到：

```text
__rom_start
__text_start
__text_end
__rodata_start
__rodata_end
__data_load_start
__data_start
__data_end
__bss_start
__bss_end
__heap_start
__stack_bottom
__stack_top
__ram_end
```

现在 linker symbol 已经成为：

# Firmware Memory API

---

# 三十五、实验 29-16：用 `readelf -sW` 做精确验证

```bash
readelf -sW firmware.elf
```

重点记录：

| Symbol         | Value | Bind   | Visibility | Ndx     |
| -------------- | ----: | ------ | ---------- | ------- |
| `__rom_start`  |   ... | GLOBAL | DEFAULT    | ABS     |
| `__rom_end`    |   ... | GLOBAL | DEFAULT    | ABS     |
| `__text_start` |   ... | GLOBAL | DEFAULT    | `.text` |
| `__text_end`   |   ... | GLOBAL | DEFAULT    | `.text` |
| `__data_start` |   ... | GLOBAL | DEFAULT    | `.data` |
| `__bss_start`  |   ... | GLOBAL | DEFAULT    | `.bss`  |

这里你会第一次非常清楚地看到：

```text
Symbol Value
+
Section
+
Binding
+
Visibility
```

其实是四个独立概念。

---

# 三十六、实验 29-17：为什么 `__rom_start` 通常是 ABS？

因为：

```ld
__rom_start = ORIGIN(ROM);
```

这里：

```text
ORIGIN(ROM)
```

不是：

```text
.text 当前地址
```

而是：

```text
MEMORY region 的固定地址
```

因此：

```text
__rom_start
```

天然适合成为：

```text
ABS
```

类型的 Symbol。

---

# 三十七、实验 29-18：为什么 `__text_start` 不一定是 ABS？

因为：

```ld
.text :
{
    __text_start = .;
}
```

这里的：

```text
.
```

处于：

```text
.text
```

的 Section 上下文中。

因此：

```text
__text_start
```

通常属于：

```text
.text-relative
```

这两个符号虽然：

```text
Value
```

可能都显示为：

```text
0x00400040
```

但它们的：

```text
Ndx
```

语义不同。

这是：

# `ABSOLUTE()` 存在的重要原因。

---

# 三十八、实验 29-19：自己验证 `ABSOLUTE()`

在 `.text` 中：

```ld
__text_end_relative = .;
__text_end_absolute = ABSOLUTE(.);
```

链接。

然后：

```bash
readelf -sW firmware.elf |
grep __text_end
```

比较：

```text
__text_end_relative
__text_end_absolute
```

重点观察：

```text
Ndx
```

如果一个显示：

```text
.text
```

另一个：

```text
ABS
```

那么你就真正看到了：

```text
Section-relative
vs
Absolute
```

而不是停留在概念层面。

---

# 三十九、实验 29-20：Map 文件中的 Symbol

打开：

```bash
less firmware.map
```

搜索：

```text
__text_start
```

再：

```text
__data_start
```

再：

```text
__ram_end
```

Map 文件通常会列出：

```text
Symbol
Value
```

或在对应输出 Section 附近体现。

所以：

```text
readelf
```

回答：

> 最终 ELF 里的 Symbol 是什么？

而：

```text
Map
```

回答：

> **linker 当时是怎么计算和布局它的？**

---

# 四十、实验 29-21：`PROVIDE()` 最容易犯的错误

错误写法：

```ld
PROVIDE(__heap_start = .);
```

然后认为：

```bash
nm firmware.elf
```

一定有：

```text
__heap_start
```

这是错误的假设。

正确理解：

```text
PROVIDE
=
默认提供
```

如果你希望：

```text
这是 Firmware 的公开 Linker API
```

推荐：

```ld
__heap_start = .;
```

而不是：

```ld
PROVIDE(__heap_start = .);
```

---

# 四十一、实验 29-22：什么时候使用 `PROVIDE()` 最合理？

一个典型场景：

```ld
PROVIDE(__stack_size = 0x2000);
```

意思：

```text
默认 Stack = 8 KB
```

然后其他地方如果提供了：

```text
__stack_size
```

就允许覆盖默认值。

所以：

```text
PROVIDE
```

非常适合：

# 默认配置项

而不是：

# 核心 Memory Symbol

---

# 四十二、推荐的 Firmware Symbol 策略

### 固定核心地址：

```ld
__rom_start = ORIGIN(ROM);
__rom_end = ORIGIN(ROM) + LENGTH(ROM);

__ram_start = ORIGIN(RAM);
__ram_end = ORIGIN(RAM) + LENGTH(RAM);
```

直接定义。

---

### Section 边界：

```ld
__text_start = .;
__text_end = .;

__data_start = .;
__data_end = .;

__bss_start = .;
__bss_end = .;
```

直接定义。

---

### 可覆盖配置：

```ld
PROVIDE(__stack_size = 0x2000);
```

使用 `PROVIDE()`。

---

### 内部实现符号：

```ld
HIDDEN(__internal_start = .);
```

或者：

```ld
PROVIDE_HIDDEN(__internal_start = .);
```

---

# 四十三、实验 29-23：最终 linker.ld

把这一节知识整合起来：

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
    /*
     * =========================
     * Region boundaries
     * =========================
     */

    __rom_start = ORIGIN(ROM);
    __rom_end   = ORIGIN(ROM) + LENGTH(ROM);

    __ram_start = ORIGIN(RAM);
    __ram_end   = ORIGIN(RAM) + LENGTH(RAM);


    /*
     * =========================
     * Text
     * =========================
     */

    . = SIZEOF_HEADERS;

    .text :
    {
        __text_start = .;

        *(.text)
        *(.text.*)

        __text_end = .;
    } > ROM :text


    /*
     * =========================
     * Read-only data
     * =========================
     */

    .rodata :
    {
        __rodata_start = .;

        *(.rodata)
        *(.rodata.*)

        __rodata_end = .;
    } > ROM :text


    /*
     * =========================
     * Firmware Header
     * =========================
     */

    .firmware_header :
    {
        __firmware_header_start = .;

        KEEP(*(.firmware_header))

        __firmware_header_end = .;
    } > ROM :text


    /*
     * =========================
     * Data
     * =========================
     */

    .data :
    {
        __data_start = .;

        *(.data)
        *(.data.*)

        __data_end = .;
    } > RAM AT > ROM :data

    __data_load_start = LOADADDR(.data);
    __data_size = SIZEOF(.data);


    /*
     * =========================
     * BSS
     * =========================
     */

    .bss :
    {
        __bss_start = .;

        *(.bss)
        *(.bss.*)
        *(COMMON)

        __bss_end = .;
    } > RAM :data

    __bss_size = SIZEOF(.bss);


    /*
     * =========================
     * Heap / Stack
     * =========================
     */

    . = ALIGN(16);

    __heap_start = .;

    PROVIDE(__stack_size = 0x2000);

    __stack_top = __ram_end;

    __stack_bottom =
        __stack_top - __stack_size;


    /*
     * =========================
     * Image boundaries
     * =========================
     */

    __image_start = LOADADDR(.text);

    __image_end =
        LOADADDR(.data) + SIZEOF(.data);


    /*
     * =========================
     * Assertions
     * =========================
     */

    ASSERT(
        __data_end <= __ram_end,
        "ERROR: .data exceeds RAM"
    );

    ASSERT(
        __bss_end <= __ram_end,
        "ERROR: .bss exceeds RAM"
    );

    ASSERT(
        __heap_start < __stack_bottom,
        "ERROR: heap overlaps stack"
    );

    ASSERT(
        __image_end <= __rom_end,
        "ERROR: firmware exceeds ROM"
    );
}
```

---

# 四十四、实验 29-24：最终编译和链接

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

链接：

```bash
ld \
    --gc-sections \
    --print-gc-sections \
    -T linker.ld \
    start.o \
    main.o \
    -o firmware.elf \
    -Map=firmware.map
```

---

# 四十五、第一轮验证

```bash
readelf -h firmware.elf
```

确认：

```text
Entry point
```

---

```bash
readelf -SW firmware.elf
```

确认：

```text
.text
.rodata
.data
.bss
```

---

```bash
readelf -lW firmware.elf
```

确认：

```text
PT_LOAD
```

---

```bash
objdump -h firmware.elf
```

确认：

```text
VMA
LMA
Size
```

---

# 四十六、第二轮：Symbol 验证

```bash
nm -n firmware.elf |
grep -E \
'__rom|__ram|__text|__rodata|__data|__bss|__heap|__stack|__image'
```

然后：

```bash
readelf -sW firmware.elf |
grep -E \
'__rom|__ram|__text|__rodata|__data|__bss|__heap|__stack|__image'
```

最后：

```bash
objdump -t firmware.elf |
grep -E \
'__rom|__ram|__text|__rodata|__data|__bss|__heap|__stack|__image'
```

现在你可以第一次真正做到：

```text
nm
   ↓
快速查看

readelf -sW
   ↓
精确分析 Symbol

objdump -t
   ↓
再次交叉验证
```

---

# 四十七、第三轮：Map 分析

```bash
less firmware.map
```

重点找：

```text
__rom_start
__rom_end

__ram_start
__ram_end

__text_start
__text_end

__data_load_start
__data_start
__data_end

__bss_start
__bss_end

__heap_start
__stack_bottom
__stack_top

__image_start
__image_end
```

最终建立：

```text
ROM
│
├── __image_start
│
├── .text
│
├── .rodata
│
├── .firmware_header
│
├── .data image
│
└── __image_end
│
└── __rom_end


RAM
│
├── __ram_start
│
├── .data
│
├── .bss
│
├── __heap_start
│
│
├── __stack_bottom
├── stack
│
└── __stack_top
    __ram_end
```

---

# 四十八、这一节最重要的对照表

| 写法                         | 含义               |
| -------------------------- | ---------------- |
| `foo = .;`                 | 普通 linker symbol |
| `foo = 0x1234;`            | Absolute symbol  |
| `PROVIDE(foo = .);`        | 默认提供 symbol      |
| `HIDDEN(foo = .);`         | 创建 Hidden symbol |
| `PROVIDE_HIDDEN(foo = .);` | Hidden + PROVIDE |
| `ABSOLUTE(.)`              | 强制作为绝对地址处理       |
| `ADDR(.data)`              | `.data` VMA      |
| `LOADADDR(.data)`          | `.data` LMA      |
| `SIZEOF(.data)`            | `.data` 大小       |
| `ORIGIN(RAM)`              | RAM 起始地址         |
| `LENGTH(RAM)`              | RAM 大小           |

---

# 四十九、最重要的三个认知

## ① `PROVIDE()` ≠ 普通定义

```ld
PROVIDE(foo = value);
```

不要简单理解成：

```text
“foo 一定被创建”
```

它的核心语义是：

```text
“如果需要这个符号，而它没有其他定义，
linker 可以提供这个默认定义。”
```

---

## ② `nm` 看不到 ≠ linker script 没执行

例如：

```ld
PROVIDE(__ram_end = ...);
```

即使：

```text
nm
```

没找到：

```text
__ram_end
```

也不能直接得出：

```text
“PROVIDE 没执行”
```

要结合：

```bash
readelf -sW
```

以及：

```text
是否有引用
是否有其他定义
```

一起分析。

---

## ③ 地址相同 ≠ Symbol 类型相同

例如：

```text
__text_end
```

和：

```text
__text_end_abs
```

可能：

```text
Value
```

完全一样。

但：

```text
Ndx
```

可能不同：

```text
.text
vs
ABS
```

因此：

# 不要只看 Symbol Value。

---

# 五十、实验 29 的最终知识体系

```text
                    Linker Symbol
                         │
          ┌──────────────┼──────────────┐
          │              │              │
      Definition      PROVIDE        Visibility
          │              │              │
     ┌────┴────┐         │        ┌─────┴─────┐
     │         │         │        │           │
  Relative   Absolute    │     DEFAULT      HIDDEN
     │         │         │        │           │
     │      ABSOLUTE()   │        │      HIDDEN()
     │                    │        │
     └──────────┬─────────┘        │
                │                  │
                ▼                  ▼
          PROVIDE_HIDDEN       HIDDEN
                │
                └──────────┬───────────┘
                           ▼
                     ELF Symbol Table
                           │
                ┌──────────┼──────────┐
                ▼          ▼          ▼
               nm       readelf    objdump
```

---

# 五十一、到这里，GNU ld 的核心 Symbol 体系已经打通

前面的路线：

```text
实验 25
PHDRS / PT_LOAD

实验 26
ROM → RAM / LMA

实验 27
ALIGN / FILL / AT

实验 28
GC / KEEP / SORT / DISCARD

实验 29
Symbol / PROVIDE / HIDDEN / ABSOLUTE
```

现在已经从：

```text
“怎么看 ELF”
```

进入：

```text
“如何设计一个真正可维护的 Firmware Linker Script”
```

---

# 五十二、下一节：实验 30 —— `ASSERT()` + `NOCROSSREFS()` + `NOCROSSREFS_TO()`

下一步我们开始做 **链接期架构约束**。

这一节会故意制造：

```text
Bootloader
    │
    └── 调用 Application

Application
    │
    └── 调用 Bootloader
```

然后利用 linker 在**链接阶段直接禁止非法依赖**。

最终得到：

```text
BOOT
 │
 │ 允许
 ▼
APP

APP
 │
 X 禁止
 ▼
BOOT
```

并深入实验：

```ld
ASSERT(...)
NOCROSSREFS(...)
NOCROSSREFS_TO(...)
```

同时配合：

```bash
readelf -r
readelf -sW
objdump -dr
```

分析：

```text
relocation
     ↓
symbol reference
     ↓
cross-reference
     ↓
linker reject
```

最后会把工程升级成真正的：

```text
Bootloader
      │
      ▼
Application
      │
      ▼
Firmware Image
      │
      ▼
Link-time Architecture Enforcement
```

这一步之后，GNU `ld` 就不再只是“负责把目标文件拼起来”，而开始成为一个**编译期架构约束工具**。

