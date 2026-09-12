# GNU ld 实战课程 · 实验 13

## VMA / LMA / `AT()` / `LOADADDR()`：`.data` 为什么“运行在 RAM，却存储在 ROM”？

上一节我们已经把：

```text
Archive
   ↓
Symbol Resolution
   ↓
Relocation
   ↓
最终 ELF
```

完整串起来了。

这一节进入 GNU `ld` linker script 中一个**非常关键、也是最容易混淆的概念**：

> **一个 Output Section 可以同时拥有两个不同的地址：VMA 和 LMA。**

这正是嵌入式程序能够做到：

```text
Flash / ROM
    │
    │ 保存 .data 初始值
    ▼
RAM
    │
    │ 程序运行时访问
    ▼
.data
```

的根本原因。

GNU ld 文档明确规定：每个 section 都有 VMA 和 LMA；VMA 是运行时虚拟地址，而 `AT` / `AT>` 可以指定不同的加载地址。`LOADADDR(section)` 则可以取得该 section 的 LMA。([Sourceware][1])

---

# 一、先把最核心的概念搞清楚

先看：

```ld
.data :
{
    *(.data)
} > RAM AT > ROM
```

这里有两个地址：

```text
             .data
               │
       ┌───────┴────────┐
       │                │
       ▼                ▼
      VMA              LMA
       │                │
       ▼                ▼
      RAM              ROM
```

也就是：

```text
VMA
=
程序运行时访问这个 section 的地址

LMA
=
这个 section 的初始内容存放在哪里
```

所以：

```text
.data
VMA = RAM
LMA = ROM
```

这正是 MCU 固件中最典型的布局。

---

# 二、为什么 `.data` 需要两个地址？

假设：

```c
int counter = 123;
```

这个变量有一个非常特殊的属性：

```text
① 程序启动后需要修改
② 所以必须放 RAM
③ 但是程序烧录到 Flash 后，初始值 123 必须有地方保存
```

于是：

```text
Flash:

123
 ↓
程序镜像


启动：

Flash
  │
  │ copy
  ▼
RAM

counter = 123
```

所以：

```text
初始镜像
    ↓
Flash / ROM

运行时对象
    ↓
RAM
```

这就是：

```text
LMA ≠ VMA
```

---

# 三、实验 13-1：先制造一个最简单的 `.data`

目录：

```text
ld-lab/
├── main.c
├── start.S
└── linker.ld
```

---

# 四、main.c

```c
int global_value = 0x12345678;

int main(void)
{
    return global_value & 0xff;
}
```

这里：

```c
int global_value = 0x12345678;
```

因为有显式初始值：

```text
global_value
      ↓
.data
```

---

# 五、start.S

继续使用我们的最小启动代码：

```asm
.global _start

.extern main

_start:
    call main

    mov %eax, %edi
    mov $60, %eax
    syscall

.section .note.GNU-stack,"",@progbits
```

---

# 六、第一版 linker.ld：让 `.data` 运行在 RAM

这次正式建立：

```text
ROM
RAM
```

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
        *(.rodata)
        *(.rodata.*)
    } > ROM :text

    .data :
    {
        _sdata = .;

        *(.data)
        *(.data.*)

        _edata = .;
    } > RAM AT > ROM :data

    .bss :
    {
        _sbss = .;

        *(.bss)
        *(.bss.*)
        *(COMMON)

        _ebss = .;
    } > RAM :data
}
```

注意这一行：

```ld
.data : { ... } > RAM AT > ROM :data
```

它同时完成两件事：

```text
> RAM
    ↓
VMA

AT > ROM
    ↓
LMA
```

---

# 七、编译

```bash
gcc -c main.c -o main.o
gcc -c start.S -o start.o
```

检查：

```bash
readelf -S main.o
```

找到：

```text
.data
```

再：

```bash
objdump -h main.o
```

可以看到 `.data` 的大小和对齐信息。

---

# 八、链接

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    -o vma-lma.elf \
    -Map=vma-lma.map
```

---

