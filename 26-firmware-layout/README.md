# GNU ld 实战课程 · 实验 26

# 构造真正的 ROM → RAM Firmware 镜像

上一节我们已经完成了一个非常关键的跨越：

```text
Section
   ↓
VMA / LMA
   ↓
PHDRS
   ↓
PT_LOAD
   ↓
File Offset / VirtAddr / PhysAddr
```

这一节开始进入真正的 **Firmware Linker Script**。

我们不再满足于：

```text
readelf -lW
```

“看起来正确”。

而是要最终得到一个可以明确解释的镜像：

```text
ROM / Flash
┌──────────────────────────────┐
│ .text                        │
│ .rodata                      │
│ .data 的初始化镜像            │
│ firmware metadata            │
└──────────────────────────────┘

RAM
┌──────────────────────────────┐
│ .data                        │ ← 从 ROM copy
│ .bss                         │ ← 启动时清零
│ heap                         │
│ ...                          │
│ stack                        │
└──────────────────────────────┘
```

并进一步：

```text
firmware.elf
      ↓
objcopy
      ↓
firmware.bin
      ↓
hexdump
```

最终直接观察：

> **linker script 设计出来的 ROM 布局，究竟变成了什么二进制字节。**

---

# 一、实验 26 的学习目标

这一节完成 8 件事情：

```text
① 设计 ROM/RAM Firmware Layout

② .data：
   VMA → RAM
   LMA → ROM

③ .bss：
   VMA → RAM
   不占 ROM 镜像

④ 定义 __data_load_start

⑤ 定义 __data_start / __data_end

⑥ 定义 stack_top / heap_start

⑦ 使用 objcopy 生成 firmware.bin

⑧ 用 objdump/hexdump 验证二进制镜像
```

最终形成：

```text
             linker.ld
                 │
                 ▼
          firmware.elf
                 │
       ┌─────────┴─────────┐
       │                   │
    Section              Segment
       │                   │
       └─────────┬─────────┘
                 │
                 ▼
            objcopy
                 │
                 ▼
          firmware.bin
                 │
                 ▼
          Flash / ROM
```

---

# 二、实验目录

建立：

```text
lab26/
├── start.S
├── main.c
├── data.c
├── linker.ld
└── Makefile
```

---

# 三、实验 26-1：准备一份真正适合观察镜像的数据

`data.c`：

```c
int counter = 1234;

int magic = 0x12345678;

char message[] = "GNU ld firmware";

const char version[] = "FW-26";

int bss_buffer[256];
```

这里故意制造四种不同情况：

```text
counter
    ↓
.data

magic
    ↓
.data

message
    ↓
.data

version
    ↓
.rodata

bss_buffer
    ↓
.bss
```

所以最终：

```text
ROM
├── .text
├── .rodata
└── .data image

RAM
├── .data
└── .bss
```

---

# 四、`main.c`

```c
extern int counter;
extern int magic;

extern char message[];
extern const char version[];

extern int bss_buffer[];

int main(void)
{
    counter++;
    magic++;

    bss_buffer[0] = counter;

    return message[0] + version[0];
}
```

---

# 五、`start.S`

这一节先做一个极简启动代码。

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

先不要加入 `.data` copy 和 `.bss` clear。

这一节先专门观察：

> linker 产生的镜像到底是什么。

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
objdump -h start.o
objdump -h main.o
objdump -h data.o
```

---

# 七、实验 26-2：先确认 Input Section

执行：

```bash
objdump -h data.o
```

重点应该能够看到类似：

```text
.data
.data.counter
.data.magic
.data.message
.rodata
.rodata.version
.bss
.bss.bss_buffer
```

因为使用了：

```bash
-fdata-sections
```

不同变量可能进入独立的 Input Section。

这正好可以让我们观察：

```text
Input Section
      ↓
Output Section
      ↓
Segment
      ↓
Binary Image
```

完整链路。

---

# 八、实验 26-3：Firmware linker script

现在创建：

```text
linker.ld
```

内容：

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
    . = SIZEOF_HEADERS;

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
        __data_start = .;

        *(.data)
        *(.data.*)

        __data_end = .;
    } > RAM AT > ROM :data

    __data_load_start = LOADADDR(.data);
    __data_size = SIZEOF(.data);

    .bss :
    {
        __bss_start = .;

        *(.bss)
        *(.bss.*)
        *(COMMON)

        __bss_end = .;
    } > RAM :data

    __bss_size = SIZEOF(.bss);
}
```

---

# 九、先不要急着加入 Stack

先验证最基本布局。

