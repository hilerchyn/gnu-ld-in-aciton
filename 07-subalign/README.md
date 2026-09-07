# GNU ld 实战课程 · 实验 07

## `SUBALIGN()`：控制多个 Input Section 在 Output Section 中的排列

上一节我们把 `ALIGN()` 的三个概念拆开了。这一节继续沿着 `SECTIONS` → Input Section 的路线深入：

```text
实验 06
ALIGN()
  ↓
Output Section 地址 / location counter
  ↓
padding

实验 07
SUBALIGN()
  ↓
Input Section 对齐
  ↓
多个 .foo 如何排列
```

这一步非常重要，因为以后看到：

```ld
*(.text)
*(.rodata)
*(.init_array)
*(.foo)
```

你不能只想：

> “把这些东西拼起来。”

还要问：

> **每一个 Input Section 自己要求什么 alignment？linker 在把它们拼进 Output Section 时，是否保留这个 alignment？**

GNU ld 的 Output Section 描述语法本身就提供了 `SUBALIGN(subsection_align)`，用于控制其中 Input Section 的对齐方式。([源代码网][1])

---

# 一、今天要解决的问题

假设有三个 `.foo`：

```text
foo1.o
└── .foo

foo2.o
└── .foo

foo3.o
└── .foo
```

正常情况下：

```ld
.foo :
{
    *(.foo)
}
```

linker 会根据各个 Input Section 自身的 alignment 要求进行排列。

可能形成：

```text
.foo Output Section

0x400000
├── foo1.o:.foo
│
├── padding
│
├── foo2.o:.foo
│
├── padding
│
└── foo3.o:.foo
```

而：

```ld
.foo : SUBALIGN(1)
{
    *(.foo)
}
```

则告诉 linker：

> **把 `.foo` 中各个 Input Section 的 alignment 降到 1。**

于是可能变成：

```text
.foo

foo1
foo2
foo3
```

不再因为 Input Section 自身 alignment 而插入额外 padding。

---

# 二、先搞清楚 ALIGN 和 SUBALIGN 的层次

这是今天最关键的概念。

```text
                    Output Section
                         │
                         │
             ┌───────────┴───────────┐
             │                       │
             ▼                       ▼
       Output Section           Input Sections
          alignment              alignment
             │                       │
             ▼                       ▼
          ALIGN()                 SUBALIGN()
```

也就是说：

```text
ALIGN
    ↓
Output Section / 当前地址

SUBALIGN
    ↓
Output Section 内部
各 Input Section 之间的排列
```

可以简单记：

```text
ALIGN    → “这个大盒子怎么对齐”
SUBALIGN → “盒子里面的小东西怎么对齐”
```

---

# 三、实验目录

今天增加三个汇编文件：

```text
ld-lab/
├── main.c
├── start.S
├── foo1.S
├── foo2.S
├── foo3.S
└── linker.ld
```

---

# 四、main.c

保持简单：

```c
int main(void)
{
    return 42;
}
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

# 六、制造三个不同 alignment 的 Input Section

这里是本实验的核心。

## foo1.S

```asm
.section .foo,"a",@progbits
.p2align 2

foo1_begin:
    .byte 0x11
    .byte 0x12
    .byte 0x13
    .byte 0x14

foo1_end:
```

这里：

```asm
.p2align 2
```

表示：

```text
2^2 = 4
```

所以：

```text
.foo
alignment = 4
```

---

# 七、foo2.S

```asm
.section .foo,"a",@progbits
.p2align 4

foo2_begin:
    .byte 0x21
    .byte 0x22
    .byte 0x23
    .byte 0x24

foo2_end:
```

这里：

```text
2^4 = 16
```

因此：

```text
.foo
alignment = 16
```

---

# 八、foo3.S

```asm
.section .foo,"a",@progbits
.p2align 5

foo3_begin:
    .byte 0x31
    .byte 0x32
    .byte 0x33
    .byte 0x34

