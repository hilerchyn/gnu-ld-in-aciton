# GNU ld 实战课程 · 实验 27

# `FILL()`、`.`、`ALIGN()`、`AT()`：精确控制 Firmware Binary 的 Padding

上一节实验 26，我们已经完成了：

```text
C/ASM
  ↓
Input Section
  ↓
Output Section
  ↓
VMA / LMA
  ↓
PT_LOAD
  ↓
ELF
  ↓
objcopy
  ↓
firmware.bin
```

这一节继续向前一步：**不只是决定“数据放在哪里”，还要决定“数据之间的空白区域是什么”。**

这在真实固件中非常重要，例如：

```text
Flash
0x00000000
│
├── Firmware Header
├── .text
├── 对齐 Padding
├── .rodata
├── 对齐 Padding
├── .data 镜像
├── CRC
└── Image End
```

我们会亲眼验证：

```text
. = ALIGN(...)
```

为什么会改变地址；

```text
FILL(0xFF)
```

为什么会真正改变 `firmware.bin` 中的字节；

以及：

```text
AT(...)
```

到底如何改变 `.data` 在 ROM 中的加载位置。

---

# 一、实验 27 的最终目标

最终制作这样的镜像：

```text
ROM / Flash
┌─────────────────────────────┐
│ Firmware Header             │
├─────────────────────────────┤
│ .text                       │
├─────────────────────────────┤
│ FF FF FF FF ...             │ ← padding
├─────────────────────────────┤
│ .rodata                     │
├─────────────────────────────┤
│ FF FF FF FF ...             │
├─────────────────────────────┤
│ .data image                 │
├─────────────────────────────┤
│ FF FF FF FF ...             │
├─────────────────────────────┤
│ CRC / metadata              │
└─────────────────────────────┘
```

然后通过：

```bash
readelf -SW firmware.elf
readelf -lW firmware.elf
objdump -h firmware.elf
objdump -s firmware.elf
hexdump -C firmware.bin
```

逐层验证。

---

# 二、实验 27-1：先建立最小工程

目录：

```text
lab27/
├── start.S
├── main.c
├── data.c
├── linker.ld
└── Makefile
```

---

# 三、`start.S`

继续使用极简启动代码：

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
extern int counter;
extern int magic;

extern char message[];

int main(void)
{
    counter++;
    magic++;

    return message[0];
}
```

---

# 五、`data.c`

这一节故意加入明显容易识别的数据。

```c
int counter = 1234;

int magic = 0x12345678;

char message[] = "GNU LD LAB 27";

const char version[] = "VERSION-27";

__attribute__((section(".firmware_header")))
const unsigned int firmware_magic = 0x46574D47;

__attribute__((section(".firmware_header")))
const unsigned int firmware_version = 0x00010000;
```

其中：

```text
0x46574D47
```

就是我们人为定义的 Firmware Magic。

---

# 六、编译

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
    -c data.c \
    -o data.o
```

检查：

```bash
objdump -h data.o
```

你应该能看到类似：

```text
.data
.data.counter
.data.magic
.data.message
.rodata
.rodata.version
.firmware_header
```

---

# 七、实验 27-2：最简单的 `ALIGN()`

先建立一个极简 linker：

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

    .rodata :
    {
        *(.rodata)
        *(.rodata.*)
    } > ROM
}
```

链接：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    data.o \
    -o align0.elf \
    -Map=align0.map
```

观察：

```bash
readelf -SW align0.elf
```

记录：

```text
.text
.rodata
```

的地址。

---

# 八、加入 0x100 对齐

现在改成：

```ld
SECTIONS
{
    .text :
    {
        *(.text)
        *(.text.*)
    } > ROM

    . = ALIGN(0x100);

    .rodata :
    {
        *(.rodata)
        *(.rodata.*)
    } > ROM
}
```

这里特别注意：

> 我们使用的是 `. = ALIGN(0x100);`，而不是把 `ALIGN()` 放到 Output Section 名称的位置。

也就是：

```ld
. = ALIGN(0x100);

.rodata :
{
    ...
}
```

而不是：

```ld
.rodata ALIGN(0x100) :
```

---

# 九、`ALIGN()` 到底干了什么？

假设：

```text
当前地址 = 0x00400053
```