链接：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    data.o \
    -o firmware.elf \
    -Map=firmware.map
```

---

# 十、第一轮验证：Section

执行：

```bash
readelf -SW firmware.elf
```

重点观察：

```text
.text
.rodata
.data
.bss
```

然后：

```bash
objdump -h firmware.elf
```

特别记录：

```text
.data
```

的：

```text
VMA
LMA
Size
```

你应该得到类似：

```text
.data
VMA = 0x0060....
LMA = 0x0040....
```

这说明：

```text
.data
运行地址 → RAM
加载地址 → ROM
```

---

# 十一、第二轮验证：Segment

执行：

```bash
readelf -lW firmware.elf
```

理想结构：

```text
LOAD
    R E
    .text
    .rodata

LOAD
    R W
    .data
    .bss
```

也就是说：

```text
PT_LOAD #1
    RX

PT_LOAD #2
    RW
```

---

# 十二、第三轮验证：Section → Segment

看：

```text
Section to Segment mapping:
```

你应该看到类似：

```text
Segment Sections...
   00
   01     .text .rodata
   02     .data .bss
```

具体编号可能不同。

现在你应该已经能够解释：

```text
.text
    ↓
text PT_LOAD
    ↓
RX

.data
    ↓
data PT_LOAD
    ↓
RW
```

---

# 十三、实验 26-4：检查符号

执行：

```bash
nm -n firmware.elf
```

重点：

```bash
nm -n firmware.elf | grep -E '__data|__bss'
```

应该得到类似：

```text
__data_load_start
__data_start
__data_end
__data_size

__bss_start
__bss_end
__bss_size
```

这几个符号就是以后 startup code 的“接口”。

---

# 十四、把 linker script 当成 API

这一点非常重要。

我们实际上已经定义了一套：

```text
Linker → Startup
```

接口：

```text
__data_load_start
__data_start
__data_end
__data_size

__bss_start
__bss_end
__bss_size
```

启动代码不需要知道：

```text
.data 到底在哪个地址？
```

它只需要：

```text
extern __data_load_start;
extern __data_start;
extern __data_size;
```

这就是 linker script 和 startup assembly 之间的契约。

---

# 十五、实验 26-5：加入 RAM Stack

现在继续。

在 `.bss` 后面加入：

```ld
    . = ALIGN(16);

    __heap_start = .;

    . = ORIGIN(RAM) + LENGTH(RAM);

    __stack_top = .;
```

于是：

```text
RAM
0x00600000
│
├── .data
├── .bss
│
├── heap_start
│
│
│   free RAM
│
│
└── stack_top
    0x00610000
```


执行`nm -n firmware_lab5.elf`

```text
0000000000000020 A __data_size
0000000000000400 A __bss_zize
0000000000400000 T _start
0000000000400000 T _stext
0000000000400005 t .hang
0000000000400008 T main
0000000000400052 T _etext
0000000000400052 R _srodata
0000000000400052 R version
0000000000400058 R _erodata
0000000000400090 A __data_load_start
0000000000600000 D counter
0000000000600000 D __data_start
0000000000600004 D magic
0000000000600010 D message
0000000000600020 B bss_buffer
0000000000600020 B __bss_start
0000000000600020 D __data_end
0000000000600420 B __bss_end
0000000000600420 B __heap_start
0000000000610000 B __stack_top
```

---

# 十六、为什么使用：

```ld
. = ORIGIN(RAM) + LENGTH(RAM);
```

因为：

```ld
ORIGIN(RAM)
```

得到：

```text
RAM 起始地址
```

而：

```ld
LENGTH(RAM)
```

得到：

```text
RAM 大小
```

所以：

```text
ORIGIN(RAM) + LENGTH(RAM)
```

就是：

```text
RAM 结束地址
```

---

# 十七、定义 RAM 边界

建议写：

```ld
PROVIDE(__ram_start = ORIGIN(RAM));
PROVIDE(__ram_end   = ORIGIN(RAM) + LENGTH(RAM));
```

于是：

```text
__ram_start
```

表示：

```text
RAM 起点
```

而：

```text
__ram_end
```

表示：

```text
RAM 末尾
```

然后：

```ld
PROVIDE(__stack_top = __ram_end);
```

---

# 十八、完整 RAM 区域

现在：

```ld
    PROVIDE(__ram_start = ORIGIN(RAM));
    PROVIDE(__ram_end   = ORIGIN(RAM) + LENGTH(RAM));

    . = ALIGN(16);

    PROVIDE(__heap_start = .);
    PROVIDE(__stack_top = __ram_end);
