# GNU ld 实战课程 · 实验 06

## `ALIGN()`、`.`、padding：真正掌握链接器的“地址数学”

上一节你指出了一个很关键的问题：**`ALIGN()` 的不同使用位置不能混为一谈。**

这里先把规则彻底校正一下。GNU ld 当前手册明确说明：

```ld
.text ALIGN(0x10) : { *(.text) }
```

中的 `ALIGN(0x10)` 是 **Output Section Address**，用于指定输出 section 的 VMA；而：

```ld
.text :
{
    . = ALIGN(0x10);
    ...
}
```

则是在 section 内容描述中操作 **location counter `.`**。`ALIGN(align)` 本身返回向上对齐后的地址，并不会单独改变 location counter。([Sourceware][1])

所以这一节我们专门把这两个概念拆开实验，避免后面越学越乱。

---

# 一、今天的核心目标

今天不再简单地“会写 `ALIGN(16)`”，而是要真正理解：

```text
.
│
│ 当前地址
│
├── ALIGN(4)
├── ALIGN(8)
├── ALIGN(16)
├── ALIGN(0x100)
│
└── padding
```

最终理解：

```text
ALIGN()
   ↓
地址计算
   ↓
location counter
   ↓
section 大小变化
   ↓
padding
   ↓
VMA / LMA
   ↓
map 文件
```

---

# 二、先记住一个公式

假设：

```text
当前地址 = 0x1003
```

执行：

```ld
ALIGN(0x10)
```

得到：

```text
0x1010
```

因为：

```text
0x1003
   ↓
下一个 0x10 对齐地址
   ↓
0x1010
```

再比如：

```text
当前 = 0x1021

ALIGN(0x10)
       ↓
0x1030
```

因此：

```text
ALIGN(N)
```

可以理解成：

> **把一个地址向上取整到 N 的边界。**

---

# 三、但是有一个非常重要的区别

看：

```ld
foo = ALIGN(16);
```

这是：

```text
计算一个对齐后的值
```

而：

```ld
. = ALIGN(16);
```

这是：

```text
把 location counter 移到对齐后的地址
```

所以：

```text
foo = ALIGN(16)
```

和：

```text
. = ALIGN(16)
```

完全不是一个动作。

---

# 四、实验 06-1：观察最原始的 `.`

创建：

```text
ld-lab/
├── main.c
├── start.S
└── linker.ld
```

---

## main.c

这次故意制造不同大小的数据：

```c
volatile int a = 1;
volatile char b = 2;
volatile int c = 3;

int main(void)
{
    return a + b + c;
}
```

理论上：

```text
a → .data
b → .data
c → .data
```

---

# 五、start.S

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

# 六、第一版 linker.ld：完全不主动 ALIGN

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

        _etext = .;
    } > ROM :text

    .rodata :
    {
        *(.rodata)
    } > ROM :text

    .data :
    {
        _sdata = .;

        *(.data)

        _edata = .;
    } > RAM AT > ROM :data

    .bss :
    {
        _sbss = .;

        *(.bss)
        *(COMMON)

        _ebss = .;
    } > RAM :data
}
```

---

# 七、编译

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

# 八、先观察 `.data`

```bash
objdump -h custom.elf
```

再：

```bash
readelf -S custom.elf
```

以及：

```bash
nm -n custom.elf
```

找到：

```text
a
b
c
_sdata
_edata
```

---

# 九、这里先提出一个问题

假设：

```text
_sdata = 0x600000
```

那么：

```text
a = 4 bytes
b = 1 byte
c = 4 bytes
```

是不是一定：

```text
a
b
padding
c
```

？

**不一定按照你脑子里简单的 C 结构体规则来理解。**

真正决定每个 input section 内部布局的是：

```text
编译器
+
汇编器
+
input section alignment
+
linker
```

因此下一步我们要主动制造 section。

---

# 十、实验 06-2：自己制造 `.foo`

创建：

```text
foo.S
```

内容：

```asm
.section .foo,"a"

.byte 0x11
.byte 0x22
.byte 0x33

.section .bar,"a"

