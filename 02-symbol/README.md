# GNU ld 实战课程 · 实验 02

# 第一次真正控制程序地址：`linker.ld`

上一实验我们使用：

```text
start.o + main.o
        │
        ▼
       ld
        │
        ▼
      hello
```

但是我们没有告诉 `ld`：

> `.text` 应该放在哪里？

于是 `ld` 使用了默认 linker script。

这一节开始，我们自己接管这个权力。

---

# 🎯 本实验目标

你将亲手完成：

```text
main.c
start.S
linker.ld
     │
     ▼
 GNU ld
     │
     ▼
 custom.elf
```

并理解：

1. `SECTIONS` 是什么
2. `.`（Location Counter）是什么
3. Input Section 如何进入 Output Section
4. Linker Script 如何决定地址
5. `ENTRY(_start)` 如何决定 ELF Entry Point
6. 如何用 `readelf`、`objdump`、`nm`、`map` 验证

---

# 一、实验目录

```text
02-custom-linker-script
│
├── main.c
├── start.S
└── linker.ld
```

---

# 二、main.c

我们继续使用最简单的程序：

```c
int global_data = 123;

int global_bss;

int main(void)
{
    global_bss = global_data;

    return global_bss;
}
```

这一次故意加入：

```c
int global_data = 123;
```

它通常进入：

```text
.data
```

而：

```c
int global_bss;
```

通常进入：

```text
.bss
```

所以现在我们可以观察：

```text
.text
.data
.bss
```

三个最经典的 Section。

---

# 三、start.S

继续使用上一节的最小启动代码：

```asm
.global _start

_start:

    call main

    mov %eax, %edi

    mov $60, %eax

    syscall
```

逻辑：

```text
ELF Entry Point
        │
        ▼
      _start
        │
        ▼
       main
        │
        ▼
 return value
        │
        ▼
 Linux syscall exit
```

---

# 四、第一个 linker.ld

创建：

```text
linker.ld
```

内容：

```ld
ENTRY(_start)

SECTIONS
{
    . = 0x100000;

    .text :
    {
        *(.text)
    }

    .data :
    {
        *(.data)
    }

    .bss :
    {
        *(.bss)
    }
}
```

这就是一个最小 linker script。

---

# 五、先理解整体结构

```text
Linker Script
│
├── ENTRY(_start)
│
└── SECTIONS
      │
      ├── .
      │
      ├── .text
      │
      ├── .data
      │
      └── .bss
```

---

# 六、`ENTRY(_start)`

```ld
ENTRY(_start)
```

告诉 `ld`：

```text
ELF Entry Point
       │
       ▼
     _start
```

注意：

```text
ENTRY(_start)
```

不是：

> 把 `_start` 放在某个地址。

而是：

> ELF Header 的 Entry Point 指向 `_start`。

---

# 七、最重要的符号：`.`

现在看：

```ld
. = 0x100000;
```

`.` 是：

# ⭐ Location Counter

也就是：

> 当前链接地址。

脑图：

```text
.
│
▼
Current Address
```

执行：

```ld
. = 0x100000;
```

相当于：

```text
当前地址

0x100000
```

---

# 八、`.text` 从哪里开始？

接下来：

```ld
.text :
{
    *(.text)
}
```

因为之前：

```ld
. = 0x100000;
```

所以：

```text
.text

开始地址：

0x100000
```

模型：

```text
Location Counter

0x100000
    │
    ▼
.text
```

---

# 九、`*(.text)` 到底做了什么？

这是 GNU ld 最重要的语法之一。

```ld
*(.text)
```

拆开：

```text
*
│
├── start.o
├── main.o
└── 所有输入文件
```

然后：

```text
(.text)
│
▼
每个文件中的 .text
```

所以：

```text
start.o(.text)
        │
        ▼
main.o(.text)
        │
        ▼
最终 .text
```

更准确：

```text
Input Sections

start.o
└── .text

main.o
└── .text

        │
        ▼

Output Section

.text
```

---

# 十、编译程序

先编译：

```bash
gcc -c main.c -o main.o
```

然后：

```bash
gcc -c start.S -o start.o
```

