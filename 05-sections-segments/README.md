# GNU ld 实战课程 · 实验 05

## Section → Segment：从“链接布局”进入 ELF Loader 世界

上一节我们已经完成了：

```text
.o
 ↓
ld
 ↓
linker.ld
 ↓
.text / .rodata / .data / .bss
 ↓
VMA / LMA
 ↓
startup code
```

这一节解决一个非常关键的问题：

> **为什么 `readelf -S` 看到的 Section，和 `readelf -l` 看到的 Segment 是两套完全不同的东西？**

同时，直接解决你实验 02 遇到的：

```text
ld: warning: custom.elf has a LOAD segment with RWX permissions
```

这一节结束后，你应该建立这个模型：

```text
                    ELF
                     │
          ┌──────────┴──────────┐
          │                     │
          ▼                     ▼
      Sections              Segments
       -S                     -l
          │                     │
          │                     │
          ▼                     ▼
   链接器组织方式          Loader加载方式
          │                     │
          └──────────┬──────────┘
                     ▼
               Section → Segment
```

---

# 一、先建立最重要的区别

ELF 中同时存在：

```text
Section
Segment
```

它们服务于不同对象。

## Section

主要服务于：

```text
链接器
调试器
符号分析工具
objdump
```

典型：

```text
.text
.rodata
.data
.bss
.symtab
.strtab
.rela.text
```

查看：

```bash
readelf -S custom.elf
```

---

## Segment

主要服务于：

```text
程序加载器
操作系统 loader
动态链接器
```

典型：

```text
PT_LOAD
PT_DYNAMIC
PT_INTERP
PT_NOTE
```

查看：

```bash
readelf -l custom.elf
```

---

# 二、一个非常重要的类比

可以这样理解：

```text
Section
=
“仓库里的货物分类”

Segment
=
“运输车”
```

例如：

```text
Section：

.text
.rodata
.data
.bss
```

linker 可以把它们按照实际加载需求打包成：

```text
Segment：

PT_LOAD R E
    ├── .text
    └── .rodata

PT_LOAD RW
    ├── .data
    └── .bss
```

所以：

```text
一个 Segment
可以包含多个 Section
```

但：

```text
Section ≠ Segment
```

---

# 三、继续使用上一实验代码

目录：

```text
ld-lab/
├── main.c
├── start.S
└── linker.ld
```

`main.c`：

```c
volatile int global_data = 123;

volatile int global_bss;

int main(void)
{
    global_bss = global_data + 1;

    return global_bss;
}
```

`start.S`：

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

先暂时不用 `.data` copy，因为这一节的目标是研究 ELF 的 **Section → Segment 映射**。

---

# 四、实验 05-A：不使用 PHDRS

先建立：

```ld
ENTRY(_start)

MEMORY
{
    ROM (rx)  : ORIGIN = 0x00400000, LENGTH = 64K
    RAM (rwx) : ORIGIN = 0x00600000, LENGTH = 64K
}

SECTIONS
{
    .text ALIGN(16) :
    {
        _stext = .;
        *(.text)
        _etext = .;
    } > ROM

    .rodata ALIGN(8) :
    {
        *(.rodata)
    } > ROM

    .data ALIGN(8) :
    {
        _sdata = .;
        *(.data)
        _edata = .;
    } > RAM AT > ROM

    _sidata = LOADADDR(.data);

    .bss ALIGN(8) :
    {
        _sbss = .;
        *(.bss)
        *(COMMON)
        _ebss = .;
    } > RAM
}
```

---

# 五、编译

```bash
rm -f *.o custom.elf custom.map

gcc -c main.c -o main.o
gcc -c start.S -o start.o
```

然后：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    -o custom.elf \
    -Map=custom.map
```

---

# 六、先看 Section

```bash
readelf -S custom.elf
```

你会看到类似：

```text
.text
.rodata
.data
.bss
.symtab
.strtab
.shstrtab
```

这是：

```text
Section Header Table
```

---

# 七、再看 Segment

执行：

```bash
readelf -l custom.elf
```

你会看到类似：

```text
Program Headers:

Type           Offset   VirtAddr
               PhysAddr
               FileSiz  MemSiz
               Flg      Align

LOAD           ...
LOAD           ...
```

最重要的是：

```text
Section to Segment mapping:
```

例如可能出现：

```text
Segment Sections...
   00     .text .rodata
   01     .data .bss
```

这就是 ELF 正式告诉 loader：

```text
PT_LOAD #0
    .text
    .rodata

PT_LOAD #1
    .data
    .bss