# 九、第一件必须看的东西：`readelf -S`

执行：

```bash
readelf -S vma-lma.elf
```

找到：

```text
.text
.rodata
.data
.bss
```

重点观察 `.data`。

你会发现：

```text
Address
```

应该接近：

```text
0x00600000
```

因为：

```ld
.data ... > RAM
```

所以：

```text
.data VMA
=
RAM
=
0x00600000...
```

---

# 十、但是这里有个坑

你只看：

```bash
readelf -S
```

还不能完整看到：

```text
.data 的 LMA
```

因为：

```text
readelf -S
```

主要告诉你：

```text
Section
Address
Offset
Size
```

真正观察：

```text
VMA
LMA
```

的好工具之一是：

```bash
objdump -h
```

---

# 十一、使用 `objdump -h`

执行：

```bash
objdump -h vma-lma.elf
```

你会看到类似：

```text
Idx Name      Size      VMA               LMA
...
 1 .text      ...       0000000000400000  0000000000400000
 2 .rodata    ...       00000000004000xx  00000000004000xx
 3 .data      ...       0000000000600000  00000000004000xx
 4 .bss       ...       00000000006000xx  00000000006000xx
```

这里就是今天最重要的一张表：

```text
Section      VMA             LMA
------------------------------------------------
.text        0x00400000      0x00400000
.rodata      0x00400xxx      0x00400xxx
.data        0x00600000      0x00400xxx
.bss         0x00600xxx      0x00600xxx
```

也就是说：

```text
.data
    VMA = 0x00600000...
    LMA = 0x00400xxx...
```

这就是：

# VMA ≠ LMA

---

# 十二、画成内存地图就非常直观了

假设：

```text
ROM
0x00400000
    │
    ├── .text
    │
    ├── .rodata
    │
    └── .data 的初始镜像
            │
            │ LMA
            │
            ▼

RAM
0x00600000
    │
    ├── .data
    │
    └── .bss
```

所以：

```text
Flash / ROM 镜像
       │
       │
       │ copy
       ▼
RAM runtime
```

---

# 十三、为什么 `.bss` 没有独立 LMA 数据？

例如：

```c
int global_zero;
```

它：

```text
没有初始值
```

所以不需要在 ROM 中保存：

```text
00000000
```

几十 KB 的零。

只需要：

```text
启动时：

RAM .bss
    ↓
全部清零
```

因此：

```text
.data
    初始值来自 ROM

.bss
    启动代码直接清零
```

这就是为什么：

```text
ELF / 固件
```

通常不会真的为 `.bss` 保存同样大小的 ROM 数据。

---

# 十四、实验 13-2：使用 `LOADADDR()`

现在在 linker script 中增加：

```ld
_data_load = LOADADDR(.data);
```

放在 `.data` 后面：

```ld
.data :
{
    _sdata = .;

    *(.data)
    *(.data.*)

    _edata = .;
} > RAM AT > ROM :data

_data_load = LOADADDR(.data);
```

这里：

```ld
_data_load = LOADADDR(.data);
```

得到：

```text
.data 的 LMA
```

而：

```ld
_sdata
```

是：

```text
.data 的 VMA 起始
```

所以：

```text
_sdata
    ↓
VMA

_data_load
    ↓
LMA
```

---

# 十五、重新链接

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    -o vma-lma-symbol.elf \
    -Map=vma-lma-symbol.map
```

---

# 十六、用 `nm` 验证

```bash
nm -n vma-lma-symbol.elf | grep -E '_sdata|_edata|_data_load'
```

你会看到类似：

```text
00000000004000xx A _data_load
0000000000600000 D _sdata
0000000000600004 D _edata
```

重点：

```text
_sdata
```

是 RAM 地址。

而：

```text
_data_load
```

是 ROM 地址。

所以：

```text
_data_load
      │
      │ source
      ▼
ROM

_sdata
      │
      │ destination
      ▼
RAM
```

---

# 十七、这三个 linker symbol 是嵌入式启动代码的经典组合

以后你会经常看到：

```ld
_sdata = .;
...
_edata = .;