检查：

```bash
nm start.o
```

应该看到：

```text
T _start
U main
```

然后：

```bash
nm main.o
```

应该看到类似：

```text
T main
D global_data
B global_bss
```

这三个字母非常重要：

```text
T = Text

D = Data

B = BSS
```

脑图：

```text
Symbol
│
├── T
│   └── .text
│
├── D
│   └── .data
│
└── B
    └── .bss
```

---

# 十一、开始真正使用 linker script

执行：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    -o custom.elf \
    -Map=custom.map
```

其中：

```text
-T linker.ld
```

意思：

```text
使用指定的 Linker Script
```

---

# 十二、查看 ELF Entry Point

执行：

```bash
readelf -h custom.elf
```

重点：

```text
Entry point address:
```

应该接近：

```text
0x100000
```

为什么？

因为：

```text
_start
```

是 `.text` 的第一个函数。

而：

```text
.text
```

开始地址是：

```text
0x100000
```

所以：

```text
ELF Entry Point

0x100000
```

---

# 十三、用 nm 验证

执行：

```bash
nm -n custom.elf
```

`-n` 表示：

```text
按照地址排序
```

你可能看到：

```text
0000000000100000 T _start
0000000000100011 T main
0000000000102000 D global_data
0000000000102004 B global_bss
```

实际地址可能略有不同，但关系类似。

脑图：

```text
0x100000
│
├── _start
│
├── main
│
├── .data
│
└── .bss
```

---

# 十四、objdump 验证机器代码地址

执行：

```bash
objdump -d custom.elf
```

你应该看到：

```text
0000000000100000 <_start>:
```

然后：

```text
100000: call ...
```

这说明：

```text
Linker Script
      │
      ▼
. = 0x100000
      │
      ▼
.text
      │
      ▼
_start
      │
      ▼
0x100000
```

成功。

---

# 十五、查看 Section 地址

执行：

```bash
readelf -S custom.elf
```

你会看到：

```text
[Nr] Name

.text
.data
.bss
```

重点看：

```text
Address
```

模型：

```text
.text

0x100000
```

然后：

```text
.data

紧跟 .text
```

然后：

```text
.bss

紧跟 .data
```

---

# 十六、Location Counter 会自动增长

你的 linker script：

```ld
. = 0x100000;

.text :
{
    *(.text)
}

.data :
{
    *(.data)
}

.bss :
{
    *(.bss)
}
```

实际上发生：

```text
. = 0x100000

        │
        ▼

.text
        │
        │ size = 0x123
        ▼

. = 0x100123

        │
        ▼

.data
        │
        │ size = 4
        ▼

. = 0x100127

        │
        ▼

.bss
```

这就是：

# ⭐ Location Counter 自动向前移动。

---

# 十七、自己插入一个“地址洞”

现在修改：

```ld
ENTRY(_start)

SECTIONS
{
    . = 0x100000;

    .text :
    {
        *(.text)
    }

    . = 0x200000;

    .data :
    {
        *(.data)
    }

    .bss :
    {
        *(.bss)
    }
}
```

注意：

```ld
. = 0x200000;
```

意味着：

```text
.text

0x100000
   │
   │
   │
   ▼

.data

0x200000
```

中间出现巨大空洞。

重新：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    -o custom.elf \
    -Map=custom.map
```

---

# 十八、验证地址变化

执行：

```bash
readelf -S custom.elf
```

你会看到：

```text
.text

0x100000
```

而：

```text
.data

0x200000
```

模型：

```text
Memory

0x100000
│
├── .text
│
│
│
│
│
│
0x200000
│
├── .data
│
└── .bss
```

---

# 十九、查看 Map File

打开：

```bash
less custom.map
```

重点找：

```text
.text
```

你可能看到：

```text
.text           0x0000000000100000
                start.o
                main.o
```

然后：

```text
.data           0x0000000000200000
```

这就是 Linker Script 的“证据”。

---

# 二十、Map 文件阅读方法

以后看到 Map File，不要从头乱看。

按这个顺序：