foo3_end:
```

所以：

```text
alignment = 32
```

现在三个 `.o`：

```text
foo1.o
    .foo align 4

foo2.o
    .foo align 16

foo3.o
    .foo align 32
```

这就是我们想制造的实验环境。

---

# 九、先不要链接，观察 Input Section

编译：

```bash
gcc -c foo1.S -o foo1.o
gcc -c foo2.S -o foo2.o
gcc -c foo3.S -o foo3.o
```

然后：

```bash
objdump -h foo1.o
```

再：

```bash
objdump -h foo2.o
```

再：

```bash
objdump -h foo3.o
```

重点观察：

```text
Align
```

你应该得到类似：

```text
foo1.o

.foo
Size: ...
Align: 2**2


foo2.o

.foo
Size: ...
Align: 2**4


foo3.o

.foo
Size: ...
Align: 2**5
```

这里一定注意：

```text
2**2 = 4
2**4 = 16
2**5 = 32
```

所以现在 linker 面对的是：

```text
foo1 → align 4
foo2 → align 16
foo3 → align 32
```

---

# 十、建立第一版 linker.ld

先**不要使用 `SUBALIGN`**。

```ld
ENTRY(_start)

MEMORY
{
    ROM (rx) : ORIGIN = 0x00400000, LENGTH = 64K
}

PHDRS
{
    text PT_LOAD FLAGS(5);
}

SECTIONS
{
    .text :
    {
        *(.text)
    } > ROM :text

    .foo :
    {
        foo_start = .;

        *(.foo)

        foo_end = .;
    } > ROM :text
}
```

---

# 十一、编译 main/start

```bash
gcc -c main.c -o main.o
gcc -c start.S -o start.o
```

然后链接：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    foo1.o \
    foo2.o \
    foo3.o \
    -o normal.elf \
    -Map=normal.map
```

---

# 十二、第一次观察

执行：

```bash
objdump -h normal.elf
```

然后：

```bash
nm -n normal.elf
```

以及：

```bash
objdump -s -j .foo normal.elf
```

最后：

```bash
grep -A 30 -B 5 "\.foo" normal.map
```

---

# 十三、Map 文件才是今天最值得看的东西

打开：

```bash
less normal.map
```

寻找：

```text
.foo
```

你应该看到类似：

```text
.foo
                0x00000000004000xx
                foo_start = .

 *(.foo)

 .foo
                0x00000000004000xx        0x4 foo1.o

 .foo
                0x00000000004000xx        0x4 foo2.o

 .foo
                0x00000000004000xx        0x4 foo3.o

                foo_end = .
```

真正需要观察的是：

```text
foo1.o
foo2.o
foo3.o
```

之间有没有空洞。

---

# 十四、为什么会有 padding？

假设：

```text
foo1.o:.foo
地址 = 0x400100
大小 = 4
```

结束：

```text
0x400104
```

接下来：

```text
foo2.o:.foo
alignment = 16
```

所以 linker 不能直接放：

```text
0x400104
```

而必须向上对齐：

```text
0x400110
```

于是：

```text
0x400104
   │
   ├── padding
   │
   ▼
0x400110
   │
   └── foo2
```

然后 foo2：

```text
0x400110
+
4
=
0x400114
```

foo3 要求：

```text
alignment = 32
```

所以：

```text
0x400114
   ↓
ALIGN(32)
   ↓
0x400120
```

最终：

```text
foo1
    4 bytes

padding

foo2
    4 bytes

padding

foo3
    4 bytes
```

---

# 十五、现在使用 `SUBALIGN(1)`

把：

```ld
.foo :
{
    foo_start = .;

    *(.foo)

    foo_end = .;
} > ROM :text
```

修改为：

```ld
.foo :
SUBALIGN(1)
{
    foo_start = .;

    *(.foo)

    foo_end = .;
} > ROM :text
```