```

形成：

```text
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
│   heap / free RAM
│
│
└── __stack_top
    __ram_end
```

---

# 十九、实验 26-6：为什么 `PROVIDE()` 有时候 `nm` 看不到？

这个问题你之前已经遇到过。

如果：

```ld
PROVIDE(__ram_end = ...);
```

没有被其他对象引用：

```text
__ram_end
```

可能不会成为一个普通意义上可见的最终符号。

这正是：

```text
PROVIDE
```

与：

```ld
__ram_end = ...
```

的重要区别之一。

如果你希望实验中**一定能看到符号**，直接写：

```ld
__ram_end = ORIGIN(RAM) + LENGTH(RAM);
```

更适合观察。

所以这一节为了实验清晰，我们可以暂时写：

```ld
__ram_start = ORIGIN(RAM);
__ram_end = ORIGIN(RAM) + LENGTH(RAM);
__stack_top = __ram_end;
```

而不是 `PROVIDE()`。

---

# 二十、实验 26-7：最终 linker.ld

整理成：

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
    . = SIZEOF_HEADERS;

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
        __data_start = .;

        *(.data)
        *(.data.*)

        __data_end = .;
    } > RAM AT > ROM :data

    __data_load_start = LOADADDR(.data);
    __data_size = SIZEOF(.data);

    .bss :
    {
        __bss_start = .;

        *(.bss)
        *(.bss.*)
        *(COMMON)

        __bss_end = .;
    } > RAM :data

    __bss_size = SIZEOF(.bss);

    . = ALIGN(16);

    __heap_start = .;

    __ram_start = ORIGIN(RAM);
    __ram_end = ORIGIN(RAM) + LENGTH(RAM);
    __stack_top = __ram_end;

    ASSERT(
        __data_end <= __ram_end,
        "ERROR: .data exceeds RAM"
    );

    ASSERT(
        __bss_end <= __ram_end,
        "ERROR: .bss exceeds RAM"
    );

    ASSERT(
        LOADADDR(.data) + SIZEOF(.data)
        <= ORIGIN(ROM) + LENGTH(ROM),
        "ERROR: .data image exceeds ROM"
    );
}
```

---

# 二十一、实验 26-8：验证 RAM Symbols

重新链接：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    data.o \
    -o firmware.elf \
    -Map=firmware.map
```

执行：

```bash
nm -n firmware.elf | grep -E '__ram|__heap|__stack|__data|__bss'
```

你应该得到类似：

```text
0040.... T ...
0040.... __data_load_start

00600000
__data_start

0060....
__data_end

0060....
__bss_start

0060....
__bss_end

0060....
__heap_start

00610000
__ram_end

00610000
__stack_top
```

现在已经能够从 `nm` 完整恢复 RAM 布局。

---

# 二十二、实验 26-9：第一次生成真正的 Binary

这是本节的关键。

执行：

```bash
objcopy \
    -O binary \
    firmware.elf \
    firmware.bin
```

然后：

```bash
ls -lh firmware.elf firmware.bin
```

你会看到：

```text
firmware.elf
```

和：

```text
firmware.bin
```

大小通常明显不同。

原因：

```text
ELF
=
Headers
+
Sections
+
Symbols
+
Relocations/metadata
+
Program Headers
```

而：

```text
binary
=
纯镜像数据
```

---

# 二十三、实验 26-10：观察 Binary

执行：

```bash
xxd firmware.bin | head -n 40
```

或者：

```bash
hexdump -C firmware.bin | head -n 40
```

你会看到真正的：

```text
机器码
+
只读数据
+
初始化数据
```

而不会看到：

```text
ELF Header
```

因为：

```text
-O binary
```

就是把可加载内容提取为原始二进制。

---

# 二十四、第一件非常重要的事情

比较：

```bash
readelf -lW firmware.elf
```

和：

```bash
ls -l firmware.bin
```

不要期待：

```text
firmware.bin
```

一定等于：

```text
所有 Section Size 相加
```

因为 Binary 的大小受到：

```text
LMA
File Offset
Segment
padding
```

影响。

---

# 二十五、实验 26-11：直接看 Binary 中的 `.text`

先：

```bash
objdump -d firmware.elf
```

找到：

```text
_start
```

例如：

```text
00400040 <_start>:
    ...
```

然后：

```bash
objdump -s -j .text firmware.elf
```

得到：

```text
Contents of section .text:
```

再：

```bash
hexdump -C firmware.bin
```

你就可以开始人工对应：

```text
ELF .text
      ↓
