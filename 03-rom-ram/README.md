# GNU ld 实战课程 · 实验 03

## VMA vs LMA：理解“程序运行地址”和“程序存储地址”

上一节我们已经真正控制了 `.text/.data/.bss` 的地址。今天往前迈一步：**搞懂嵌入式链接器里最核心、也最容易混淆的一对概念——VMA 和 LMA。**

这一节先不急着做真正的 MCU 烧录，而是用一个**可检查、可复现的 ELF 实验**把链接器行为看透。

---

## 1. 今天要解决什么问题？

假设一个 MCU 有这样的内存：

```text
┌──────────────────────────────┐
│ Flash / ROM                  │
│ 0x08000000                   │
│                              │
│  .text                       │
│  .rodata                     │
│  .data 的初始值              │
│                              │
└──────────────────────────────┘

┌──────────────────────────────┐
│ SRAM                         │
│ 0x20000000                   │
│                              │
│  .data  ← 程序运行时          │
│  .bss                        │
│  stack                       │
│                              │
└──────────────────────────────┘
```

`.data` 有一个非常特殊的性质：

```c
int counter = 123;
```

程序运行时：

```text
counter → SRAM
```

但是 `123` 这个初始值最开始不能凭空存在于 SRAM。

它通常被烧进 Flash：

```text
Flash:
    0x0800xxxx
       │
       │ 初始值 123
       ▼
启动代码 copy
       │
       ▼
SRAM:
    0x2000xxxx
       │
       └── counter
```

所以 `.data` 同时有两个地址：

```text
VMA = Virtual Memory Address
     程序运行时地址

LMA = Load Memory Address
     程序存储/加载地址
```

这就是今天的核心。

---

# 2. 先看一个最重要的模型

以后看到：

```ld
.data : AT(...)
{
    *(.data)
}
```

脑子里应该立即出现：

```text
                .data
                  │
        ┌─────────┴─────────┐
        │                   │
       LMA                  VMA
        │                   │
     Flash                 RAM
   存初始值              程序运行
```

例如：

```text
.data
LMA = 0x08001000
VMA = 0x20000000
```

意味着：

```text
Flash 0x08001000
       │
       │ initial data
       ▼
RAM   0x20000000
```

---

# 3. 实验目录

创建：

```text
ld-lab/
├── main.c
├── start.S
└── linker.ld
```

---

# 4. main.c

```c
int global_data = 123;

int global_bss;

const char message[] = "Hello ld";

int main(void)
{
    global_bss = global_data;

    return global_bss;
}
```

这里故意制造三种数据：

```text
global_data
    ↓
.data

global_bss
    ↓
.bss

message
    ↓
.rodata
```

所以：

```text
main.o
│
├── .text
├── .data
├── .bss
└── .rodata
```

---

# 5. start.S

继续使用上一节的 Linux x86-64 启动代码：

```asm
.global _start

_start:
    call main

    mov %eax, %edi

    mov $60, %eax
    syscall

.section .note.GNU-stack,"",@progbits
```

注意这里的：

```asm
.section .note.GNU-stack,"",@progbits
```

就是上一节解决：

```text
missing .note.GNU-stack section
```

的方法。

---

# 6. 第一步：编译但不要链接

```bash
gcc -c main.c -o main.o
gcc -c start.S -o start.o
```

然后：

```bash
readelf -S main.o
```

重点寻找：

```text
.text
.rodata
.data
.bss
```

再：

```bash
objdump -h main.o
```

你会看到类似：

```text
Idx Name      Size
  0 .text     ...
  1 .data     ...
  2 .bss      ...
  3 .rodata   ...
```

这时候注意：

**这些地址还不是最终运行地址。**

`.o` 是：

```text
ET_REL
```

即：

```text
Relocatable ELF
```

它只是告诉 linker：

> “我这里有一个 `.data`，里面有东西；至于最终放哪里，你决定。”

---

# 7. 第二步：第一次使用 MEMORY