这里专门采用我们这次课程要强调的 Output Section 描述形式：

```ld
section :
SUBALIGN(...)
{
    ...
}
```

GNU ld 的完整 Output Section 描述语法中，`SUBALIGN(subsection_align)` 就位于 section 地址、`AT`、`ALIGN` 等属性之后、section 内容 `{ ... }` 之前。([源代码网][1])

---

# 十六、重新链接

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    foo1.o \
    foo2.o \
    foo3.o \
    -o subalign.elf \
    -Map=subalign.map
```

然后：

```bash
objdump -h subalign.elf
```

以及：

```bash
nm -n subalign.elf
```

再：

```bash
grep -A 30 -B 5 "\.foo" subalign.map
```

---

# 十七、现在比较两个 map

我们有：

```text
normal.map
subalign.map
```

比较：

```bash
diff -u normal.map subalign.map
```

或者：

```bash
grep -A 20 -B 3 "\.foo" normal.map
```

和：

```bash
grep -A 20 -B 3 "\.foo" subalign.map
```

你应该看到一个非常明显的变化：

```text
正常：

foo1
padding
foo2
padding
foo3
```

而：

```text
SUBALIGN(1)：

foo1
foo2
foo3
```

---

# 十八、用 `objdump -s` 看实际字节

执行：

```bash
objdump -s -j .foo normal.elf
```

以及：

```bash
objdump -s -j .foo subalign.elf
```

正常版本可能类似：

```text
11 12 13 14
00 00 00 ...
21 22 23 24
00 00 ...
31 32 33 34
```

而 `SUBALIGN(1)`：

```text
11 12 13 14
21 22 23 24
31 32 33 34
```

这里你就真正看到了：

> **linker 为 Input Section alignment 插入的 padding。**

---

# 十九、非常重要：`SUBALIGN(1)` 不等于 Output Section 按 1 字节对齐

这是非常容易犯的错误。

看：

```ld
.foo :
SUBALIGN(1)
{
    *(.foo)
}
```

它的意思不是：

```text
.foo Output Section alignment = 1
```

而是：

```text
Output Section
    │
    ├── foo1 input section
    ├── foo2 input section
    └── foo3 input section

SUBALIGN(1)
    ↓
控制这些 Input Section 的排列 alignment
```

所以：

```text
Output Section alignment
```

和：

```text
Input Section alignment
```

是两个层次。

---

# 二十、这和上一节的 ALIGN 正好对应

现在可以形成：

```text
                 SECTIONS
                    │
                    ▼
              Output Section
                    │
          ┌─────────┴─────────┐
          │                   │
          ▼                   ▼
       ALIGN              SUBALIGN
          │                   │
          │                   │
          ▼                   ▼
 Output Section          Input Sections
    alignment               alignment
```

简单记忆：

```text
ALIGN
↓
大盒子