_data_load = LOADADDR(.data);
```

然后 C：

```c
extern char _data_load[];
extern char _sdata[];
extern char _edata[];
```

启动代码：

```c
memcpy(
    _sdata,
    _data_load,
    _edata - _sdata
);
```

也就是：

```text
src = _data_load
dst = _sdata
size = _edata - _sdata
```

---

# 十八、这和你之前研究的 `.data` 搬运代码完全对应

之前我们研究过：

```c
extern char data_start[];
extern char data_size[];
extern char data_load_start[];

void copy_data(void)
{
    if (data_start != data_load_start) {
        memcpy(
            data_load_start,
            data_start,
            (size_t)data_size
        );
    }
}
```

现在从 linker 的角度重新解释：

```text
data_start
    ↓
.data VMA

data_load_start
    ↓
.data LMA

data_size
    ↓
SIZEOF(.data)
```

也就是说，这三个值都可以由 linker 自动产生。

---

# 十九、实验 13-3：让 linker 自动产生 size

继续增加：

```ld
_data_size = SIZEOF(.data);
```

于是：

```ld
.data :
{
    _sdata = .;

    *(.data)
    *(.data.*)

    _edata = .;
} > RAM AT > ROM :data

_data_load = LOADADDR(.data);
_data_size = SIZEOF(.data);
```

---

# 二十、重新链接

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    -o data-symbols.elf \
    -Map=data-symbols.map
```

查看：

```bash
nm -n data-symbols.elf \
    | grep -E '_sdata|_edata|_data_load|_data_size'
```

例如：

```text
_data_load
_sdata
_edata
_data_size
```

---

# 二十一、验证这个公式

应该满足：

```text
_data_size
=
_edata - _sdata
```

例如：

```text
_sdata     = 0x600000
_edata     = 0x600004
```

那么：

```text
_data_size = 4
```

而：

```text
_data_load
```

则是：

```text
.data 在 ROM 中的起始位置
```

所以最终得到：

```text
Source:
    _data_load

Destination:
    _sdata

Length:
    _data_size
```

---

# 二十二、用 shell 验证

可以直接：

```bash
nm -n data-symbols.elf
```

然后人工检查：

```text
_edata - _sdata
=
_data_size
```

也可以使用：

```bash
readelf -s data-symbols.elf \
    | grep -E '_sdata|_edata|_data_load|_data_size'
```

---

# 二十三、实验 13-4：理解 `ADDR()` 和 `LOADADDR()` 的区别

这是本节最值得记住的两个函数。

```ld
ADDR(.data)
```

得到：

```text
.data VMA
```

而：

```ld
LOADADDR(.data)
```

得到：

```text
.data LMA
```

因此：

```text
ADDR(.data)
      ↓
VMA

LOADADDR(.data)
      ↓
LMA
```

GNU ld 文档专门区分了 output section address 和 load address；`AT`/`AT>`负责 LMA，`LOADADDR`用于取得该值。([Sourceware][1])

---

# 二十四、同时生成两个符号

```ld
_data_vma = ADDR(.data);
_data_lma = LOADADDR(.data);
```

然后：

```bash
nm -n data-symbols.elf \
    | grep -E '_data_vma|_data_lma'
```

应该看到：

```text
_data_vma
    ≈ 0x00600000

_data_lma
    ≈ 0x00400xxx
```

这样就不会再混淆：

```text
ADDR()
```

和：

```text
LOADADDR()
```

---

# 二十五、实验 13-5：直接使用 `AT()`

前面：

```ld
.data :
{
    ...
} > RAM AT > ROM
```

是：

```text
指定一个 Memory Region
```

现在我们换成：

```ld
.data :
{
    _sdata = .;

    *(.data)

    _edata = .;
}
> RAM
AT(ADDR(.text) + SIZEOF(.text))
:data
```

也就是：

```text
.data VMA
    ↓
RAM

.data LMA
    ↓
.text 结束位置
```