```

---

# 八、现在理解之前那个 RWX 警告

如果你看到：

```text
ld: warning: custom.elf has a LOAD segment with RWX permissions
```

本质就是：

```text
某个 PT_LOAD

R
W
X

三个权限同时存在
```

即：

```text
RWX
```

例如：

```text
PT_LOAD
├── .text    X
├── .data    W
└── .bss     W
```

于是 linker 推断：

```text
R + W + X
```

得到：

```text
RWX
```

从安全角度看，这通常不是一个理想的最终布局。

---

# 九、为什么 Section 权限会影响 Segment？

注意 linker script 中：

```ld
MEMORY
{
    ROM (rx) ...
    RAM (rwx) ...
}
```

然后：

```ld
.text > ROM
```

因此：

```text
.text
→ ROM
→ RX
```

而：

```ld
.data > RAM
```

因此：

```text
.data
→ RAM
→ RW
```

问题来了：

```text
linker
```

需要决定：

```text
哪些 Section
放进哪个 PT_LOAD？
```

如果没有显式：

```ld
PHDRS
```

linker 会根据 ELF 输出属性自动组织 Segment。

这就是：

```text
implicit segment layout
```

---

# 十、实验 05-B：开始使用 PHDRS

现在我们第一次真正使用：

```ld
PHDRS
```

修改 linker script：

```ld
ENTRY(_start)

MEMORY
{
    ROM (rx)  : ORIGIN = 0x00400000, LENGTH = 64K
    RAM (rw)  : ORIGIN = 0x00600000, LENGTH = 64K
}

PHDRS
{
    text PT_LOAD FLAGS(5);
    data PT_LOAD FLAGS(6);
}

SECTIONS
{
    .text ALIGN(16) :
    {
        _stext = .;

        *(.text)

        _etext = .;
    } > ROM :text

    .rodata ALIGN(8) :
    {
        *(.rodata)
    } > ROM :text

    .data ALIGN(8) :
    {
        _sdata = .;

        *(.data)

        _edata = .;
    } > RAM AT > ROM :data

    _sidata = LOADADDR(.data);

    .bss ALIGN(8) :
    {
        _sbss = .;

        *(.bss)
        *(COMMON)

        _ebss = .;
    } > RAM :data
}
```

这里出现了两个新语法：

```ld
:text
```

和：

```ld
:data
```

它们就是：

> **告诉 linker：这个 Output Section 应该属于哪个 Program Header。**

---

# 十一、`FLAGS(5)` 是什么意思？

这是今天非常重要的一个数字。

ELF Segment Flags：

```text
PF_X = 1
PF_W = 2
PF_R = 4
```

所以：

```text
5
=
4 + 1
=
R + X
```

也就是：

```text
FLAGS(5)
```

等价：

```text
R-X
```

---

而：

```text
FLAGS(6)
```

是：

```text
6
=
4 + 2
=
R + W
```

所以：

```text
FLAGS(6)
```

就是：

```text
RW-
```

最终：

```text
PHDRS
{
    text PT_LOAD FLAGS(5);
    data PT_LOAD FLAGS(6);
}
```

得到：

```text
PT_LOAD
R E

PT_LOAD
RW
```

而不是：

```text
PT_LOAD
RWX
```

---

# 十二、重新链接

```bash
rm -f custom.elf custom.map

ld \
    -T linker.ld \
    start.o \
    main.o \
    -o custom.elf \
    -Map=custom.map
```

现在：

```bash
readelf -l custom.elf
```

重点看：

```text
LOAD
```

理想情况下应该类似：

```text
LOAD ... R E
LOAD ... RW
```

也就是说：

```text
Segment #0
    R E
    ├── .text
    └── .rodata

Segment #1
    RW
    ├── .data
    └── .bss
```

---

# 十三、Section → Segment 映射

继续：

```bash
readelf -l custom.elf
```

找到：

```text
Section to Segment mapping:
```

你应该看到类似：

```text
Segment Sections...
   00     .text .rodata
   01     .data .bss
```

现在把两条命令放在一起：

```bash
readelf -S custom.elf
```

和：

```bash
readelf -l custom.elf
```

你就能看到：

```text
Section
   │
   │ :text
   ▼
PT_LOAD
R E
```

以及：

```text
Section
   │
   │ :data
   ▼
PT_LOAD
RW
```

---

# 十四、`objdump -h` 再验证

执行：

```bash
objdump -h custom.elf
```

重点：

```text
.text
.rodata
.data
.bss
```

这里主要看：

```text
VMA
LMA
File offset
Size
```

而：

```bash
readelf -l
```

重点看：

```text
Offset
VirtAddr
PhysAddr
FileSiz
MemSiz
Flags
Align
```

于是：

```text
objdump -h
```

和：

```text
readelf -l
```

形成互补。

---

# 十五、最重要的关系：FileSiz vs MemSiz

现在看：

```text
PT_LOAD
```

有两个非常重要的字段：

```text
FileSiz
MemSiz
```

例如：

```text
FileSiz = 0x100
MemSiz  = 0x120
```

意味着：

```text
文件中实际存在：