SUBALIGN
↓
盒子里面的小盒子
```

---

# 二十一、实验 07-2：`SUBALIGN(4)`

不要只实验：

```ld
SUBALIGN(1)
```

继续试：

```ld
.foo :
SUBALIGN(4)
{
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
    foo1.o \
    foo2.o \
    foo3.o \
    -o subalign4.elf \
    -Map=subalign4.map
```

现在：

```text
foo1 → 4
foo2 → 4
foo3 → 4
```

即：

```text
SUBALIGN(4)
```

强制这些 Input Section 按 4 字节对齐。

所以：

```text
foo1
padding to 4
foo2
padding to 4
foo3
```

不会再要求：

```text
foo2 → 16
foo3 → 32
```

---

# 二十二、实验 07-3：`SUBALIGN(16)`

再试：

```ld
.foo :
SUBALIGN(16)
{
    foo_start = .;

    *(.foo)

    foo_end = .;
} > ROM :text
```

现在：

```text
foo1
   ↓
16-byte boundary

foo2
   ↓
16-byte boundary

foo3
   ↓
16-byte boundary
```

所以：

```text
SUBALIGN(16)
```

会比：

```text
SUBALIGN(1)
```

产生更多 padding。

---

# 二十三、把三个结果放在一起

| linker script  | Input Section 排列 |
| -------------- | ---------------- |
| 无 `SUBALIGN`   | 使用各自 alignment   |
| `SUBALIGN(1)`  | 全部按 1 对齐         |
| `SUBALIGN(4)`  | 全部按 4 对齐         |
| `SUBALIGN(16)` | 全部按 16 对齐        |

可以理解成：

```text
无 SUBALIGN

foo1 → 4
foo2 → 16
foo3 → 32
```

而：

```text
SUBALIGN(1)

foo1 → 1
foo2 → 1
foo3 → 1
```

---

# 二十四、再做一个非常重要的实验：Output Section 自身的 ALIGN

现在：

```ld
.foo :
SUBALIGN(1)
{
    *(.foo)
}
```

改成：

```ld
.foo :
ALIGN(16)
SUBALIGN(1)
{
    foo_start = .;

    *(.foo)

    foo_end = .;
} > ROM :text
```

注意这里：

```ld
ALIGN(16)
```

和：

```ld
SUBALIGN(1)
```

同时出现。

它们控制两个不同层次：

```text
.foo Output Section
       │
       │ ALIGN(16)
       ▼
Output Section 起始地址

       │
       ├── foo1
       ├── foo2
       └── foo3
             ↑
             SUBALIGN(1)
```

这正好把上一节和本节连接起来。

GNU ld 的 Output Section 语法中，`ALIGN(section_align)` 和 `SUBALIGN(subsection_align)` 是两个独立的 section 属性。([源代码网][1])

---

# 二十五、推荐你做这个组合实验

最终：

```ld
.foo :
ALIGN(16)
SUBALIGN(1)
{
    foo_start = .;

    *(.foo)

    foo_end = .;
} > ROM :text
```

观察：

```bash
objdump -h custom.elf
```

以及：

```bash
nm -n custom.elf
```

然后 map：

```bash
grep -A 30 -B 5 "\.foo" custom.map
```

最终你应该看到：

```text
Output Section
    ↓
从 16-byte boundary 开始

foo1
foo2
foo3
    ↓
内部按照 1-byte alignment 排列
```

所以：

```text
ALIGN
```

解决：

```text
“Output Section 从哪里开始？”
```

而：

```text
SUBALIGN
```

解决：

```text
“Input Section 在里面怎么排？”
```

---

# 二十六、`SUBALIGN` 的实际应用场景

这个命令并不是为了“炫 linker 技巧”。

它在实际工程里很有意义。

例如你有：

```text
100 个插件
```

每个插件产生：

```text
.plugin
```

并且每个 `.plugin` Input Section 因为编译器/汇编器原因有比较大的 alignment。

如果不控制：

```text
SUBALIGN
```

最终可能：

```text
插件 1
padding
插件 2
padding
插件 3
padding
...
```

大量浪费 Flash。

这时候可以设计：

```ld
.plugin :
SUBALIGN(4)
{
    __plugin_start = .;

    KEEP(*(.plugin))

    __plugin_end = .;
}
```

于是：

```text
Flash
│
├── plugin1
├── plugin2
├── plugin3
├── plugin4
└── ...
```

这在：

```text
固件
驱动表
注册表
插件系统
初始化表
协议描述表
```

等场景很常见。

---

# 二十七、这里提前埋一个伏笔：`KEEP()`

你可能已经注意到我刚才写：

```ld
KEEP(*(.plugin))
```

而不是：

```ld
*(.plugin)
```

这是故意的。

下一阶段我们会进入：

# 实验 08：`--gc-sections` + `KEEP()`

这是 linker script 中非常重要的一关。

例如：

```text
main.o
 ├── main()
 └── unused_function()

foo.o
 └── .mytable
```

编译：

```bash
gcc -ffunction-sections -fdata-sections -c main.c
```

链接：

```bash
ld --gc-sections ...
```

可能出现：

```text
unused_function
        ↓
删除

.mytable
        ↓
删除
```

即使：

```text
.mytable
```

是你设计好的“启动表”。

于是需要：

```ld
KEEP(*(.mytable))
```

告诉 linker：

> **即使垃圾回收认为它没人引用，也不能删除。**

GNU ld 的 `--gc-sections` 会依据符号和 relocation 关系确定哪些 input section 被使用；`KEEP()` 是 linker script 中用来保护 section、避免被垃圾回收的重要机制。([源代码网][2])

---

# 二十八、实验 07 最终形成的知识体系

到现在：

```text
SECTIONS
│
├── Output Section
│     │
│     ├── Address
│     │      └── ALIGN(...)
│     │
│     ├── Section content
│     │      └── . = ALIGN(...)
│     │
│     ├── Input Section alignment
│     │      └── SUBALIGN(...)
│     │
│     └── Input Section selection
│            └── *(.foo)
│
└── Program Header
       └── :text / :data
```

这已经开始接近真正的 linker script 设计了。

---

# 二十九、今天建议完整执行的命令

### 1. 编译

```bash
gcc -c main.c -o main.o
gcc -c start.S -o start.o

gcc -c foo1.S -o foo1.o
gcc -c foo2.S -o foo2.o
gcc -c foo3.S -o foo3.o
```

### 2. 看 Input Section

```bash
objdump -h foo1.o
objdump -h foo2.o
objdump -h foo3.o
```

### 3. 无 SUBALIGN

```bash
ld -T linker.ld \
   start.o main.o \
   foo1.o foo2.o foo3.o \
   -o normal.elf \
   -Map=normal.map
```

### 4. 有 SUBALIGN

```bash
ld -T linker.ld \
   start.o main.o \
   foo1.o foo2.o foo3.o \
   -o subalign.elf \
   -Map=subalign.map
```

### 5. 比较

```bash
objdump -h normal.elf
objdump -h subalign.elf
```

```bash
nm -n normal.elf
nm -n subalign.elf
```

```bash
objdump -s -j .foo normal.elf
objdump -s -j .foo subalign.elf
```

```bash
grep -A 30 -B 5 "\.foo" normal.map
grep -A 30 -B 5 "\.foo" subalign.map
```

---

# 三十、今天真正应该记住的四句话

```text
ALIGN()
    → Output Section / 地址对齐

. = ALIGN()
    → 修改 location counter

SUBALIGN()
    → 控制 Output Section 内 Input Section 的对齐

KEEP()
    → 下一节：阻止 --gc-sections 删除指定 Input Section
```

整个 `SECTIONS` 的思维方式现在可以升级成：

```text
                SECTIONS
                   │
                   ▼
            Output Section
                   │
       ┌───────────┼───────────┐
       │           │           │
       ▼           ▼           ▼
     地址        属性        内容
       │           │           │
    ALIGN       SUBALIGN     *(.foo)
       │           │           │
       └───────────┴───────────┘
                   │
                   ▼
                ELF
                   │
          ┌────────┴────────┐
          ▼                 ▼
      readelf -S         map file
```

**下一实验就是实验 08：`--gc-sections + KEEP()`。**这一关会非常有意思：我们故意制造“明明写进 ELF、却被 linker 删除”的函数和数据，然后用 `--print-gc-sections`、map、`readelf -S`、`nm`、`objdump` 五路证据把它抓出来，再用 `KEEP()` 把它救回来。

[1]: https://sourceware.org/binutils/docs/ld.pdf?utm_source=chatgpt.com "The GNU linker"
[2]: https://sourceware.org/binutils/docs-2.37/ld.pdf?utm_source=chatgpt.com "The GNU linker"