```text
① Memory Configuration

        ↓

② Linker script and memory map

        ↓

③ .text

        ↓

④ .data

        ↓

⑤ .bss

        ↓

⑥ Symbols
```

---

# 二十一、增加链接器符号

现在升级 linker script：

```ld
ENTRY(_start)

SECTIONS
{
    . = 0x100000;

    text_start = .;

    .text :
    {
        *(.text)
    }

    text_end = .;

    . = 0x200000;

    data_start = .;

    .data :
    {
        *(.data)
    }

    data_end = .;

    bss_start = .;

    .bss :
    {
        *(.bss)
    }

    bss_end = .;
}
```

这里：

```ld
text_start = .;
```

不是 C 变量。

它是：

# ⭐ Linker Symbol

---

# 二十二、查看 Linker Symbol

执行：

```bash
nm -n custom.elf
```

你应该看到：

```text
0000000000100000 T text_start
0000000000100000 T _start
...
000000000010xxxx T text_end

0000000000200000 D data_start
...
0000000000200004 D data_end
```

现在你已经能够：

# ⭐ 用 ld 创建自己的地址符号。

这在 Bootloader / OS / Embedded 中极其重要。

---

# 二十三、在 C 中使用 Linker Symbol

修改：

```c
extern char text_start[];
extern char text_end[];

extern char data_start[];
extern char data_end[];
```

然后：

```c
unsigned long text_size =
    text_end - text_start;
```

模型：

```text
Linker Script

text_start
    │
    ▼
.text
    │
    ▼
text_end
```

C：

```text
text_end - text_start

=

.text 大小
```

---

# ⚠️ 一个非常重要的概念

这些：

```c
extern char text_start[];
```

不是说：

> 内存中真的存在一个 char 数组。

而是：

```text
text_start

只是一个地址符号。
```

你真正想使用的是：

```c
&text_start
```

或者：

```c
text_start
```

因为数组名本身会转换成地址。

---

# 二十四、本实验最重要的模型

```text
Linker Script
        │
        ▼
SECTIONS
        │
        ▼
Location Counter
        │
        ▼
Output Section
        │
        ▼
Input Section
```

完整：

```text
. = 0x100000
        │
        ▼
.text
        │
        ├── start.o(.text)
        │
        └── main.o(.text)
        │
        ▼
Location Counter 自动增长
        │
        ▼
. = 0x200000
        │
        ▼
.data
        │
        └── main.o(.data)
        │
        ▼
.bss
        │
        └── main.o(.bss)
```

---

# 二十五、实验结果总表

| 内容          | 工具           | 你应该验证什么                  |
| ----------- | ------------ | ------------------------ |
| ELF 类型      | `readelf -h` | `EXEC`                   |
| Entry Point | `readelf -h` | `_start` 地址              |
| Section     | `readelf -S` | `.text/.data/.bss` 地址    |
| Symbol      | `nm -n`      | `_start/main/data_start` |
| 汇编          | `objdump -d` | `_start` 的真实地址           |
| Map         | `custom.map` | 输入 Section 如何组合          |

---

# 🧠 实验 02 最终脑图

```text
GNU ld
│
├── Linker Script
│
│   ├── ENTRY(_start)
│   │
│   └── SECTIONS
│
├── Location Counter
│
│   .
│   │
│   ├── . = 0x100000
│   │
│   └── . = 0x200000
│
├── Output Sections
│
│   ├── .text
│   │
│   ├── .data
│   │
│   └── .bss
│
├── Input Sections
│
│   ├── start.o(.text)
│   │
│   └── main.o(.text)
│
└── Linker Symbols
    │
    ├── text_start
    ├── text_end
    ├── data_start
    ├── data_end
    ├── bss_start
    └── bss_end
```

---

# 🚀 实验 03 预告

下一节我们进入 GNU ld 最关键的概念之一：

# **VMA vs LMA：为什么 `.data` 要在 ROM 中保存，却在 RAM 中运行？**

我们将构建：

```text
03-rom-ram
│
├── main.c
├── start.S
└── linker.ld
```

最终实现：

```text
FLASH / ROM

.text
.rodata
.data 初始值
        │
        │ Copy
        ▼
RAM

.data
.bss
```