现在建立：

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
        *(.text)
    } > ROM

    .rodata :
    {
        *(.rodata)
    } > ROM

    .data :
    {
        *(.data)
    } > RAM AT > ROM

    .bss :
    {
        *(.bss)
        *(COMMON)
    } > RAM
}
```

这是今天最重要的 linker script。

---

# 8. 逐行拆解

## 8.1 MEMORY

```ld
MEMORY
{
    ROM (rx)  : ORIGIN = 0x00400000, LENGTH = 64K
    RAM (rwx) : ORIGIN = 0x00600000, LENGTH = 64K
}
```

告诉 linker：

```text
ROM
起始地址 = 0x00400000
大小     = 64 KB
权限     = r-x

RAM
起始地址 = 0x00600000
大小     = 64 KB
权限     = rwx
```

可以把它理解成：

```text
                linker
                  │
          ┌───────┴────────┐
          ▼                ▼
        ROM              RAM
   0x00400000        0x00600000
```

---

# 9. `.text` 放 ROM

```ld
.text :
{
    *(.text)
} > ROM
```

等价于：

```text
.text
   ↓
ROM
```

因此：

```text
VMA(.text) = ROM 当前地址
LMA(.text) = ROM 当前地址
```

两者通常相同。

---

# 10. `.rodata` 也放 ROM

```ld
.rodata :
{
    *(.rodata)
} > ROM
```

因为：

```c
const char message[] = "Hello ld";
```

本身不会被修改。

所以：

```text
.rodata
    ↓
ROM
```

---

# 11. 最关键的一行

现在来看：

```ld
.data :
{
    *(.data)
} > RAM AT > ROM
```

这一行实际上表达了两个事情。

第一：

```ld
> RAM
```

表示：

> `.data` 的运行地址放 RAM。

所以：

```text
VMA(.data) = RAM
```

第二：

```ld
AT > ROM
```

表示：

> `.data` 的加载内容放 ROM。

所以：

```text
LMA(.data) = ROM
```

于是：

```text
               .data
                 │
        ┌────────┴────────┐
        │                 │
       VMA               LMA
        │                 │
        ▼                 ▼
      RAM               ROM
  0x0060xxxx         0x0040xxxx
```

这就是嵌入式启动代码中：

```text
ROM → RAM
```

的数据来源。

---

# 12. `.bss` 为什么不用 AT？

```ld
.bss :
{
    *(.bss)
    *(COMMON)
} > RAM
```

因为 `.bss` 是：

```text
未初始化数据
```

例如：

```c
int global_bss;
```

它启动后要求：

```text
global_bss == 0
```

但不需要在 Flash 里保存一堆：

```text
00 00 00 00
```

因此 ELF 中通常只记录：

```text
.bss
需要多少内存
```

而不是存储对应的零字节。

所以：

```text
.data
    Flash → RAM
    有初始数据

.bss
    RAM
    启动时清零
```

---

# 13. 链接

执行：

```bash
ld -T linker.ld start.o main.o -o custom.elf -Map=custom.map
```

然后：

```bash
./custom.elf
echo $?
```

应该得到：

```text
123
```

因为：

```c
global_bss = global_data;
```

所以：

```text
global_data = 123

global_bss = 123

return 123
```

---

# 14. 现在开始真正观察 VMA / LMA

执行：

```bash
readelf -S custom.elf
```

然后：

```bash
readelf -l custom.elf
```

以及：

```bash
objdump -h custom.elf
```

重点观察 `.data`。

你应该能看到类似：

```text
.data
  VMA = 0x0060....
  LMA = 0x0040....
```

也就是说：

```text
.data
运行地址 ≠ 存储地址
```

这就是 linker script 最有价值的能力之一。

---

# 15. `objdump -h` 是观察 VMA/LMA 的利器

运行：

```bash
objdump -h custom.elf
```

输出通常包含：

```text
Idx Name      Size      VMA               LMA
...
.data         ...       000000000060....  000000000040....
.bss          ...       000000000060....  000000000060....
```

注意：

```text
.data

VMA ≠ LMA
```

而：

```text
.bss

VMA ≈ LMA
```

这正是我们设计 linker script 的结果。

---

# 16. 为什么 `.data` 的 LMA 会紧跟 ROM？

因为：

```ld
.text > ROM
.rodata > ROM
.data > RAM AT > ROM
```

linker 会安排：

```text
ROM
0x00400000
      │
      ├── .text
      │
      ├── .rodata
      │
      └── .data 初始内容
             │
             │ LMA
             ▼

RAM
0x00600000
      │
      ├── .data
      │
      └── .bss
```

因此：

```text
ROM layout