Binary 前面的机器码
```

---

# 二十六、实验 26-12：观察 `.data` 的初始化值

`data.c` 中：

```c
int counter = 1234;
```

十六进制：

```text
1234
=
0x000004D2
```

x86-64 小端存储：

```text
D2 04 00 00
```

而：

```c
int magic = 0x12345678;
```

应该看到：

```text
78 56 34 12
```

所以执行：

```bash
objdump -s -j .data firmware.elf
```

应该能够找到：

```text
d2 04 00 00
78 56 34 12
```

具体顺序和 padding 取决于 Section 排列。

---

# 二十七、这一步非常关键

现在你实际上已经验证：

```text
C 源码
   ↓
.data
   ↓
linker
   ↓
LMA
   ↓
PT_LOAD
   ↓
ELF
   ↓
objcopy
   ↓
firmware.bin
   ↓
真实字节
```

这才是真正的：

# Linker → Firmware Image

闭环。

---

# 二十八、实验 26-13：为什么 `.bss` 不出现在 Binary？

执行：

```bash
objdump -h firmware.elf
```

找到：

```text
.bss
```

再：

```bash
readelf -SW firmware.elf
```

看：

```text
NOBITS
```

然后：

```bash
ls -l firmware.bin
```

你会发现：

```text
.bss
```

虽然可能有：

```text
1024 bytes
```

甚至：

```text
4096 bytes
```

但它不会让 Binary 简单地增加相同数量的真实数据。

原因：

```text
.bss
=
运行时空间

不是：

ROM 初始化数据
```

启动程序需要做：

```text
memset(
    __bss_start,
    0,
    __bss_size
);
```

而不是从 Flash 读取一大片 0。

---

# 二十九、实验 26-14：真正完成 `.data` Copy

现在开始修改 `start.S`。

```asm
.global _start

.extern main

.extern __data_load_start
.extern __data_start
.extern __data_end

.text

_start:

    lea __data_load_start(%rip), %rsi
    lea __data_start(%rip), %rdi
    lea __data_end(%rip), %rcx

    sub %rdi, %rcx

    test %rcx, %rcx
    je .data_done

.data_copy:
    movb (%rsi), %al
    movb %al, (%rdi)

    inc %rsi
    inc %rdi
    dec %rcx

    jne .data_copy

.data_done:

    call main

.hang:
    hlt
    jmp .hang
```

---

# 三十、这里真正发生了什么？

```text
__data_load_start
        │
        │ ROM
        ▼
┌─────────────────┐
│ 1234             │
│ 0x12345678       │
│ "GNU ld firmware"│
└─────────────────┘
        │
        │ copy
        ▼
__data_start
        │
        ▼
RAM .data
```

这就是：

```text
LMA → VMA
```

的真实使用。

---

# 三十一、实验 26-15：实现 `.bss` Clear

增加：

```asm
.extern __bss_start
.extern __bss_end
```

然后：

```asm
    lea __bss_start(%rip), %rdi
    lea __bss_end(%rip), %rcx

    sub %rdi, %rcx

    xor %rax, %rax

    test %rcx, %rcx
    je .bss_done

.bss_clear:
    movb %al, (%rdi)

    inc %rdi
    dec %rcx

    jne .bss_clear

.bss_done:
```

完整启动流程：

```text
_start
   │
   ├── copy .data
   │
   ├── clear .bss
   │
   └── call main
```

---

# 三十二、现在 linker 和 startup 已经真正配合起来了

Linker 提供：

```text
__data_load_start
__data_start
__data_end

__bss_start
__bss_end
```

Startup 使用：

```text
ROM
 ↓
__data_load_start

RAM
 ↓
__data_start
```

以及：

```text
__bss_start
 ↓
zero
 ↓
__bss_end
```

这就是现代 C 程序启动过程最核心的两步。

---

# 三十三、实验 26-16：加入 `__image_end`

现在我们希望知道：

> ROM 镜像到底在哪里结束？

在 `.data` 后面增加：

```ld
__image_end = LOADADDR(.data) + SIZEOF(.data);
```

于是：

```text
ROM

.text
.rodata
.data image
        │
        ▼
    __image_end
```

注意：

```text
__image_end
```

这里是：

```text
LMA
```

语义。

不要把它误认为：

```text
.data VMA end
```

---

# 三十四、再定义：

```ld
__image_start = LOADADDR(.text);
```

这样：

```text
__image_start
```

和：

```text
__image_end
```

就形成：

```text
ROM image

[ __image_start
        ...
  __image_end )