执行：

```ld
. = ALIGN(0x100);
```

得到：

```text
0x00400100
```

所以：

```text
原来：

0x00400053
     │
     │ 0xAD bytes
     ▼
0x00400100
```

中间产生：

```text
padding
```

---

# 十、验证

重新链接：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    data.o \
    -o align100.elf \
    -Map=align100.map
```

然后：

```bash
readelf -SW align100.elf
```

比较：

```text
align0.elf
```

和：

```text
align100.elf
```

的：

```text
.text
.rodata
```

地址。

---

# 十一、Map 文件验证

打开：

```bash
less align100.map
```

找到：

```text
.text
```

和：

```text
.rodata
```

你会发现：

```text
.text
    ...
    
          ALIGN(0x100)
    
.rodata
```

之间存在地址跳跃。

这个跳跃就是：

```text
Padding
```

---

# 十二、实验 27-3：`ALIGN()` 不一定意味着 Binary 中一定出现这么多字节

这是一个非常重要的区别。

```ld
. = ALIGN(0x100);
```

首先改变的是：

```text
VMA
```

如果这个地址跳跃同时落在一个可加载的：

```text
PT_LOAD
```

文件范围内，那么它才会进一步体现为：

```text
File Padding
```

因此：

> **不要看到地址有 gap，就直接认为 ELF 文件中一定有同样大小的 gap。**

必须继续看：

```bash
readelf -lW align100.elf
```

---

# 十三、Section 层和 Segment 层必须同时看

例如：

```text
Section：

.text
VMA = 0x400040
Size = 0x50

.rodata
VMA = 0x400100
Size = 0x30
```

这里：

```text
0x400040 + 0x50 = 0x400090
```

而：

```text
.rodata = 0x400100
```

中间：

```text
0x70
```

是 Section 地址间隔。

但是否对应 ELF 文件中的实际 padding，要看：

```text
PT_LOAD
```

的：

```text
p_offset
p_filesz
```

---

# 十四、实验 27-4：第一次使用 `FILL()`

现在：

```ld
SECTIONS
{
    .text :
    {
        *(.text)
        *(.text.*)
    } > ROM

    . = ALIGN(0x100);

    .rodata :
    {
        *(.rodata)
        *(.rodata.*)
    } > ROM
}
```

加入：

```ld
FILL(0xFF)
```

完整：

```ld
SECTIONS
{
    .text :
    {
        *(.text)
        *(.text.*)
    } > ROM

    FILL(0xFF);

    . = ALIGN(0x100);

    .rodata :
    {
        *(.rodata)
        *(.rodata.*)
    } > ROM
}
```

---

# 十五、`FILL(0xFF)` 是什么？

它告诉 ld：

> Output Section 中没有被实际输入 Section 占据的区域，用指定的填充值填充。

例如：

```text
.text
0x40 bytes

然后：

ALIGN(0x100)
```

中间：

```text
0xC0 bytes
```

那么这些区域可以变成：

```text
FF FF FF FF FF FF ...
```

而不是：

```text
00 00 00 00 ...
```

---

# 十六、重新链接

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    data.o \
    -o fill.elf \
    -Map=fill.map
```

然后：

```bash
objdump -s fill.elf
```

重点看：

```text
Contents of section .text:
```

和：

```text
Contents of section .rodata:
```

---

# 十七、但是这里有一个非常容易踩坑的地方

`FILL()` 是：

# Output Section 的填充机制

而：

```bash
objcopy -O binary
```

生成 Raw Binary 时，还涉及：

```text
Segment
```

之间的 gap。

所以：

```ld
FILL(0xFF)
```

并不意味着：

> “整个 firmware.bin 的所有空洞自动变成 FF。”

它主要控制：

> **Output Section 内部的填充。**

这是一个非常关键的边界。

---

# 十八、实验 27-5：Section 内部 Padding

我们做一个非常容易观察的例子：

```ld
SECTIONS
{
    .text :
    {
        *(.text)
        
        . = ALIGN(0x100);

        BYTE(0x12);
    } > ROM
}
```

这里：

```ld
. = ALIGN(0x100);
```

把当前地址推到：

```text
0x100 边界
```

然后：

```ld
BYTE(0x12);
```

放一个明确的字节。

---