并彻底讲清楚：

```text
VMA

LMA

AT>

LOADADDR()

ADDR()

SIZEOF()
```

以及你之前研究过的那个经典问题：

> **为什么启动代码要把 `.data` 从 ROM 拷贝到 RAM？**

这一节之后，GNU `ld` 就会从“会写几个 `SECTIONS`”升级到真正理解**裸机程序内存布局**。




## 问题补充


```
实验02 ：  
ld 
     -T linker.ld 
     start.o 
     main.o 
     -o custom.elf 
     -Map=custom.map 


ld: warning: start.o: missing .note.GNU-stack section implies executable stack 
ld: NOTE: This behaviour is deprecated and will be removed in a future version of the linker 
ld: warning: custom.elf has a LOAD segment with RWX permissions
```

这个现象非常好，**实验 02 正好碰到了 GNU `ld` 实际使用中两个非常重要的问题**。

你的链接其实已经成功了：

```text
custom.elf
custom.map
```

只是 `ld` 给出了两个 warning。我们逐个解决，而且这两个 warning 背后分别对应：

1. **`.note.GNU-stack`：汇编文件的栈权限标记**
2. **RWX LOAD segment：ELF Segment 的权限布局**

这恰好可以把我们下一阶段的 `Section → Segment` 知识提前引出来。

---

# 1. 第一个 warning

你看到：

```text
ld: warning: start.o: missing .note.GNU-stack section implies executable stack
ld: NOTE: This behaviour is deprecated and will be removed in a future version of the linker
```

关键是：

```text
missing .note.GNU-stack
```

意思是：

> `start.S` 没有告诉 linker：“这个目标文件不需要可执行栈”。

---

# 2. 为什么一个 `.S` 文件会影响栈？

你现在的 `start.S`：

```asm
.global _start

_start:

    call main

    mov %eax, %edi

    mov $60, %eax

    syscall
```

代码本身没有问题。

但是 GNU assembler 还允许我们给 object file 添加一个特殊 Section：

```text
.note.GNU-stack
```

它不是实际运行时的栈。

名字很容易误导。

它实际上是一个：

> **“这个目标文件是否要求可执行栈”的标记。**

---

# 3. 给 start.S 加上 `.note.GNU-stack`

修改成：

```asm
.global _start

_start:

    call main

    mov %eax, %edi

    mov $60, %eax

    syscall


.section .note.GNU-stack,"",@progbits
```

最后这一行：

```asm
.section .note.GNU-stack,"",@progbits
```

非常关键。

可以拆成：

```text
.section
    │
    ▼
创建 Section

.note.GNU-stack
    │
    ▼
GNU Stack 标记

""
    │
    ▼
没有 SHF_EXECINSTR 权限

@progbits
    │
    ▼
普通 ELF section 类型
```

---

# 4. 重新编译

```bash
gcc -c start.S -o start.o
```

然后：

```bash
readelf -S start.o
```

应该能够看到：

```text
.note.GNU-stack
```

更重要的是，它应该**没有 executable flag**。

可以用：

```bash
readelf -SW start.o
```

观察 Flags。

---

# 5. 为什么 `ld` 原来认为 Stack 可以执行？

因为：

```text
start.o
    │
    ├── .text
    │
    └── 没有 .note.GNU-stack
             │
             ▼
       linker 无法确认
             │
             ▼
     按 executable stack 处理
```

因此：

```text
没有 .note.GNU-stack
        ↓
可能需要 executable stack
```

而现在：

```text
.note.GNU-stack
        ↓
明确声明不需要执行栈
        ↓
NX / non-executable stack
```

---

# 6. 第二个 warning

现在来看更有意思的：

```text
ld: warning: custom.elf has a LOAD segment with RWX permissions
```

这里最重要的是：

# `LOAD segment`

注意：

我们前面一直学习的是：

```text
Section
```

但是这里突然出现：

```text
Segment
```

这正是 ELF 中非常重要的：

# Section ≠ Segment

---

# 7. 先看你的 ELF

执行：

```bash
readelf -l custom.elf
```

你应该能看到类似：