GNU ld 文档给出的经典 ROM-image 示例就是通过 `AT(ADDR(.text) + SIZEOF(.text))` 把 `.data` 的 LMA 放到 `.text` 后面，同时 `.data` 的 VMA 可以位于另一个地址空间。([Sourceware][2])

---

# 二十六、为什么这个写法非常有价值？

因为：

```ld
AT > ROM
```

让 linker 自动寻找：

```text
ROM 中下一个可用地址
```

而：

```ld
AT(ADDR(.text) + SIZEOF(.text))
```

则明确告诉 linker：

> `.data` 的加载镜像紧跟在 `.text` 后面。

于是：

```text
ROM
0x00400000
    │
    ├── .text
    │
    └── .data LOAD IMAGE
```

而：

```text
RAM
0x00600000
    │
    └── .data RUNTIME
```

---

# 二十七、完整 linker.ld

现在整理成一个适合后续实验继续使用的版本：

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
        *(.rodata)
        *(.rodata.*)
    } > ROM :text

    .data :
    {
        _sdata = .;

        *(.data)
        *(.data.*)

        _edata = .;
    } > RAM AT > ROM :data

    _data_load = LOADADDR(.data);
    _data_size = SIZEOF(.data);

    .bss :
    {
        _sbss = .;

        *(.bss)
        *(.bss.*)
        *(COMMON)

        _ebss = .;
    } > RAM :data

    _data_vma = ADDR(.data);
    _data_lma = LOADADDR(.data);
}
```

---

# 二十八、现在重点观察 `readelf -S`

```bash
readelf -S data-symbols.elf
```

重点：

```text
.data
```

看：

```text
Address
Offset
Size
```

其中：

```text
Address
```

就是：

```text
VMA
```

---

# 二十九、再看 `objdump -h`

```bash
objdump -h data-symbols.elf
```

这里重点观察：

```text
Name
Size
VMA
LMA
File off
```

你应该形成这样的认识：

```text
.data
 ├── Size
 ├── VMA = RAM
 └── LMA = ROM
```

这条命令是这节实验最值得反复执行的命令之一。

---

# 三十、再看 Program Header

现在执行：

```bash
readelf -l data-symbols.elf
```

不要只看：

```text
Section to Segment mapping
```

先看：

```text
LOAD
```

例如：

```text
LOAD
    Offset
    VirtAddr
    PhysAddr
    FileSiz
    MemSiz
    Flags
```

这里特别重要：

```text
VirtAddr
```

与：

```text
PhysAddr
```

在 ELF program header 中分别承担不同语义；对于我们的 linker-script 实验，可以利用它们观察 section 的运行地址和加载相关布局。

---

# 三十一、为什么 `readelf -l` 比 `readelf -S` 更重要？

因为：

```text
Section
```

主要回答：

> ELF 内部有哪些 section？

而：

```text
Program Header
```

回答：

> 程序装载时，哪些内容组成一个 Loadable Segment？

这就是：

```text
Section
    ↓
链接器内部组织

Segment
    ↓
加载器真正装载
```

所以后面的课程我们会逐渐从：

```text
Section-centric
```

进入：

```text
Segment-centric
```

---

# 三十二、Map 文件现在怎么看？

执行：

```bash
grep -A 20 -B 5 "\.data" data-symbols.map
```

你会看到类似：

```text
.data           0x0000000000600000        0x4
                0x0000000000600000                _sdata = .
 *(.data)
 .data          ...
                0x0000000000600004                _edata = .

                0x00000000004000xx                _data_load = LOADADDR (.data)
                0x0000000000000004                _data_size = SIZEOF (.data)