.byte 0xaa
```

编译：

```bash
gcc -c foo.S -o foo.o
```

查看：

```bash
objdump -h foo.o
```

应该看到：

```text
.foo
.bar
```

---

# 十一、把 `.foo` 和 `.bar` 放到 ELF

linker.ld：

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
        *(.text)
    } > ROM :text

    .rodata :
    {
        *(.rodata)
    } > ROM :text

    .foo :
    {
        foo_start = .;

        *(.foo)

        foo_end = .;
    } > ROM :text

    .bar :
    {
        bar_start = .;

        *(.bar)

        bar_end = .;
    } > ROM :text

    .data :
    {
        _sdata = .;

        *(.data)

        _edata = .;
    } > RAM AT > ROM :data

    .bss :
    {
        _sbss = .;

        *(.bss)
        *(COMMON)

        _ebss = .;
    } > RAM :data
}
```

重新链接：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    foo.o \
    -o custom.elf \
    -Map=custom.map
```

---

# 十二、观察 `.foo` / `.bar`

```bash
objdump -h custom.elf
```

然后：

```bash
nm -n custom.elf
```

找到：

```text
foo_start
foo_end
bar_start
bar_end
```

因为：

```asm
.foo
.byte 0x11
.byte 0x22
.byte 0x33
```

所以：

```text
foo_end - foo_start
=
3
```

而：

```asm
.bar
.byte 0xaa
```

所以：

```text
bar_end - bar_start
=
1
```

---

# 十三、现在真正使用 `. = ALIGN(16)`

修改：

```ld
.foo :
{
    foo_start = .;

    *(.foo)

    foo_end = .;
} > ROM :text
```

为：

```ld
.foo :
{
    . = ALIGN(16);

    foo_start = .;

    *(.foo)

    foo_end = .;
} > ROM :text
```

重新链接：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    foo.o \
    -o custom.elf \
    -Map=custom.map
```

---

# 十四、发生了什么？

假设进入 `.foo` 时：

```text
. = 0x400013
```

执行：

```ld
. = ALIGN(16);
```

得到：

```text
. = 0x400020
```

于是：

```text
0x400013
     │
     │ padding
     │
     ▼
0x400020
     │
     └── foo
```

所以：

```text
foo_start
=
0x400020
```

---

# 十五、用 map 文件验证

```bash
grep -A 12 -B 3 "\.foo" custom.map
```

观察：

```text
.foo
```

然后：

```bash
nm -n custom.elf | grep foo
```

把两个结果对起来。

这时你会非常直观地看到：

```text
之前：

foo_start = 0x400013

之后：

foo_start = 0x400020
```

中间多出来的：

```text
0x0d
```

就是 padding。

---

# 十六、这就是 linker padding

可以画成：

```text
原始：

0x400013
│
├── .foo
│
└── ...

ALIGN(16)

0x400013
│
├── padding
│
│  0x0d bytes
│
▼
0x400020
│
├── .foo
│
└── ...
```

所以：

> `ALIGN()` 不只是“改变一个数字”，它可能直接导致 ELF 中产生实际的地址间隙。

---

# 十七、实验 06-3：区分 `foo = ALIGN(16)` 和 `. = ALIGN(16)`

这是本节最重要的实验。

先写：

```ld
.foo :
{
    foo_aligned = ALIGN(16);

    foo_start = .;

    *(.foo)

    foo_end = .;
} > ROM :text
```

注意：

```ld
foo_aligned = ALIGN(16);
```

而不是：

```ld
. = ALIGN(16);
```

重新链接：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    foo.o \
    -o custom.elf \
    -Map=custom.map
```

然后：

```bash
nm -n custom.elf | grep -E 'foo_(aligned|start|end)'
```

你会看到类似：

```text
foo_aligned = 0x400020
foo_start   = 0x400013
foo_end     = 0x400016
```

这三个值可能不同。

---

# 十八、为什么？

因为：

```ld
foo_aligned = ALIGN(16);
```

只是：

```text
计算：

ALIGN(.)
```

然后：

```text
把结果保存给 foo_aligned
```

它没有改变：

```text
.
```

所以：

```text
foo_aligned
       ↓
0x400020

.
       ↓
仍然是 0x400013
```

---

而：

```ld
. = ALIGN(16);
```

则是：

```text
计算 ALIGN(.)
       ↓
得到 0x400020
       ↓
把结果写回 .
       ↓