0x100 bytes

内存中需要：

0x120 bytes
```

多出来：

```text
0x20
```

通常就是：

```text
.bss
```

因为：

```text
.bss
```

需要占用内存，但是：

```text
不需要占用 ELF 文件中的实际初始化数据空间。
```

所以：

```text
FileSiz
    ↓
文件里需要多少

MemSiz
    ↓
加载到内存后需要多少
```

---

# 十六、这和 `.bss` 完美对应

假设：

```text
.data = 8 bytes
.bss  = 8 bytes
```

那么：

```text
PT_LOAD RW
```

可能是：

```text
FileSiz = 8
MemSiz  = 16
```

内存布局：

```text
RAM
│
├── .data
│   8 bytes
│
└── .bss
    8 bytes
```

但是 ELF 文件：

```text
file
│
└── .data
    8 bytes
```

`.bss`：

```text
不需要真正保存 8 个 0
```

这就是：

```text
SHT_NOBITS
```

---

# 十七、现在观察 `.bss`

执行：

```bash
readelf -S custom.elf
```

找到：

```text
.bss
```

看它的：

```text
Type
```

应该是：

```text
NOBITS
```

这三个字母非常值得记住：

```text
SHT_NOBITS
```

意思：

> Section 在逻辑上存在，但是没有对应的文件内容。

因此：

```text
.bss
```

可以：

```text
占 RAM
```

但：

```text
不占 ELF 文件实际数据空间
```

---

# 十八、现在进入一个很重要的 ELF 三层模型

以后分析 ELF，建议永远同时看这三层：

```text
                    ELF
                     │
       ┌─────────────┼─────────────┐
       │             │             │
       ▼             ▼             ▼
    Section       Symbol         Segment
       │             │             │
       │             │             │
       ▼             ▼             ▼
   readelf -S    readelf -s    readelf -l
   objdump -h       nm
```

三者解决三个不同问题。

---

## Section

问：

> “代码和数据怎么组织？”

```text
.text
.data
.bss
.rodata
```

---

## Symbol

问：

> “这个函数/变量在哪里？”

```text
main
global_data
_sdata
_ebss
```

---

## Segment

问：

> “loader 到底加载什么？”

```text
PT_LOAD
R E
PT_LOAD
RW
```

---

# 十九、Map 文件在这里干什么？

打开：

```bash
less custom.map
```

重点找：

```text
.text
```

```text
.rodata
```

```text
.data
```

```text
.bss
```

你会得到：

```text
main.o
    │
    ├── .text
    ├── .data
    └── .bss
```

再对应：

```text
linker.ld
```

中的：

```ld
.text   > ROM :text
.rodata > ROM :text

.data   > RAM :data
.bss    > RAM :data
```

最终形成：

```text
                    linker.ld
                        │
          ┌─────────────┴─────────────┐
          ▼                           ▼
       :text                        :data
          │                           │
          ▼                           ▼
       PT_LOAD                     PT_LOAD
        R E                          RW
          │                           │
    ┌─────┴─────┐               ┌────┴────┐
    ▼           ▼               ▼         ▼
  .text      .rodata          .data     .bss
```

这就是今天整个实验的核心。

---

# 二十、一个容易踩的坑：`:NONE`

现在你已经知道：

```ld
.text :text
```

是在控制 Segment。

那么下面这个语法也值得记住：

```ld
.foo :
{
    *(.foo)
} :NONE
```

意思是：

> 不把这个 Output Section 放进任何 Program Header。

这在以后处理：

```text
.debug_*
.symtab
.strtab
```

等特殊 Section 时会很有用。

---

# 二十一、为什么 PHDRS 是“高级 linker script”分水岭？

到目前为止：

```text
SECTIONS
```

解决的是：

```text
Section 在哪里？
```

而：

```text
PHDRS
```

解决的是：

```text
Segment 怎么组织？
```

所以可以建立：

```text
MEMORY
   │
   └── 描述物理/逻辑内存区域

SECTIONS
   │
   └── 描述 Section 布局

PHDRS
   │
   └── 描述 Program Segment 布局
```

三者关系：

```text
              linker script
                    │
       ┌────────────┼────────────┐
       ▼            ▼            ▼
    MEMORY       SECTIONS       PHDRS
       │            │            │
       │            │            │
       ▼            ▼            ▼
    内存区域      Section       Segment