```

这里 Map 文件第一次真正体现出：

```text
Section
+
VMA
+
LMA
+
Symbol
+
Size
```

之间的关系。

---

# 三十三、特别注意：`.` 永远要小心

在：

```ld
.data :
{
    _sdata = .;
    *(.data)
    _edata = .;
}
> RAM AT > ROM
```

这里：

```text
.
```

表示的是：

> **当前 Output Section 的 VMA location counter。**

不是 LMA。

GNU ld 官方文档中的示例也特别指出，在具有不同 LMA/VMA 的 section 中，`.` 反映的是 VMA，而不是 LMA。([Sourceware][2])

所以：

```ld
_sdata = .;
```

得到：

```text
RAM 地址
```

而不是：

```text
ROM 地址
```

要得到 ROM 地址：

```ld
_data_load = LOADADDR(.data);
```

---

# 三十四、这是一个非常容易犯的错误

错误理解：

```ld
.data > RAM AT > ROM
```

然后认为：

```ld
.data
{
    _start = .;
}
```

这里：

```text
_start
```

应该是 ROM 地址。

❌ 错。

正确：

```text
. = VMA
```

因此：

```text
_start
=
.data VMA
=
RAM
```

而：

```ld
LOADADDR(.data)
```

才是：

```text
.data LMA
=
ROM
```

---

# 三十五、实验 13-6：加入 `.bss`

继续：

```c
int global_value = 0x12345678;
int zero_value;
```

完整：

```c
int global_value = 0x12345678;
int zero_value;

int main(void)
{
    return global_value + zero_value;
}
```

重新：

```bash
gcc -c main.c -o main.o
ld \
    -T linker.ld \
    start.o \
    main.o \
    -o data-bss.elf \
    -Map=data-bss.map
```

---

# 三十六、比较 `.data` 和 `.bss`

```bash
objdump -h data-bss.elf
```

观察：

```text
.data
.bss
```

应该理解为：

```text
.data
    VMA = RAM
    LMA = ROM
    File contents = 有

.bss
    VMA = RAM
    LMA 通常不需要实际数据镜像
    File contents = 不需要保存零
```

所以：

```text
.data
```

需要：

```text
ROM image
```

而：

```text
.bss
```

只需要：

```text
RAM allocation
```

---

# 三十七、用 `readelf -S` 验证 `.bss`

```bash
readelf -S data-bss.elf
```

重点看：

```text
.data
.bss
```

`.bss` 的：

```text
Type
```

通常是：

```text
NOBITS
```

这四个字母特别重要：

```text
NOBITS
```

意思是：

> 这个 section 在 ELF 文件中不需要保存对应的数据内容。

所以：

```text
.bss = NOBITS
```

正好解释：

> 为什么几十 KB 的全局零初始化变量不会让 Flash 镜像增加几十 KB。

---

# 三十八、`readelf -S` 与 `objdump -h` 形成互补

建议以后：

```bash
readelf -S xxx.elf
```

主要看：

```text
Section Header
```

而：

```bash
objdump -h xxx.elf
```

主要快速看：

```text
Size
VMA
LMA
File Offset
```

两者一起使用。

---

# 三十九、实验 13-7：自己验证 `SIZEOF()`

现在我们故意增加：

```c
char data1[16] = {
    1, 2, 3, 4
};
```

再：

```c
char data2[32] = {
    5, 6, 7, 8
};
```

然后：

```bash
gcc -c main.c -o main.o
ld \
    -T linker.ld \
    start.o main.o \
    -o sizeof.elf \
    -Map=sizeof.map
```

执行：

```bash
nm -n sizeof.elf | grep _data_size
```

再：

```bash
objdump -h sizeof.elf
```

观察：

```text
.data Size
```

然后验证：

```text
_data_size
=
.data Size
```

这就是：

```ld
SIZEOF(.data)
```

最直接的用途。

---

# 四十、几个 linker script 函数形成一个非常漂亮的组合

现在我们已经掌握：

```ld
ADDR(.data)
```

```ld
LOADADDR(.data)
```

```ld
SIZEOF(.data)
```

可以组成：

```text
┌──────────────────────────────┐
│            .data             │
├──────────────────────────────┤
│ VMA                          │
│ ADDR(.data)                  │
│                              │
│ LMA                          │
│ LOADADDR(.data)              │
│                              │
│ SIZE                         │
│ SIZEOF(.data)                │
└──────────────────────────────┘
```

于是启动代码需要的全部信息：

```text
source
destination
size
```

linker 都可以自动提供。

---

# 四十一、形成标准 `.data` 初始化模型

最终可以定义：

```ld
_sdata = ADDR(.data);
_edata = ADDR(.data) + SIZEOF(.data);