```text
Elf file type is EXEC (Executable file)
Entry point 0x100000

Program Headers:

  Type           Offset   VirtAddr
                 PhysAddr FileSiz MemSiz
                 Flags Align

  LOAD           ...
                 R E
                 
  LOAD           ...
                 RWX
```

具体地址可能与你这里不同。

重点看：

```text
Type
Flags
```

---

# 8. Section 和 Segment 的关系

先建立这个模型：

```text
ELF
│
├── Sections
│
│   ├── .text
│   ├── .rodata
│   ├── .data
│   ├── .bss
│   └── ...
│
└── Segments
    │
    ├── LOAD
    ├── LOAD
    ├── INTERP
    ├── DYNAMIC
    └── ...
```

---

# 9. 谁使用 Section？谁使用 Segment？

这是理解 ELF 的关键：

```text
Section
   │
   ▼
Linker / Compiler / Debugger
```

而：

```text
Segment
   │
   ▼
OS Loader
```

所以：

```text
Section
   ↓
描述“程序由什么组成”
```

而：

```text
Segment
   ↓
描述“程序运行时应该怎样被加载”
```

---

# 10. 为什么出现 RWX？

RWX：

```text
R = Read
W = Write
X = Execute
```

所以：

```text
RWX
```

就是：

> 一个 LOAD segment 同时可读、可写、可执行。

现代 Linux 环境通常不希望出现这样的布局。

理想情况下：

```text
.text
    ↓
R-X

.data
.bss
    ↓
RW-
```

也就是：

```text
          Permission

.text     R-X
.rodata   R--

.data     RW-
.bss      RW-
```

---

# 11. 为什么我们的实验产生 RWX？

这其实是我们这个实验的 linker script 导致的。

现在：

```ld
SECTIONS
{
    . = 0x100000;

    .text :
    {
        *(.text)
    }

    . = 0x200000;

    .data :
    {
        *(.data)
    }

    .bss :
    {
        *(.bss)
    }
}
```

你告诉 linker：

```text
.text
.data
.bss
```

怎么排列。

但是你**没有告诉 linker 应该怎样创建 Program Header / LOAD Segment**。

于是 linker 根据默认规则进行推导。

最终可能形成：

```text
LOAD
│
├── .text
├── .data
└── .bss
```

于是：

```text
R + X
+
R + W
```

最后可能合并成：

```text
RWX
```

于是 warning：

```text
LOAD segment with RWX permissions
```

---

# 12. 这其实是一个非常好的学习机会

你现在遇到的两个 warning：

```text
.note.GNU-stack
```

和：

```text
LOAD segment RWX
```

刚好把我们引向 ELF 的两个层次：

```text
              ELF
               │
       ┌───────┴────────┐
       │                │
    Sections         Segments
       │                │
       │                │
  .text/.data       PT_LOAD
  .bss/.rodata      permissions
       │                │
       ▼                ▼
    Linker           Loader
```

---

# 13. 现在先不要急着修 RWX

我反而建议：

# ⭐ 暂时保留这个 warning。

因为我们现在正处于：

```text
实验 02
```

真正目的就是学习：

```text
SECTIONS
```

如果现在直接加入：

```ld
PHDRS
```

一下就跨到了：

```text
Section
     ↓
Segment
     ↓
Program Header
```

容易把几个概念混在一起。

---

# 14. 但我们可以先验证它

执行：

```bash
readelf -l custom.elf
```

重点找：

```text
Section to Segment mapping:
```

可能看到：

```text
Segment Sections...
   00
   01     .text .data .bss
```

这张表非常重要。

它告诉你：

```text
Segment #1
   │
   ├── .text
   ├── .data
   └── .bss
```

所以：

```text
多个 Section
      │
      ▼
一个 LOAD Segment
```

这就是为什么权限会产生冲突。

---

# 15. 用一个图理解

目前你的 ELF 大概是：

```text
                custom.elf
                    │
             Program Headers
                    │
                 PT_LOAD
                    │
       ┌────────────┼────────────┐
       │            │            │
       ▼            ▼            ▼
     .text        .data         .bss
       │            │            │
      R-X          RW-          RW-
       │            │            │
       └────────────┼────────────┘
                    │
                    ▼
                  RWX
```