. = 0x400020
```

这就是为什么：

```text
foo = ALIGN(16)
```

和：

```text
. = ALIGN(16)
```

必须严格区分。

GNU ld 手册也明确指出，单参数 `ALIGN` 本身只是对 location counter 做算术计算，并不会修改 location counter；将其赋值给 `.` 才会改变当前地址。([Sourceware][2])

---

# 十九、实验 06-4：Output Section 地址上的 ALIGN

现在再专门实验你之前指出的语法：

```ld
.foo ALIGN(16) :
{
    *(.foo)
} > ROM :text
```

这也是合法的 GNU ld 语法。

GNU ld 文档把这里的：

```ld
ALIGN(16)
```

定义为：

> Output Section Address。

也就是直接指定：

```text
.foo 的 VMA
```

而不是在 section 内容中修改 location counter。([Sourceware][1])

所以现在有三种写法：

### 写法 A

```ld
.foo ALIGN(16) :
{
    *(.foo)
}
```

含义：

```text
指定 .foo Output Section 的地址
```

---

### 写法 B

```ld
.foo :
{
    . = ALIGN(16);

    *(.foo)
}
```

含义：

```text
进入 .foo 后
把 location counter 对齐
```

---

### 写法 C

```ld
.foo :
{
    foo_start = ALIGN(16);

    *(.foo)
}
```

含义：

```text
计算一个对齐后的数值
保存给 foo_start

但是不移动 .
```

---

# 二十、把三者画成一张图

```text
                 ALIGN(16)
                     │
       ┌─────────────┼─────────────┐
       │             │             │
       ▼             ▼             ▼

.foo ALIGN(16) :   . = ALIGN(16)   x = ALIGN(16)
       │             │             │
       ▼             ▼             ▼
Section VMA       修改 "."       只计算数值
       │             │             │
       ▼             ▼             ▼
    .foo地址       当前地址       x得到结果
```

这张图建议直接记下来。

---

# 二十一、实验 06-5：观察 ALIGN 产生的 padding

现在制造一个特别明显的例子。

`foo.S`：

```asm
.section .foo,"a"

.byte 1
.byte 2
.byte 3
.byte 4
.byte 5
```

然后：

```ld
.foo :
{
    . = ALIGN(0x100);

    foo_start = .;

    *(.foo)

    foo_end = .;
} > ROM :text
```

重新链接。

假设进入 `.foo` 时：

```text
0x400013
```

那么：

```text
ALIGN(0x100)
```

得到：

```text
0x400100
```

于是产生：

```text
0xed bytes
```

左右的地址空洞。

用：

```bash
objdump -h custom.elf
```

观察 section 地址。

再：

```bash
readelf -S custom.elf
```

观察：

```text
Address
Offset
Size
```

最后：

```bash
grep -A 15 -B 3 "\.foo" custom.map
```

观察 map。

---

# 二十二、进一步理解：ALIGN 会影响 section 大小吗？

这里非常容易误解。

如果：

```ld
.foo :
{
    . = ALIGN(0x100);

    *(.foo)
}
```

那么对齐发生在：

```text
.foo 内容开始之前
```

因此它可能形成 section 内部的前置空洞。

而如果：

```ld
.foo :
{
    *(.foo)

    . = ALIGN(0x100);
}
```

那么：

```text
.foo 内容
    ↓
padding
    ↓
section结束
```

这时 padding 在尾部。

---

# 二十三、实验：前对齐 vs 后对齐

### A：前面对齐

```ld
.foo :
{
    . = ALIGN(16);

    foo_start = .;

    *(.foo)

    foo_end = .;
}
```

布局：

```text
padding
↓
.foo
```

---

### B：后面对齐

```ld
.foo :
{
    foo_start = .;

    *(.foo)

    foo_end = .;

    . = ALIGN(16);
}
```

布局：

```text
.foo
↓
padding
```

这两个实验非常值得亲自比较：

```bash
objdump -h custom.elf
```

和：

```bash
nm -n custom.elf
```

---

# 二十四、现在引入 `ALIGNOF`

GNU ld 还有一个非常有用的 builtin：

```ld
ALIGNOF(section)
```

它返回：

> 指定 Output Section 的对齐要求。([Sourceware][2])

例如：

```ld
foo_alignment = ALIGNOF(.foo);
```

然后：

```bash
nm -n custom.elf | grep foo_alignment
```

你就可以看到 linker 实际计算出来的 section alignment。

---

# 二十五、实验 06-6：让 linker 告诉我们 section alignment

修改：

```ld
.foo :
{
    foo_start = .;

    *(.foo)

    foo_end = .;
} > ROM :text

foo_alignment = ALIGNOF(.foo);
```

然后：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    foo.o \
    -o custom.elf \
    -Map=custom.map
```

执行：

```bash
nm -n custom.elf | grep foo
```

重点观察：

```text
foo_start
foo_end
foo_alignment
```

---

# 二十六、现在理解 Input Section Alignment

这里开始进入更深一层：