.text
.rodata
.data(initial values)
```

而：

```text
RAM layout

.data
.bss
```

这是以后写：

```text
STM32
nRF52
ESP32
RISC-V MCU
Bootloader
裸机程序
```

linker script 的核心模式。

---

# 17. map 文件：今天重点看这个

打开：

```bash
less custom.map
```

搜索：

```text
.data
```

可以：

```bash
grep -A 10 -B 3 "\.data" custom.map
```

你会看到类似：

```text
.data           0x0000000000600000        0x4
                ...
 *(.data)
 .data          0x0000000000600000        0x4 main.o
```

这里非常重要：

```text
0x00600000
```

是 `.data` 的运行地址，也就是：

```text
VMA
```

而 map 文件中还会出现 load address 信息，例如：

```text
LOADADDR
```

或者类似：

```text
load address 0x0040....
```

这就是：

```text
LMA
```

---

# 18. linker 提供了三个非常重要的函数

以后写复杂 linker script 时，这三个必须熟。

## `ADDR`

```ld
ADDR(.data)
```

得到：

```text
.data VMA
```

也就是：

```text
运行地址
```

---

## `LOADADDR`

```ld
LOADADDR(.data)
```

得到：

```text
.data LMA
```

也就是：

```text
存储/加载地址
```

---

## `SIZEOF`

```ld
SIZEOF(.data)
```

得到：

```text
.data 大小
```

所以：

```ld
data_start = ADDR(.data);
data_load_start = LOADADDR(.data);
data_size = SIZEOF(.data);
```

这三个变量组合起来就是经典的：

```text
ROM → RAM copy
```

元数据。

---

# 19. 给 linker script 加上这些符号

把：

```ld
.data :
{
    *(.data)
} > RAM AT > ROM
```

改成：

```ld
.data :
{
    data_start = .;

    *(.data)

    data_end = .;
} > RAM AT > ROM

data_load_start = LOADADDR(.data);
data_size = SIZEOF(.data);
```

完整一点：

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
        text_start = .;

        *(.text)

        text_end = .;
    } > ROM

    .rodata :
    {
        rodata_start = .;

        *(.rodata)

        rodata_end = .;
    } > ROM

    .data :
    {
        data_start = .;

        *(.data)

        data_end = .;
    } > RAM AT > ROM

    data_load_start = LOADADDR(.data);
    data_size = SIZEOF(.data);

    .bss :
    {
        bss_start = .;

        *(.bss)
        *(COMMON)

        bss_end = .;
    } > RAM
}
```

---

# 20. 用 nm 验证 linker 计算结果

执行：

```bash
nm -n custom.elf
```

寻找：

```text
data_start
data_end
data_load_start
data_size
```

你应该看到类似：

```text
000000000040....
0000000000600000 D data_start
0000000000600004 D data_end
000000000040.... A data_load_start
0000000000000004 A data_size
```

其中：

```text
data_start
```

是：

```text
.data VMA
```

而：

```text
data_load_start
```

是：

```text
.data LMA
```

---

# 21. 把整个过程串起来

现在我们已经可以画出：

```text
                 linker
                    │
                    ▼
              linker script
                    │
       ┌────────────┼────────────┐
       │            │            │
       ▼            ▼            ▼
     .text        .rodata       .data
       │            │            │
       ▼            ▼       ┌────┴─────┐
      ROM          ROM       │          │
                             ▼          ▼
                            VMA        LMA
                             │          │
                             ▼          ▼
                            RAM        ROM
```

而 `.bss`：

```text
.bss
  │
  ▼
 RAM
  │
  └── startup 清零
```

---

# 22. 为什么启动代码必须知道这些地址？

真正的裸机程序通常会有：

```c
extern char data_start[];
extern char data_load_start[];
extern char data_size[];
```

然后：

```c
memcpy(
    data_start,
    data_load_start,
    (size_t)data_size
);
```

实际上就是：

```text
                 Flash
                   │
        data_load_start
                   │
                   │ copy
                   ▼
                 RAM
                data_start
```

这也正好解释了你之前问过的那段代码为什么能够完成：

```text
.data 从 ROM → RAM
```

**不是 C 代码自己知道 ROM/RAM 地址。**

真正决定这些地址的是：

```text
linker.ld
```

然后：