# 十九、验证

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    data.o \
    -o fill2.elf \
    -Map=fill2.map
```

然后：

```bash
objdump -s -j .text fill2.elf
```

如果当前 `.text` 原本只有：

```text
0x40
```

那么后面的：

```text
0xC0
```

区域就属于 Output Section 内部填充区域。

---

# 二十、实验 27-6：显式指定 `FILL`

可以写：

```ld
.text :
{
    *(.text)

    FILL(0xFF)

    . = ALIGN(0x100);

    BYTE(0x12);
} > ROM
```

然后：

```bash
objdump -s -j .text fill2.elf
```

寻找：

```text
FF FF FF FF ...
```

最终：

```text
... FF FF FF FF 12
```

---

# 二十一、`FILL()` 的另一个写法

也可以使用：

```ld
.text : FILL(0xFF)
{
    ...
}
```

但为了避免把：

```text
Section 属性
```

和：

```text
Output Section 内容
```

混在一起，我建议当前课程统一使用：

```ld
.text :
{
    ...
    FILL(0xFF)
    ...
}
```

这样阅读起来更加直观。

---

# 二十二、实验 27-7：`BYTE()`、`SHORT()`、`LONG()`、`QUAD()`

既然已经有：

```ld
BYTE(0x12)
```

继续认识四个非常有用的 linker script 命令：

```ld
BYTE(0x12)
SHORT(0x1234)
LONG(0x12345678)
QUAD(0x123456789ABCDEF0)
```

它们可以直接向输出 Section 写入数据。

---

# 二十三、Firmware Header 实验

创建：

```ld
.firmware_header :
{
    LONG(0x46574D47);       /* "FWMG" */
    LONG(0x00010000);       /* version */
    LONG(0);                /* image size */
    LONG(0);                /* CRC */

    KEEP(*(.firmware_header))
} > ROM
```

现在：

```text
.firmware_header
```

就不只是 C 数据了。

Linker 自己也写入：

```text
Magic
Version
Image Size
CRC
```

这已经开始接近真正的 Bootloader 镜像设计。

---

# 二十四、实验 27-8：查看 Header

链接：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    data.o \
    -o header.elf \
    -Map=header.map
```

执行：

```bash
readelf -SW header.elf
```

找到：

```text
.firmware_header
```

然后：

```bash
objdump -s -j .firmware_header header.elf
```

你应该能够看到：

```text
47 4d 57 46
00 00 01 00
00 00 00 00
00 00 00 00
```

注意 x86-64 小端表示：

```text
0x46574D47
```

会看到：

```text
47 4D 57 46
```

---

# 二十五、实验 27-9：理解 `.` 的真正含义

GNU ld linker script 中：

```ld
.
```

是：

# Location Counter

即：

> 当前输出地址。

例如：

```ld
.text :
{
    *(.text)

    . = ALIGN(0x100);

    BYTE(0xAA);

    . = . + 0x20;

    BYTE(0xBB);
}
```

如果进入时：

```text
. = 0x400040
```

假设 `.text` 结束：

```text
. = 0x400090
```

执行：

```ld
. = ALIGN(0x100);
```

变成：

```text
0x400100
```

然后：

```ld
BYTE(0xAA);
```

写入：

```text
0x400100
```

接着：

```ld
. = . + 0x20;
```

变成：

```text
0x400121
```

然后：

```ld
BYTE(0xBB);
```

写入新的位置。

---

# 二十六、这其实就是 linker 版的“指针”

可以把：

```ld
.
```

暂时理解为：

```c
current_address
```

所以：

```ld
. = ALIGN(0x100);
```

相当于：

```c
current_address =
    align_up(current_address, 0x100);
```

而：

```ld
. = . + 0x20;
```

相当于：

```c
current_address += 0x20;
```

这个理解方式对于学习 linker script 非常有用。

---

# 二十七、实验 27-10：`AT()` 真正控制 `.data` LMA

现在回到：

```ld
.data :
{
    *(.data)
} > RAM AT > ROM
```

这里 ld 会自动计算 `.data` 的：

```text
VMA
LMA
```

现在我们改成显式地址。

例如：

```ld
.data :
{
    __data_start = .;

    *(.data)
    *(.data.*)

    __data_end = .;
} > RAM AT(0x00401000)
```