```text
Output Section
        │
        ├── Input Section A
        ├── Input Section B
        └── Input Section C
```

每个 input section 本身可能要求：

```text
A → 4-byte alignment
B → 16-byte alignment
C → 32-byte alignment
```

那么 Output Section 的 alignment requirement 至少需要满足其中最严格的要求。

GNU ld 的 Output Section Address 规则明确指出：如果没有显式给出输出地址，linker 会根据其中 input sections 的最严格对齐要求调整输出 section 地址。([Sourceware][1])

所以：

```text
Input Sections
     │
     ├── align 4
     ├── align 16
     └── align 32
             │
             ▼
Output Section
       alignment ≥ 32
```

这就是 linker 为什么有时候：

> “我明明没写 ALIGN，为什么 `.text` 自己跑到了一个很整齐的地址？”

答案经常就在这里。

---

# 二十七、今天的 map 文件分析方法

以后看到：

```text
.data
```

不要只看：

```text
地址
大小
```

还要问：

```text
① 当前地址从哪里来？

② 为什么这个地址是这个值？

③ 前面有没有 ALIGN？

④ 有没有 padding？

⑤ input section 的 alignment 是多少？

⑥ output section 的 alignment 是多少？

⑦ 有没有 MEMORY region 导致地址变化？
```

例如：

```text
.text
    ↓
结束地址 0x400137

ALIGN(16)
    ↓
0x400140

.rodata
    ↓
```

那么：

```text
0x400140 - 0x400137
=
9
```

就是地址调整产生的 gap。

---

# 二十八、把今天所有知识串起来

现在 linker script 中：

```ld
MEMORY
{
    ROM : ORIGIN = ..., LENGTH = ...
}
```

负责：

```text
“去哪块内存”
```

---

```ld
.text :
{
    ...
} > ROM
```

负责：

```text
“这个 Output Section 放到哪里”
```

---

```ld
. = ALIGN(16);
```

负责：

```text
“当前位置向上对齐”
```

---

```ld
foo = ALIGN(16);
```

负责：

```text
“计算一个对齐后的地址”
```

---

```ld
.text ALIGN(16) :
```

负责：

```text
“把 Output Section 的 VMA 指定为对齐后的地址”
```

---

# 二十九、这一节最重要的认知

以后看到：

```ld
ALIGN(...)
```

不要马上认为：

> “这是给 section 对齐。”

先问：

```text
ALIGN 出现在哪里？
```

如果是：

```ld
.text ALIGN(16) :
```

它是在：

```text
Output Section Address
```

位置。

如果是：

```ld
.text :
{
    . = ALIGN(16);
}
```

它是在：

```text
修改 location counter
```

如果是：

```ld
foo = ALIGN(16);
```

它是在：

```text
计算一个值
```

这三个概念现在一定要分开。

---

# 三十、实验 06 最终检查命令

建议把下面这一组命令全部跑一遍：

```bash
gcc -c main.c -o main.o
gcc -c start.S -o start.o
gcc -c foo.S -o foo.o
```

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    foo.o \
    -o custom.elf \
    -Map=custom.map
```

然后：

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
objdump -s -j .foo custom.elf
```

```bash
nm -n custom.elf
```

```bash
grep -A 20 -B 5 "\.foo" custom.map
```

最后运行：

```bash
./custom.elf
echo $?
```

---

# 三十一、下一实验：`SUBALIGN`——真正进入“输入 Section 排列”

下一节就可以顺着今天的 `ALIGN` 往下走：

# 实验 07：`SUBALIGN()` 与 input section 对齐

我们会制造：

```text
foo1.o
foo2.o
foo3.o
```

每个都有：

```text
.foo
```

然后：

```ld
.foo :
{
    *(.foo)
}
```

观察：

```text
foo1
padding
foo2
padding
foo3
```

再使用：

```ld
SUBALIGN(1)
```

观察 linker 如何改变**输入 section 之间的对齐**。

最后会把：

```text
ALIGN
SUBALIGN
ALIGNOF
```

和：

```text
*(.text)
*(.foo)
KEEP(*(.foo))
SORT(...)
```

串起来。

这一步之后，就开始真正进入 GNU ld `SECTIONS` 命令中非常核心的 **Input Section Description / wildcard / section sorting / garbage collection** 世界了。

[1]: https://sourceware.org/binutils/docs/ld.pdf?utm_source=chatgpt.com "The GNU linker"
[2]: https://www.sourceware.org/binutils/docs/ld.pdf?utm_source=chatgpt.com "The GNU linker"