```

---

# 三十五、实验 26-17：用 ASSERT 验证整个 Firmware 镜像

增加：

```ld
ASSERT(
    __image_end <= ORIGIN(ROM) + LENGTH(ROM),
    "ERROR: firmware image exceeds ROM"
);
```

这样：

```text
ROM
0x00400000
│
├── firmware image
│
├── __image_end
│
└── ROM end
    0x00410000
```

如果：

```text
__image_end > 0x00410000
```

链接直接失败。

这比：

```text
烧录以后才发现 Flash 爆了
```

强得多。

---

# 三十六、实验 26-18：给 Firmware 增加 Magic

现在开始做非常实用的事情。

在 `data.c` 中增加：

```c
__attribute__((section(".firmware_header")))
const unsigned int firmware_magic = 0x46574D47;

__attribute__((section(".firmware_header")))
const unsigned int firmware_version = 0x00010000;
```

其中：

```text
0x46574D47
```

可以理解成：

```text
"FWMG"
```

的 ASCII 编码形式。

---

# 三十七、为什么自己定义 Section？

因为：

```c
__attribute__((section(".firmware_header")))
```

会制造：

```text
Input Section:
.firmware_header
```

然后 linker 可以：

```ld
.firmware_header :
{
    KEEP(*(.firmware_header))
} > ROM :text
```

这就是：

# 自定义 Firmware Metadata

---

# 三十八、实验 26-19：linker 中加入 Header

在 `.text` 后面：

```ld
.firmware_header :
{
    __firmware_header_start = .;

    KEEP(*(.firmware_header))

    __firmware_header_end = .;
} > ROM :text
```

这里第一次使用：

```ld
KEEP()
```

它的意义是：

> 即使链接使用了 `--gc-sections`，也不要把这个 Section 当成无引用数据丢掉。

---

# 三十九、为什么这里需要 `KEEP()`？

假设：

```bash
ld \
    --gc-sections \
    ...
```

如果：

```text
firmware_magic
```

没有任何 C 代码引用。

linker 可能认为：

```text
没人用
```

然后：

```text
删除
```

但是 Firmware Header 恰恰是：

```text
Bootloader
```

主动寻找的。

所以：

```ld
KEEP(*(.firmware_header))
```

非常重要。

---

# 四十、实验 26-20：重新链接并检查

```bash
ld \
    --gc-sections \
    -T linker.ld \
    start.o \
    main.o \
    data.o \
    -o firmware.elf \
    -Map=firmware.map
```

然后：

```bash
readelf -SW firmware.elf
```

找到：

```text
.firmware_header
```

然后：

```bash
objdump -s -j .firmware_header firmware.elf
```

应该能够看到：

```text
47 4D 57 46 ...
```

或者对应的小端排列。

---

# 四十一、Map 文件现在更有价值了

执行：

```bash
grep -A20 -B5 "\.firmware_header" firmware.map
```

你应该能够看到：

```text
.firmware_header
    ...
    data.o
```

并且可以确定：

```text
firmware header
```

在：

```text
.text
.rodata
```

附近。

---

# 四十二、实验 26-21：完整 ROM 镜像布局

现在可以设计成：

```text
ROM
0x00400000
│
├── ELF/LOAD RX
│
├── .text
│
├── .rodata
│
├── .firmware_header
│
├── .data initial image
│
└── __image_end
```

RAM：

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
│
└── __stack_top
```

---

# 四十三、现在有一个非常重要的问题

你可能会发现：

```text
.data LMA
```

并不一定紧紧位于：

```text
.firmware_header
```

后面。

为什么？

因为：

```text
Section VMA
```

和：

```text
Section LMA
```

是两个地址空间。

这时候必须继续观察：

```bash
objdump -h firmware.elf
```

以及：

```bash
readelf -lW firmware.elf
```

不能只看 linker script 的文本顺序。

---

# 四十四、实验 26-22：把 ROM LMA 显式组织起来

这一阶段开始学习一种非常重要的技巧：

```text
LOADADDR()
```

不是只能“查询”。

我们还可以围绕：

```text
ROM current location
```

设计镜像。

例如定义：

```ld
.rom_data :
{
    ...
} > ROM
```

然后：

```ld
.data :
{
    ...
} > RAM AT(ADDR(.rom_data) + SIZEOF(.rom_data))
```

不过这一阶段先不要急着把所有地址公式复杂化。

推荐保持：

```ld
.data > RAM AT > ROM
```

然后使用：

```ld
LOADADDR(.data)
```

让 linker 计算。

这是最稳妥的工程方式。

---

# 四十五、实验 26-23：生成 Binary

最终：

```bash
objcopy \
    -O binary \
    firmware.elf \
    firmware.bin
```