因为：

```text
.text → X
.data → W
.bss  → W
```

被放进了同一个：

```text
PT_LOAD
```

所以：

```text
PT_LOAD = RWX
```

---

# 16. 第一个 warning 应该修掉

最终 `start.S` 推荐：

```asm
.global _start

_start:
    call main

    mov %eax, %edi

    mov $60, %eax
    syscall


.section .note.GNU-stack,"",@progbits
```

然后：

```bash
rm -f start.o custom.elf custom.map

gcc -c start.S -o start.o

gcc -c main.c -o main.o

ld \
    -T linker.ld \
    start.o \
    main.o \
    -o custom.elf \
    -Map=custom.map
```

此时：

```text
missing .note.GNU-stack
```

这个 warning 应该消失。

---

# 17. 第二个 warning 暂时保留

也就是说最终可能：

```text
ld: warning: custom.elf has a LOAD segment with RWX permissions
```

但：

```text
missing .note.GNU-stack
```

消失。

这不是实验失败。

相反，我们已经获得了一个非常有价值的实验结果：

```text
Section Layout
       │
       ▼
Program Header Layout
       │
       ▼
LOAD Segment
       │
       ▼
Permissions
```

---

# 18. 顺便验证一下程序

运行：

```bash
./custom.elf
echo $?
```

应该：

```text
42
```

如果得到：

```text
42
```

说明：

```text
_start
  ↓
main
  ↓
global_data
  ↓
global_bss
  ↓
return 42
  ↓
syscall exit
```

整个链接流程是工作的。

---

# 19. 一个很重要的纠正

这里我想把上一实验的一个简化说法进一步精确化。

我们之前说：

```text
.text = 0x100000
.data = 0x200000
.bss  = ...
```

这是：

> **Output Section 的 VMA 布局。**

但最终 ELF 是否把它们放入一个还是多个：

```text
PT_LOAD
```

是另外一个层次。

所以以后看到：

```text
readelf -S
```

和：

```text
readelf -l
```

不要混淆：

```text
readelf -S
       │
       ▼
Section View
```

```text
readelf -l
       │
       ▼
Segment / Program Header View
```

---

# 🧠 实验 02 到这里应该形成的完整脑图

```text
                         ELF
                          │
              ┌───────────┴───────────┐
              │                       │
          Sections                 Segments
              │                       │
              │                       │
       ┌──────┼──────┐              PT_LOAD
       │      │      │                 │
     .text  .data  .bss                │
       │      │      │                 │
       │      │      │                 │
      R-X    RW-    RW-                │
       │      │      │                 │
       └──────┼──────┘                 │
              │                        │
              └────────────┬───────────┘
                           │
                    Segment Mapping
                           │
                           ▼
                     Permissions
                           │
                           ▼
                         RWX
```

同时：

```text
start.S
   │
   ▼
.note.GNU-stack
   │
   ▼
告诉 linker
“我不需要 executable stack”
```

---

# 🔥 下一步：实验 03 就该进入真正的 VMA/LMA

你现在已经具备进入下一阶段的基础。

下一实验我们不再只是：

```text
.text
.data
.bss
```

而是做一个真正的：

```text
             ROM / FLASH
          0x08000000
               │
               ├── .text
               ├── .rodata
               │
               └── .data 初始值
                       │
                       │ LMA
                       │
                       ▼
             RAM
          0x20000000
               │
               ├── .data
               │
               └── .bss
```

然后正式引入：

```ld
AT > ROM
```

以及：

```ld
LOADADDR(.data)
ADDR(.data)
SIZEOF(.data)
```

最终写出真正的启动代码：

```asm
/* copy .data */
memcpy(
    VMA(.data),
    LMA(.data),
    SIZEOF(.data)
);

/* clear .bss */
memset(
    VMA(.bss),
    0,
    SIZEOF(.bss)
);
```

这一步会把你之前研究的 **`.data` 从 ROM 搬到 RAM**，和我们现在学到的 **Section / Segment / Linker Script / Symbol** 全部串起来。