_data_load = LOADADDR(.data);
_data_size = SIZEOF(.data);
```

启动阶段：

```c
memcpy(
    _sdata,
    _data_load,
    _data_size
);
```

等价于：

```text
ROM:
    _data_load
       │
       │ _data_size
       ▼
    [ .data image ]
       │
       │ memcpy
       ▼
RAM:
    _sdata
       │
       ▼
    [ .data runtime ]
       │
       ▼
    _edata
```

---

# 四十二、但是我们的 Linux 实验还有一个“现实世界”问题

这里必须特别说明：

我们现在使用：

```text
0x00400000
0x00600000
```

模拟：

```text
ROM
RAM
```

是为了学习 linker。

但在普通 Linux 用户进程中：

```text
0x00600000
```

并不是一个真实 MCU 的 RAM 区域。

所以：

```text
VMA/LMA
```

的思想完全正确，但：

```text
AT > ROM
```

这种布局真正最有意义的环境是：

```text
裸机
Bootloader
RTOS
MCU
SoC
Firmware
```

而不是普通 Linux ELF。

这也是为什么后面我们要逐步从：

```text
Linux host
```

过渡到：

```text
bare-metal style ELF
```

---

# 四十三、下一步实验会做一个真正的“启动搬运”

下一节将把：

```text
linker script
+
C
+
Assembly
```

真正连接起来。

我们会构造：

```text
ROM
│
├── .text
├── .rodata
└── .data image
         │
         │ copy_data()
         ▼
RAM
│
├── .data
└── .bss
```

然后实现：

```c
extern char _data_load[];
extern char _sdata[];
extern char _edata[];

extern char _sbss[];
extern char _ebss[];

void init_data_bss(void)
{
    char *src = _data_load;
    char *dst = _sdata;

    while (dst < _edata)
        *dst++ = *src++;

    dst = _sbss;

    while (dst < _ebss)
        *dst++ = 0;
}
```

再让：

```asm
_start:
    call init_data_bss
    call main
```

最终通过：

```bash
readelf -S
readelf -l
objdump -h
objdump -s
objdump -d
nm
```

以及：

```text
Map
```

完整验证：

```text
ROM .data image
       │
       │
       │ memcpy
       ▼
RAM .data
       │
       ▼
main()
```

这样我们就会从“**理解 VMA/LMA**”正式进入“**用 linker script 构造启动代码**”。

---

## 本节必须掌握的 8 个概念

| 语法/概念             | 含义                           |
| ----------------- | ---------------------------- |
| `> RAM`           | 设置 Output Section 的 VMA 所属区域 |
| `AT(lma)`         | 显式指定 LMA                     |
| `AT > ROM`        | 从 ROM Memory Region 分配 LMA   |
| `ADDR(.data)`     | `.data` 的 VMA                |
| `LOADADDR(.data)` | `.data` 的 LMA                |
| `SIZEOF(.data)`   | `.data` 大小                   |
| `readelf -S`      | 查看 Section                   |
| `objdump -h`      | 快速查看 VMA/LMA/Size            |

最核心的一句话：

```text
> RAM
    ↓
“运行在哪里？”

AT > ROM
    ↓
“初始镜像存在哪里？”
```

而：

```text
ADDR()
    ↓
VMA

LOADADDR()
    ↓
LMA

SIZEOF()
    ↓
长度
```

这三个函数，基本就是下一阶段理解 **`.data` 搬运、启动代码、Flash → RAM 初始化** 的钥匙。 ([Sourceware][1])

[1]: https://sourceware.org/binutils/docs/ld.pdf?utm_source=chatgpt.com "The GNU linker"
[2]: https://sourceware.org/binutils/docs-2.39/ld.pdf?utm_source=chatgpt.com "The GNU linker"