```

---

# 二十二、今天再做一个强制实验

把：

```ld
PHDRS
{
    text PT_LOAD FLAGS(5);
    data PT_LOAD FLAGS(6);
}
```

故意改成：

```ld
PHDRS
{
    everything PT_LOAD FLAGS(7);
}
```

然后：

```ld
.text :
{
    *(.text)
} > ROM :everything

.rodata :
{
    *(.rodata)
} > ROM :everything

.data :
{
    *(.data)
} > RAM :everything

.bss :
{
    *(.bss)
} > RAM :everything
```

重新链接：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    -o custom.elf \
    -Map=custom.map
```

然后：

```bash
readelf -l custom.elf
```

你会再次看到：

```text
RWE
```

或者：

```text
RWX
```

为什么？

因为：

```text
FLAGS(7)
```

就是：

```text
4 + 2 + 1
```

也就是：

```text
R + W + X
```

这个实验非常值得做。

---

# 二十三、再恢复正确版本

恢复：

```ld
PHDRS
{
    text PT_LOAD FLAGS(5);
    data PT_LOAD FLAGS(6);
}
```

并：

```ld
.text :text
.rodata :text

.data :data
.bss :data
```

重新链接。

最终应该是：

```text
PT_LOAD
R E
```

和：

```text
PT_LOAD
RW
```

---

# 二十四、今天真正理解的 ELF 加载模型

现在可以把整个 ELF 看成：

```text
ELF 文件
│
├── Section Header Table
│      │
│      ├── .text
│      ├── .rodata
│      ├── .data
│      ├── .bss
│      └── ...
│
├── Program Header Table
│      │
│      ├── PT_LOAD R E
│      │      ├── .text
│      │      └── .rodata
│      │
│      └── PT_LOAD RW
│             ├── .data
│             └── .bss
│
└── Symbol Table
       │
       ├── _start
       ├── main
       ├── global_data
       ├── _sdata
       └── _ebss
```

---

# 二十五、五条命令，现在应该形成固定习惯

以后拿到一个 ELF，我建议你形成这个顺序：

### ① 看文件类型

```bash
file custom.elf
```

---

### ② 看 Section

```bash
readelf -S custom.elf
```

---

### ③ 看 Segment

```bash
readelf -l custom.elf
```

---

### ④ 看 Symbol

```bash
readelf -s custom.elf
nm -n custom.elf
```

---

### ⑤ 看实际机器码

```bash
objdump -d custom.elf
```

然后：

```bash
objdump -h custom.elf
```

最后：

```bash
less custom.map
```

这套组合基本就是 ELF / linker 问题的“CT 扫描”。

---

# 二十六、实验 05 的知识闭环

现在把前四个实验全部串起来：

```text
                  main.c
                    │
                    ▼
                 main.o
                    │
                    │
             ┌──────▼──────┐
             │     ld      │
             └──────┬──────┘
                    │
             linker.ld
                    │
       ┌────────────┼────────────┐
       ▼            ▼            ▼
    MEMORY       SECTIONS       PHDRS
       │            │            │
       ▼            ▼            ▼
   ROM / RAM     .text/.data    PT_LOAD
                    │            │
                    └─────┬──────┘
                          ▼
                         ELF
                          │
             ┌────────────┼────────────┐
             ▼            ▼            ▼
          Section       Symbol      Segment
             │            │            │
          readelf -S   nm/readelf   readelf -l
             │            │            │
             └────────────┼────────────┘
                          ▼
                      Loader
```

---

# 二十七、下一实验：ALIGN——链接器中的“地址数学”

下一节进入一个非常实用、而且以后写 MCU linker script **天天会碰到**的主题：

# 实验 06：`ALIGN`、对齐、padding 与地址计算

我们会亲手制造：

```text
.text
0x400000
      ↓
0x400137
```

然后要求：

```ld
. = ALIGN(16);
```

变成：

```text
0x400140
```

接着分析：

```text
ALIGN(4)
ALIGN(8)
ALIGN(16)
ALIGN(4096)
```

以及：

```ld
. = ALIGN(16);

__foo_start = .;

*(.foo)

__foo_end = .;
```

进一步进入：

```text
ALIGN
SUBALIGN
BLOCK
MAX
MIN
ABSOLUTE
NEXT
```

最后会把这些地址运算和：

```text
MEMORY
SECTIONS
PHDRS
VMA
LMA
```

组合起来。

这一步之后，你写 linker script 就不再是“背语法”，而是开始真正进行**链接时地址计算**。