注意这里：

```text
VMA
```

仍然由：

```text
RAM
```

决定。

而：

```text
LMA
```

被强制设成：

```text
0x00401000
```

---

# 二十八、验证 `AT()`

执行：

```bash
objdump -h firmware.elf
```

观察 `.data`：

```text
VMA
LMA
```

你应该看到：

```text
VMA = 0x00600000...
LMA = 0x00401000
```

这就是：

```text
运行地址 ≠ 加载地址
```

---

# 二十九、`AT > ROM` 与 `AT(地址)` 的区别

### 第一种：

```ld
.data > RAM AT > ROM
```

意思：

> VMA 放 RAM，LMA 放 ROM，由 ld 根据 ROM 当前地址安排。

---

### 第二种：

```ld
.data > RAM AT(0x00401000)
```

意思：

> VMA 放 RAM，LMA 强制指定为 0x00401000。

所以：

```text
AT > ROM
```

更适合：

```text
普通连续 Firmware Layout
```

而：

```text
AT(...)
```

更适合：

```text
精确控制镜像地址
```

---

# 三十、实验 27-11：制造两个 ROM 数据区

现在设计：

```text
ROM

0x00400000
    .text

0x00401000
    .rodata

0x00402000
    .data image
```

可以：

```ld
.text :
{
    *(.text)
} > ROM

. = ALIGN(0x1000);

.rodata :
{
    *(.rodata)
} > ROM

. = ALIGN(0x1000);

.data :
{
    *(.data)
} > RAM AT(ALIGN(...))
```

但是这里不能直接把：

```ld
AT(ALIGN(...))
```

当成通用正确写法。

更稳妥的方式是：

```ld
__data_load_start =
    ALIGN(LOADADDR(.rodata) + SIZEOF(.rodata), 0x1000);
```

然后：

```ld
.data :
{
    ...
} > RAM AT(__data_load_start)
```

不过这里会涉及 **Section 定位与 LMA 计算的时序**，所以工程上更推荐先采用：

```ld
.data > RAM AT > ROM
```

然后通过：

```ld
LOADADDR(.data)
```

读取 ld 计算结果。

这也是我们目前课程一直采用这种写法的原因。

---

# 三十一、实验 27-12：正确认识 `AT > ROM`

这是一个非常重要的结论：

```ld
.data > RAM AT > ROM
```

不是：

```text
.data 被放到 ROM
```

而是：

```text
.data

VMA
 ↓
RAM

LMA
 ↓
ROM
```

所以：

```text
ELF Section Table
```

里面：

```text
.data
```

的地址主要体现：

```text
VMA
```

而：

```text
Program Header / Load Image
```

才能让你进一步理解：

```text
LMA / File Offset
```

---

# 三十二、实验 27-13：用 `LOADADDR()` 验证

加入：

```ld
__data_load_start = LOADADDR(.data);
```

然后：

```bash
nm -n firmware.elf | grep __data_load_start
```

再：

```bash
objdump -h firmware.elf
```

比较。

你应该能够验证：

```text
__data_load_start
=
.data LMA
```

---

# 三十三、实验 27-14：制作一个明显的 Flash Layout

现在我们故意让每个区域对齐到 256 字节：

```ld
.text :
{
    *(.text)
    *(.text.*)
} > ROM

. = ALIGN(0x100);

.rodata :
{
    *(.rodata)
    *(.rodata.*)
} > ROM

. = ALIGN(0x100);

.firmware_header :
{
    KEEP(*(.firmware_header))
} > ROM

. = ALIGN(0x100);

.data :
{
    __data_start = .;

    *(.data)
    *(.data.*)

    __data_end = .;
} > RAM AT > ROM
```

现在：

```text
.text
   ↓
256-byte boundary
   ↓
.rodata
   ↓
256-byte boundary
   ↓
header
   ↓
256-byte boundary
   ↓
.data image
```

---

# 三十四、验证 Section 地址

```bash
readelf -SW firmware.elf
```

重点检查：

```text
.text
.rodata
.firmware_header
.data
```

它们是否落在：

```text
0x100
```

边界。

例如：

```text
0x00400040
0x00400100
0x00400200
0x00600000
```

---

# 三十五、Map 文件验证