再：

```bash
objdump -s firmware.elf
```

和：

```bash
hexdump -C firmware.bin
```

进行对照。

---

# 四十六、`objcopy -O binary` 到底做了什么？

可以粗略理解为：

```text
ELF
│
├── ELF Header
├── Program Headers
├── Section Headers
├── .text
├── .rodata
├── .data
├── .bss
└── ...
        │
        │ objcopy -O binary
        ▼
┌──────────────────────────────┐
│ 可加载的实际内容              │
└──────────────────────────────┘
```

所以：

```text
firmware.bin
```

不再是：

```text
ELF
```

而是：

```text
原始镜像
```

---

# 四十七、实验 26-24：Binary 与 ELF 的一个坑

如果：

```text
.data
```

的 LMA：

```text
0x00401000
```

而：

```text
.text
```

结束：

```text
0x00400080
```

那么：

```text
firmware.bin
```

中间可能出现：

```text
0xF80
```

左右的 padding。

所以：

```text
Binary size
```

取决于：

```text
最高 LMA
-
最低 LMA
```

附近的布局。

因此：

> **Binary 很大，不代表有效数据很多。**

可能是：

```text
LMA gap
+
alignment
+
padding
```

导致。

---

# 四十八、实验 26-25：用 `objcopy --gap-fill`

现在做一个小实验：

```bash
objcopy \
    -O binary \
    --gap-fill 0xFF \
    firmware.elf \
    firmware-ff.bin
```

然后：

```bash
hexdump -C firmware-ff.bin
```

与：

```bash
hexdump -C firmware.bin
```

比较。

这在 Flash 镜像实验里非常有意义。

因为很多 Flash 擦除状态通常表现为：

```text
0xFF
```

于是：

```text
padding
```

可以明确填成：

```text
0xFF
```

---

# 四十九、实验 26-26：比较两种 Binary

执行：

```bash
ls -l firmware.bin firmware-ff.bin
```

然后：

```bash
cmp firmware.bin firmware-ff.bin
```

如果镜像中存在 gap：

```text
```

可以看到差异。

这时候你应该能够回答：

> 哪些字节是真正来自 ELF Section，哪些只是镜像 gap？

---

# 五十、实验 26-27：用 `objcopy --only-section`

我们还可以只导出：

```text
.text
```

例如：

```bash
objcopy \
    -O binary \
    --only-section=.text \
    firmware.elf \
    text.bin
```

然后：

```bash
ls -l text.bin
```

再：

```bash
objdump -s -j .text firmware.elf
```

比较两者。

这样可以明确验证：

```text
.text Size
=
text.bin 大小
```

在没有额外 padding 的情况下。

---

# 五十一、导出 `.data`

同样：

```bash
objcopy \
    -O binary \
    --only-section=.data \
    firmware.elf \
    data.bin
```

然后：

```bash
ls -l data.bin
```

再：

```bash
objdump -s -j .data firmware.elf
```

这样你可以直接看到：

```text
.data
```

真正需要复制到 RAM 的初始化数据。

---

# 五十二、实验 26-28：`.bss` 为什么不能直接这样导出？

执行：

```bash
objcopy \
    -O binary \
    --only-section=.bss \
    firmware.elf \
    bss.bin
```

你会发现它并不是：

```text
1024 个 0
```

这样的典型 Flash 数据。

因为：

```text
.bss
```

本质是：

```text
NOBITS
```

它代表：

```text
RAM reservation
```

而不是：

```text
ROM bytes
```

这就是：

# `.bss` 的核心价值。

---

# 五十三、实验 26-29：制作 Firmware Memory Report

现在我们可以手工建立一份：

```text
firmware-memory.txt
```

内容：

```text
=== ROM ===

.text:
    VMA = ...
    LMA = ...
    SIZE = ...

.rodata:
    VMA = ...
    LMA = ...
    SIZE = ...

.firmware_header:
    VMA = ...
    LMA = ...
    SIZE = ...

.data image:
    LMA = ...
    SIZE = ...

ROM used:
    ...

ROM free:
    ...


=== RAM ===

.data:
    VMA = ...
    SIZE = ...

.bss:
    VMA = ...
    SIZE = ...

heap:
    ...

stack:
    ...

RAM used:
    ...

RAM free:
    ...
```

这实际上就是很多真实 Firmware 工程中的：

# Memory Map Report

---

# 五十四、用 Map 文件计算 ROM 使用量

例如：

```text
ROM origin:
0x00400000

ROM end:
0x00410000

__image_end:
0x00400320
```

那么：