```text
linker script
       ↓
产生符号
       ↓
C startup code
       ↓
根据符号执行 copy
```

---

# 23. 一个非常重要的认知升级

到这里，你应该开始把 `ld` 看成：

> **一个“地址计算器 + ELF 重组器 + 符号解析器”。**

例如：

```ld
data_start = .;
```

不是普通 C 变量。

它实际上是在告诉 linker：

> 当前 `.data` 的地址是多少？把这个数保存成 ELF 符号 `data_start`。

而：

```ld
data_size = SIZEOF(.data);
```

则是在链接阶段计算：

```text
.data 有多大？
```

所以：

```text
C 编译阶段
    ↓
不知道最终地址

ld 链接阶段
    ↓
确定地址
    ↓
生成符号
    ↓
生成 ELF

程序启动
    ↓
读取这些地址
    ↓
完成初始化
```

---

# 24. 今天必须掌握的 8 个东西

| 概念           | 含义            |
| ------------ | ------------- |
| `MEMORY`     | 描述目标内存        |
| `ORIGIN`     | 内存起始地址        |
| `LENGTH`     | 内存大小          |
| `> RAM`      | 指定 VMA 所在区域   |
| `AT > ROM`   | 指定 LMA 所在区域   |
| `ADDR()`     | 获取 VMA        |
| `LOADADDR()` | 获取 LMA        |
| `SIZEOF()`   | 获取 section 大小 |

尤其记住：

```text
> RAM
     ↓
    VMA

AT > ROM
     ↓
    LMA
```

---

# 25. 实验 03 的最终检查清单

执行：

```bash
gcc -c main.c -o main.o
gcc -c start.S -o start.o

ld -T linker.ld \
   start.o main.o \
   -o custom.elf \
   -Map=custom.map
```

然后依次：

```bash
./custom.elf
echo $?
```

```bash
readelf -S custom.elf
```

```bash
readelf -l custom.elf
```

```bash
objdump -h custom.elf
```

```bash
nm -n custom.elf
```

```bash
grep -A 15 -B 3 "\.data" custom.map
```

你真正要找的是：

```text
.data

VMA = RAM

LMA = ROM

SIZE = SIZEOF(.data)
```

---

# 26. 下一实验：进入真正的“嵌入式启动过程”

下一阶段就不再只是“观察 linker”，而是把整个机制闭环：

```text
                 linker.ld
                    │
        ┌───────────┼───────────┐
        ▼           ▼           ▼
      .text       .data        .bss
        │           │            │
        │       LMA → VMA        │
        │           │            │
        ▼           ▼            ▼
      Flash       Flash         RAM
                    │
                    │ startup
                    ▼
                   RAM
                    │
                    ▼
                  main()
```

然后会进入 **实验 04：自己写 `_start`，实现 `.data` 拷贝 + `.bss` 清零**。

届时会真正看到：

```c
extern char _sidata[];
extern char _sdata[];
extern char _edata[];

extern char _sbss[];
extern char _ebss[];
```

对应：

```text
         linker.ld
             │
             ▼
       产生这些地址
             │
             ▼
         start.S
             │
       ┌─────┴─────┐
       ▼           ▼
   copy .data   clear .bss
       │           │
       └─────┬─────┘
             ▼
          main()
```

再往后则会进入整个 `ld` 最核心的一组高级实验：

```text
实验 04  .data/.bss 启动初始化
实验 05  Section → Segment
实验 06  PHDRS：自己控制 PT_LOAD
实验 07  ALIGN / SUBALIGN / 对齐陷阱
实验 08  KEEP + --gc-sections
实验 09  PROVIDE / PROVIDE_HIDDEN / 符号可见性
实验 10  Archive .a：为什么 ld 有时“不链接”
实验 11  --start-group / --end-group：循环依赖
实验 12  weak / strong / COMMON 符号解析
实验 13  Overlay
实验 14  Version Script / 符号版本
实验 15  partial linking：ld -r
实验 16  LTO Plugin
实验 17  Map 文件逆向分析
实验 18  从零写一个 MCU linker.ld
实验 19  RISC-V startup + linker.ld
实验 20  完整 Bootloader → Application 链接布局
```

这一条路线走完，基本就从“**会使用 `ld`**”进入到“**能设计 linker script 和分析复杂 ELF 链接问题**”的阶段了。