```bash
grep -E \
    '^(\.text|\.rodata|\.firmware_header|\.data)' \
    firmware.map
```

或者直接：

```bash
less firmware.map
```

你要学会从 Map 中回答：

```text
.text 从哪里开始？

.text 结束在哪里？

.rodata 为什么从 0x100 边界开始？

header 到底多大？

.data VMA 在哪里？

.data LMA 在哪里？
```

---

# 三十六、实验 27-15：直接查看 Segment

现在：

```bash
readelf -lW firmware.elf
```

重点看：

```text
Offset
VirtAddr
PhysAddr
FileSiz
MemSiz
Flg
Align
```

尤其观察：

```text
p_filesz
```

如果：

```text
Section 地址
```

中存在 gap，而这些 Section 又属于同一个：

```text
PT_LOAD
```

那么 gap 很可能也成为：

```text
p_filesz
```

的一部分。

这就是：

```text
Section padding
```

如何最终影响：

```text
Segment file size
```

---

# 三十七、实验 27-16：Binary 最终验证

生成：

```bash
objcopy \
    -O binary \
    firmware.elf \
    firmware.bin
```

然后：

```bash
hexdump -C firmware.bin
```

寻找：

```text
FF FF FF FF
```

如果你之前的填充区域属于：

```text
Output Section
```

并且被包含进：

```text
loadable file contents
```

那么你会真正看到：

```text
FF
```

---

# 三十八、一个非常重要的区别：`FILL()` vs `--gap-fill`

现在比较：

```ld
FILL(0xFF)
```

和：

```bash
objcopy --gap-fill 0xFF
```

它们解决的问题不是完全相同。

---

## `FILL(0xFF)`

主要控制：

```text
Output Section
```

内部的填充。

---

## `objcopy --gap-fill 0xFF`

主要针对：

```text
输出 Binary 时，
不同 loadable sections / address ranges 之间的 gap
```

进行填充。

所以：

```text
FILL
```

和：

```text
--gap-fill
```

是两个不同层次的工具。

---

# 三十九、实验 27-17：同时使用两种机制

先 linker：

```ld
.text :
{
    FILL(0xAA);

    *(.text)

    . = ALIGN(0x100);

    BYTE(0x55);
} > ROM
```

然后：

```bash
objcopy \
    -O binary \
    firmware.elf \
    firmware.bin
```

再：

```bash
objcopy \
    -O binary \
    --gap-fill 0xFF \
    firmware.elf \
    firmware-ff.bin
```

比较：

```bash
cmp -l firmware.bin firmware-ff.bin | head
```

这样就能开始真正区分：

```text
Section fill
```

和：

```text
Binary gap fill
```

---

# 四十、实验 27-18：Flash Sector 对齐

真实 Flash 往往存在：

```text
Sector size
```

例如实验假定：

```text
Sector = 0x1000
```

那么可以：

```ld
. = ALIGN(0x1000);
```

于是：

```text
.text
──────────────

0x1000 boundary

.rodata
──────────────

0x1000 boundary

.data image
```

这在设计：

```text
Bootloader
Application
Configuration
Factory data
```

分区时非常有用。

---

# 四十一、建立真实 Firmware 分区模型

例如：

```text
Flash
0x00000000
│
├── Bootloader
│   0x00000000 - 0x00007FFF
│
├── Application
│   0x00008000 - 0x0007FFFF
│
├── Configuration
│   0x00080000 - 0x0008FFFF
│
└── Factory Data
    0x00090000 - ...
```

linker script 中：

```ld
MEMORY
{
    BOOT (rx) : ORIGIN = 0x00000000, LENGTH = 32K
    APP  (rx) : ORIGIN = 0x00008000, LENGTH = 480K
    RAM  (rw) : ORIGIN = 0x20000000, LENGTH = 128K
}
```

然后：

```ld
.text > APP
```

这样 linker 本身就可以检查：

```text
Application
```

有没有超过分区大小。

---

# 四十二、实验 27-19：故意让 ROM 溢出

暂时改：

```ld
ROM (rx) : ORIGIN = 0x00400000, LENGTH = 0x100
```

重新链接：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    data.o \
    -o overflow.elf \
    -Map=overflow.map