```text
ROM used
=
0x00400320
-
0x00400000
=
0x320
```

ROM 剩余：

```text
0x10000 - 0x320
=
0xFCE0
```

---

# 五十五、RAM 同样计算

例如：

```text
RAM origin:
0x00600000

__bss_end:
0x00601000
```

那么：

```text
RAM static used
=
0x1000
```

如果：

```text
__stack_top
=
0x00610000
```

那么：

```text
free RAM
=
0x00610000
-
__heap_start
```

---

# 五十六、实验 26-30：加入最终 ASSERT

可以进一步增加：

```ld
ASSERT(
    __heap_start < __stack_top,
    "ERROR: RAM exhausted"
);
```

这样：

```text
.data
+
.bss
```

如果已经占满 RAM：

```text
__heap_start >= __stack_top
```

链接直接失败。

---

# 五十七、再加入 ROM 检查

```ld
ASSERT(
    __image_end <= __rom_end,
    "ERROR: ROM overflow"
);
```

先定义：

```ld
__rom_start = ORIGIN(ROM);
__rom_end = ORIGIN(ROM) + LENGTH(ROM);
```

于是：

```text
ROM
│
├── image
│
├── __image_end
│
└── __rom_end
```

---

# 五十八、实验 26-31：完整 Memory Symbols

现在建议统一定义：

```ld
__rom_start = ORIGIN(ROM);
__rom_end = ORIGIN(ROM) + LENGTH(ROM);

__ram_start = ORIGIN(RAM);
__ram_end = ORIGIN(RAM) + LENGTH(RAM);
```

然后：

```ld
__image_start = LOADADDR(.text);
__image_end = LOADADDR(.data) + SIZEOF(.data);

__heap_start = ALIGN(__bss_end, 16);
__stack_top = __ram_end;
```

形成：

```text
ROM symbols:

__rom_start
__image_start
__image_end
__rom_end


RAM symbols:

__ram_start
__data_start
__data_end
__bss_start
__bss_end
__heap_start
__stack_top
__ram_end
```

这已经非常接近真实 MCU linker script 的 Symbol API。

---

# 五十九、实验 26-32：最终 linker.ld

整理成：

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
    __rom_start = ORIGIN(ROM);
    __rom_end   = ORIGIN(ROM) + LENGTH(ROM);

    __ram_start = ORIGIN(RAM);
    __ram_end   = ORIGIN(RAM) + LENGTH(RAM);

    . = SIZEOF_HEADERS;

    .text :
    {
        __image_start = .;

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

    .firmware_header :
    {
        __firmware_header_start = .;

        KEEP(*(.firmware_header))

        __firmware_header_end = .;
    } > ROM :text

    .data :
    {
        __data_start = .;

        *(.data)
        *(.data.*)

        __data_end = .;
    } > RAM AT > ROM :data

    __data_load_start = LOADADDR(.data);
    __data_size = SIZEOF(.data);

    .bss :
    {
        __bss_start = .;

        *(.bss)
        *(.bss.*)
        *(COMMON)

        __bss_end = .;
    } > RAM :data

    __bss_size = SIZEOF(.bss);

    __image_end =
        LOADADDR(.data) + SIZEOF(.data);

    . = ALIGN(16);

    __heap_start = .;
    __stack_top = __ram_end;

    ASSERT(
        __data_end <= __ram_end,
        "ERROR: .data exceeds RAM"
    );

    ASSERT(
        __bss_end <= __ram_end,
        "ERROR: .bss exceeds RAM"
    );

    ASSERT(
        __heap_start < __stack_top,
        "ERROR: RAM exhausted"
    );

    ASSERT(
        __image_end <= __rom_end,
        "ERROR: firmware image exceeds ROM"
    );
}
```

---

# 六十、注意一个非常重要的工程问题

这里的：

```ld
__image_end =
    LOADADDR(.data) + SIZEOF(.data);
```

假定：

```text
.data
```

是 ROM 中最后需要加载的数据。

如果以后再增加：

```text
.calibration
.config
.factory_data
.crc
.signature
```

等 Section，就不能继续这么简单定义：

```text
__image_end = data end
```

而应该让：

```text
最后一个 ROM LMA Section
```

决定：

```text
__image_end
```

这就是为什么后面我们还需要学习：

```text
SORT
KEEP
FILL
AT
LOADADDR
CREATE_OBJECT_SYMBOLS
```

以及最终的：

```text
固件 CRC / 签名 Section
```

---

# 六十一、实验 26-33：最终验证命令集

现在这一节不要只跑一个命令。

完整执行：

```bash
readelf -h firmware.elf
```

确认：

```text
Entry point
Program Header
```

---

```bash
readelf -SW firmware.elf
```

确认：

```text
.text
.rodata
.firmware_header
.data
.bss
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
Align
```

---

```bash
readelf -lW firmware.elf
```

确认：

```text
PT_LOAD RX
PT_LOAD RW
```

---

```bash
objdump -p firmware.elf
```

再次确认 Segment。

---

```bash
nm -n firmware.elf
```

确认：

```text
__image_start
__image_end