```

如果 Section 超过：

```text
0x100
```

应该看到类似：

```text
region `ROM' overflowed by ...
```

这就是：

```text
MEMORY
```

的价值。

---

# 四十三、实验 27-20：用 ASSERT 做更精确的限制

例如：

```ld
__image_size =
    __image_end - __image_start;

ASSERT(
    __image_size <= 0x10000,
    "ERROR: firmware image exceeds 64K"
);
```

现在 linker 不仅检查：

```text
Section 是否塞得进去
```

还检查：

```text
Firmware Image
```

自己的逻辑约束。

---

# 四十四、Map 文件开始成为“工程报告”

实验 26 以前：

```text
Map
=
辅助调试
```

现在：

```text
Map
=
Firmware Memory Report 的原始数据
```

你可以从 Map 中得到：

```text
.text size
.rodata size
.data size
.bss size
header size
padding
symbol address
```

然后进一步计算：

```text
ROM used
ROM free
RAM used
RAM free
```

---

# 四十五、实验 27-21：推荐建立一个固定检查流程

以后每次修改 linker.ld：

### 第一步

```bash
ld ... -Map=firmware.map
```

### 第二步

```bash
readelf -SW firmware.elf
```

检查：

```text
Section
Address
Offset
Size
Type
```

### 第三步

```bash
readelf -lW firmware.elf
```

检查：

```text
Segment
Offset
VirtAddr
PhysAddr
FileSiz
MemSiz
Flags
Align
```

### 第四步

```bash
objdump -h firmware.elf
```

检查：

```text
VMA
LMA
Size
```

### 第五步

```bash
nm -n firmware.elf
```

检查：

```text
linker symbols
```

### 第六步

```bash
objcopy -O binary firmware.elf firmware.bin
```

### 第七步

```bash
hexdump -C firmware.bin
```

最终确认：

```text
ELF Layout
=
Binary Layout
```

---

# 四十六、实验 27-22：建立一张“地址转换表”

假设最终：

```text
.text
VMA = 0x00400040
LMA = 0x00400040

.rodata
VMA = 0x00400100
LMA = 0x00400100

.data
VMA = 0x00600000
LMA = 0x00400200
```

那么：

| Section   |          VMA |          LMA | 作用        |
| --------- | -----------: | -----------: | --------- |
| `.text`   | `0x00400040` | `0x00400040` | ROM 执行    |
| `.rodata` | `0x00400100` | `0x00400100` | ROM 读取    |
| `.data`   | `0x00600000` | `0x00400200` | ROM → RAM |

这张表是分析 Firmware linker 的核心工具。

---

# 四十七、实验 27-23：理解 `ADDR()` 与 `LOADADDR()`

对于：

```ld
.data :
{
    ...
} > RAM AT > ROM
```

有：

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

所以：

```text
ADDR
 ↓
运行地址

LOADADDR
 ↓
加载地址
```

这两个函数一定要牢牢记住。

---

# 四十八、实验 27-24：计算 Copy 长度

```ld
__data_size = SIZEOF(.data);
```

于是 startup code 可以：

```text
source =
    __data_load_start

destination =
    __data_start

length =
    __data_size
```

即：

```text
ROM
│
│ __data_load_start
│
├──────────────┐
│ .data image  │
├──────────────┘
│
└──────────────

RAM
│
│ __data_start
│
├──────────────┐
│ .data        │
├──────────────┘
│
└──────────────
```

---

# 四十九、实验 27-25：最终 Firmware Header

这一节最后把这些知识组合起来：

```ld
.firmware_header :
{
    __header_start = .;

    LONG(0x46574D47);
    LONG(0x00010000);

    LONG(__image_start);
    LONG(__image_end);

    LONG(__image_end - __image_start);

    __header_end = .;
} > ROM
```

现在 Header 中已经有：

```text
Magic
Version
Image Start
Image End
Image Size
```

这已经是一个真正的 Firmware Metadata Header。

---

# 五十、验证 Header

```bash
objdump -s -j .firmware_header firmware.elf
```

以及：

```bash
readelf -SW firmware.elf
```

再：

```bash
nm -n firmware.elf | grep '__image'
```

把：

```text
__image_start
__image_end
```

和：

```text
Header
```

中的数值进行对应。

---

# 五十一、这里有一个非常重要的“链接时计算”

例如：

```ld
LONG(__image_end - __image_start);
```

不是 C 程序运行时计算。

而是：

# ld 在链接阶段计算。

也就是说：

```text
C compiler
```

不知道：

```text
最终 firmware image size
```

但是：

```text
ld
```

知道。

所以：

```text
Linker Script
```

特别适合生成：

```text
Image Size
Memory Boundary
CRC location
Stack Top
Heap Start
Section Size
```

这些：

# 编译完成后才能确定的值。

---

# 五十二、实验 27-26：当前课程知识已经形成闭环

现在你已经掌握：

```text
MEMORY
    ↓
定义物理区域

SECTIONS
    ↓
定义 Section 布局

.
    ↓
控制当前地址

ALIGN()
    ↓
控制地址边界

FILL()
    ↓
控制 Section 内部填充

AT()
    ↓
控制 LMA

ADDR()
    ↓
VMA

LOADADDR()
    ↓
LMA

SIZEOF()
    ↓
Section 大小

PHDRS
    ↓
Segment

objcopy
    ↓
Raw Binary

ASSERT
    ↓
链接时检查
```

---

# 五十三、最终实验：完整验证链

把最终版本链接：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    data.o \
    -o firmware.elf \
    -Map=firmware.map
```

然后依次：

```bash
readelf -h firmware.elf
```

```bash
readelf -SW firmware.elf
```

```bash
readelf -lW firmware.elf
```

```bash
objdump -h firmware.elf
```

```bash
objdump -p firmware.elf
```

```bash
objdump -s firmware.elf
```

```bash
nm -n firmware.elf
```

```bash
objcopy \
    -O binary \
    firmware.elf \
    firmware.bin
```

最后：

```bash
hexdump -C firmware.bin
```

---

# 五十四、这一节最重要的知识图

```text
                    linker.ld
                       │
       ┌───────────────┼────────────────┐
       │               │                │
    MEMORY          SECTIONS           PHDRS
       │               │                │
       │          ┌────┼────┐           │
       │          │    │    │           │
       │          .    >   AT()         │
       │          │         │           │
       │       ALIGN()    LMA           │
       │          │         │           │
       └──────────┼─────────┘           │
                  │                     │
                  ▼                     ▼
              Sections              Segments
                  │                     │
                  └─────────┬───────────┘
                            ▼
                         ELF
                            │
             ┌──────────────┼─────────────┐
             │              │             │
         readelf          objdump        map
             │              │             │
             └──────────────┼─────────────┘
                            ▼
                        objcopy
                            │
                            ▼
                      firmware.bin
                            │
                            ▼
                         Flash
```

---

# 五十五、实验 27 的核心结论

这一节最容易混淆的四个东西，现在可以这样记：

```text
. = ...
```

控制：

> **当前地址**

```text
ALIGN(...)
```

控制：

> **地址边界**

```text
FILL(...)
```

控制：

> **Output Section 内部空白区域的填充值**

```text
AT(...)
```

控制：

> **Section 的加载地址 LMA**

而：

```bash
objcopy --gap-fill
```

是在：

> **把 ELF 转成 Binary 的过程中处理地址范围之间的 gap。**

---

# 五十六、下一节：实验 28 —— `KEEP()` + `--gc-sections` + Garbage Collection

下一阶段开始进入真正工程中非常重要的一部分：

```text
为什么我明明定义了一个 Section，
链接以后它却消失了？
```

我们将制作：

```text
used_function()
unused_function()

used_data
unused_data

.firmware_header
.factory_data
```

然后分别使用：

```bash
--gc-sections
```

观察：

```text
没有 KEEP()
        ↓
Section 被回收

加入 KEEP()
        ↓
Section 保留
```

并进一步研究：

```ld
KEEP(*(.firmware_header))
```

为什么能够“阻止垃圾回收”。

随后会进入：

```text
EXCLUDE_FILE()
SORT_BY_NAME()
SORT_BY_ALIGNMENT()
/DISCARD/
```

最终制作一个非常接近真实嵌入式工程的：

```text
Bootloader
    ↓
Application
    ↓
Firmware Metadata
    ↓
Factory Configuration
    ↓
CRC
    ↓
Raw Binary
```

链接布局。