__data_load_start
__data_start
__data_end

__bss_start
__bss_end

__heap_start
__stack_top

__rom_start
__rom_end
__ram_start
__ram_end
```

---

# 六十二、生成 Binary

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

---

# 六十三、查看 Binary

```bash
ls -lh firmware.elf firmware.bin firmware-ff.bin
```

```bash
hexdump -C firmware.bin | head -n 64
```

```bash
objdump -s firmware.elf
```

进行交叉验证。

---

# 六十四、Map 文件最终分析

执行：

```bash
less firmware.map
```

重点搜索：

```text
.text
.rodata
.firmware_header
.data
.bss
```

然后再搜索：

```text
__data_load_start
__data_start
__data_end
__bss_start
__bss_end
__heap_start
__stack_top
__image_end
```

最终应该能建立：

```text
                 MAP
                  │
       ┌──────────┼──────────┐
       ▼          ▼          ▼
    Section     Symbol     Segment
       │          │          │
       ▼          ▼          ▼
      VMA        API       PT_LOAD
       │          │          │
       └──────────┼──────────┘
                  ▼
              firmware.bin
```

---

# 六十五、本节最重要的一次认知升级

到实验 25，你已经知道：

```text
Section → Segment
```

现在实验 26 再增加：

```text
Segment → Binary
```

于是完整链路变成：

```text
C / ASM
   │
   ▼
Input Sections
   │
   ▼
Output Sections
   │
   ▼
VMA / LMA
   │
   ▼
Program Headers
   │
   ▼
PT_LOAD
   │
   ▼
ELF
   │
   ▼
objcopy
   │
   ▼
firmware.bin
   │
   ▼
Flash / ROM
```

而启动时：

```text
ROM
 │
 ├── .text
 ├── .rodata
 └── .data image
          │
          │ copy
          ▼
RAM
 │
 ├── .data
 └── .bss
       │
       │ zero
       ▼
     main()
```

这就是一个完整的：

# ROM → RAM Firmware Boot Model

---

# 六十六、实验 26 最值得记住的 10 个东西

```text
1. MEMORY
```

决定：

```text
ROM / RAM
```

---

```text
2. > RAM
```

决定：

```text
VMA
```

---

```text
3. AT > ROM
```

决定：

```text
LMA
```

---

```text
4. PHDRS
```

决定：

```text
Program Header
```

---

```text
5. :text / :data
```

决定：

```text
Section → Segment
```

---

```text
6. LOADADDR(.data)
```

得到：

```text
ROM source
```

---

```text
7. ADDR(.data)
```

得到：

```text
RAM destination
```

---

```text
8. SIZEOF(.data)
```

得到：

```text
copy length
```

---

```text
9. NOBITS .bss
```

意味着：

```text
RAM allocation
但不需要 ROM bytes
```

---

```text
10. objcopy -O binary
```

完成：

```text
ELF → Raw Firmware Image
```

---

# 六十七、下一阶段：实验 27

下一节继续进入一个非常实用、也非常容易踩坑的领域：

# 实验 27：`FILL()` + `.` + `ALIGN()` + `AT()`——控制 Firmware 镜像中的 Padding

我们会故意构造：

```text
ROM

.text
───────
padding
───────
.rodata
───────
padding
───────
.data image
───────
CRC
───────
END
```

然后分别实验：

```ld
FILL(0xFF)
```

```ld
. = ALIGN(16)
```

```ld
. = ALIGN(256)
```

以及：

```ld
AT(...)
```

最终做出：

```text
firmware.bin
```

并用：

```bash
hexdump -C
objdump -s
readelf -S
readelf -lW
```

逐字节验证：

> **为什么 linker script 中的一行 `.` 或 `ALIGN()`，最后会真的变成 Firmware Binary 中的一大片 `00` / `FF`。**

然后再进一步做：

```text
Firmware Header
+
Version
+
Image Size
+
CRC32
+
Payload
```

的完整镜像布局。

到那一步，GNU `ld` 就会从“理解 ELF”正式进入：

# Bootloader / Firmware Image Engineering

阶段。

