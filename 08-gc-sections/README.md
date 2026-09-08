# GNU ld 实战课程 · 实验 08

## `--gc-sections` + `KEEP()`：亲手抓住被 linker 删除的代码

上一节我们已经进入：

```text
SECTIONS
 ├── Output Section
 │    ├── ALIGN
 │    ├── SUBALIGN
 │    └── Input Section
 │
 └── *(.foo)
```

今天再向前走一步，进入实际工程里非常常见的 linker 优化：

```text
--gc-sections
```

它解决的问题是：

> **程序里有大量没有使用的函数、变量、表项时，linker 能不能自动把它们从最终 ELF 中删除？**

答案是：可以。

但马上会出现一个很有意思的问题：

> **有些东西虽然没有普通的 C 引用，但我们就是需要它，怎么办？**

答案：

```ld
KEEP(*(.xxx))
```

所以今天的核心关系是：

```text
--gc-sections
       │
       ▼
删除未使用 Input Section
       │
       ├── 正常函数 → 删除
       │
       ├── 正常变量 → 删除
       │
       └── 特殊注册表 → 可能也被删除
                              │
                              ▼
                           KEEP()
                              │
                              ▼
                           保留下来
```

---

# 一、今天实验最终要看到什么？

我们故意创建：

```text
main()
used_function()
unused_function()
```

以及一个特殊表：

```text
.mytable
```

最终观察：

```text
没有 --gc-sections：

main
used_function
unused_function
.mytable
```

开启：

```text
--gc-sections
```

可能变成：

```text
main
used_function

unused_function  ← 删除
.mytable         ← 也可能删除
```

然后：

```ld
KEEP(*(.mytable))
```

再次链接：

```text
main
used_function
.mytable         ← 救回来了
```

这次一定要使用：

```bash
--print-gc-sections
```

让 linker **亲口告诉我们删了什么**。

---

# 二、先理解 `--gc-sections` 到底在干什么

这里的 `gc` 是：

```text
Garbage Collection
```

可以把 linker 想象成一个垃圾回收器：

```text
                   ELF roots
                      │
                      ▼
                    main
                      │
               ┌──────┴──────┐
               ▼             ▼
          used_function    global_data
               │
               ▼
             ...
```

如果某个 Input Section：

```text
没有任何可达引用
```

那么：

```text
unreachable
      ↓
garbage
      ↓
删除
```

但这里有一个特别重要的细节：

> `--gc-sections` 回收的基本单位不是“一个函数的几条指令”，而通常是 **Input Section**。

所以为了让 linker 能精确删除函数，我们必须先把函数拆成独立 section。

---

# 三、第一步：`-ffunction-sections`

创建：

```text
ld-lab/
├── main.c
├── start.S
└── linker.ld
```

---

# 四、main.c

写：

```c
static int used_function(void)
{
    return 40;
}

static int unused_function(void)
{
    return 1000;
}

int main(void)
{
    return used_function() + 2;
}
```

这里：

```text
main()
   │
   ▼
used_function()
```

但是：

```text
unused_function()
```

没有任何调用者。

---

# 五、先正常编译

执行：

```bash
gcc -c \
    -ffunction-sections \
    -fdata-sections \
    main.c \
    -o main.o
```

然后：

```bash
objdump -h main.o
```

重点观察 `.text`。

正常情况下，如果没有：

```bash
-ffunction-sections
```

可能是：

```text
.text
    ├── main
    ├── used_function
    └── unused_function
```

而现在使用：

```bash
-ffunction-sections
```

会得到类似：

```text
.text.main
.text.used_function
.text.unused_function
```

这一步是整个实验的关键。

---

# 六、为什么必须拆成多个 Input Section？

假设：

```text
.text
```

里面同时有：

```text
main
used_function
unused_function
```

linker 如果把整个 `.text` 当成一个 Input Section：

```text
.text
└── main
└── used_function
└── unused_function
```

那么：

```text
unused_function
```

虽然没用，但 linker 很难只删除其中一小段。

而：

```bash
-ffunction-sections
```

让编译器变成：

```text
.text.main
.text.used_function
.text.unused_function
```

于是 linker 可以：

```text
.text.main
      ↓
保留

.text.used_function
      ↓
保留

.text.unused_function
      ↓
删除
```

这就是：

```text
Function
   ↓
独立 Input Section
   ↓
GC 可以精确处理
```

---

# 七、start.S

继续：

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

# 八、第一版 linker.ld

这次我们故意使用通配符：

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
        _stext = .;

        *(.text)
        *(.text.*)

        _etext = .;
    } > ROM :text
}
```

这里：

```ld
*(.text)
```

匹配：

```text
.text
```

而：

```ld
*(.text.*)
```

匹配：

```text
.text.main
.text.used_function
.text.unused_function
```

所以现在所有函数都进入：

```text
.text
```

Output Section。

---

# 九、第一次链接：不启用 GC

编译：

```bash
gcc -c \
    -ffunction-sections \
    -fdata-sections \
    main.c \
    -o main.o

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

# 十、验证三个函数

```bash
nm -n normal.elf
```

搜索：

```bash
nm -n normal.elf | grep function
```

应该能看到：

```text
used_function
unused_function
```

再：

```bash
objdump -d normal.elf
```

寻找：

```text
<main>
<used_function>
<unused_function>
```

正常情况下三个都存在。

---

# 十一、看 map

```bash
grep -A 30 -B 5 "\.text" normal.map
```

你应该看到类似：

```text
.text
    ...
    main.o
        .text.used_function
        .text.unused_function
        .text.main
```

这里注意一个重要区别：

```text
.text
```

是：

> **Output Section**

而：

```text
.text.main
.text.used_function
.text.unused_function
```

是：

> **Input Section**

这正好把前面的课程串起来了。

---

# 十二、现在开启 `--gc-sections`

执行：

```bash
ld \
    -T linker.ld \
    --gc-sections \
    --print-gc-sections \
    start.o \
    main.o \
    -o gc.elf \
    -Map=gc.map
```

这次重点看终端输出。

应该出现类似：

```text
removing unused section '.text.unused_function' in file 'main.o'
```

具体文字可能因 GNU binutils 版本有所不同，但核心应该是：

```text
.text.unused_function
```

被删除。

---

# 十三、再看 nm

```bash
nm -n gc.elf
```

然后：

```bash
nm -n gc.elf | grep function
```

现在应该只剩：

```text
used_function
```

而：

```text
unused_function
```

消失。

---

# 十四、反汇编再次验证

```bash
objdump -d gc.elf
```

你会看到：

```text
<main>
<used_function>
```

但是找不到：

```text
<unused_function>
```

所以我们已经完成了第一轮闭环：

```text
-ffunction-sections
        ↓
.text.unused_function
        ↓
--gc-sections
        ↓
没有引用
        ↓
删除
```

---

# 十五、为什么 `used_function` 没被删除？

因为：

```c
int main(void)
{
    return used_function() + 2;
}
```

编译器生成了：

```text
main
  │
  │ relocation
  ▼
.text.used_function
```

于是 linker 可以构建出：

```text
main
 │
 └── used_function
```

这是一棵“可达图”。

---

# 十六、把 linker GC 想象成一棵图

```text
             _start
                │
                ▼
              main
                │
                ▼
        used_function


      unused_function
             ↑
          没有边
             │
             ▼
           删除
```

实际上 `_start → main` 也是通过 relocation 建立的。

所以 linker 的核心思想可以粗略理解为：

```text
root
 ↓
跟着 relocation 走
 ↓
找到可达 Input Section
 ↓
保留

不可达
 ↓
删除
```

---

# 十七、现在进入真正有意思的部分：自定义表

实际嵌入式工程里经常有这种设计：

```c
struct command {
    const char *name;
    int (*handler)(void);
};
```

然后不同模块自己注册：

```text
命令 A
命令 B
命令 C
```

linker 把它们集中到：

```text
.command_table
```

启动时程序遍历：

```text
command_start
      ↓
command A
command B
command C
      ↓
command_end
```

问题：

> 这些表项可能没有普通的 C 代码引用。

于是：

```text
--gc-sections
```

可能把它们当成垃圾。

这就是 `KEEP()` 登场的地方。

---

# 十八、创建 `commands.c`

增加：

```text
commands.c
```

内容：

```c
struct command
{
    const char *name;
    int (*handler)(void);
};

static int command_hello(void)
{
    return 10;
}

static const struct command hello_command
    __attribute__((section(".command_table")))
    = {
        "hello",
        command_hello
    };
```

注意：

```c
__attribute__((section(".command_table")))
```

告诉 GCC：

> 把这个变量放进 `.command_table` Input Section。

---

# 十九、编译 commands.c

```bash
gcc -c \
    -ffunction-sections \
    -fdata-sections \
    commands.c \
    -o commands.o
```

查看：

```bash
objdump -h commands.o
```

应该看到：

```text
.command_table
```

同时：

```text
.text.command_hello
```

也应该存在。

---

# 二十、把 `.command_table` 加进 linker script

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
        _stext = .;

        *(.text)
        *(.text.*)

        _etext = .;
    } > ROM :text

    .command_table :
    {
        command_start = .;

        *(.command_table)

        command_end = .;
    } > ROM :text
}
```

---

# 二十一、不要 KEEP，先看看会发生什么

链接：

```bash
ld \
    -T linker.ld \
    --gc-sections \
    --print-gc-sections \
    start.o \
    main.o \
    commands.o \
    -o command-gc.elf \
    -Map=command-gc.map
```

你很可能看到：

```text
removing unused section '.command_table'
```

甚至：

```text
.text.command_hello
```

也可能被回收。

原因很简单：

```text
main
 │
 └── 没有引用 command_table

command_table
 │
 └── 没有被任何 root 引用
```

于是：

```text
GC
 ↓
删除
```

---

# 二十二、验证

执行：

```bash
nm -n command-gc.elf
```

然后：

```bash
readelf -S command-gc.elf
```

搜索：

```bash
readelf -S command-gc.elf | grep command
```

很可能：

```text
没有 .command_table
```

再：

```bash
objdump -d command-gc.elf
```

检查：

```text
command_hello
```

也可能消失。

---

# 二十三、现在使用 `KEEP()`

修改 linker script：

```ld
.command_table :
{
    command_start = .;

    KEEP(*(.command_table))

    command_end = .;
} > ROM :text
```

这就是：

```ld
KEEP(*(.command_table))
```

它告诉 linker：

> **即使垃圾回收认为 `.command_table` 没有被引用，也必须保留。**

---

# 二十四、重新链接

```bash
ld \
    -T linker.ld \
    --gc-sections \
    --print-gc-sections \
    start.o \
    main.o \
    commands.o \
    -o command-keep.elf \
    -Map=command-keep.map
```

这次：

```text
.command_table
```

应该不会被 GC 删除。

---

# 二十五、验证 Section

```bash
readelf -S command-keep.elf | grep command
```

应该看到：

```text
.command_table
```

---

# 二十六、验证 Symbol

执行：

```bash
nm -n command-keep.elf | grep command
```

应该能看到：

```text
command_start
command_end
```

而且：

```text
command_end - command_start
```

就是表的大小。

---

# 二十七、验证实际数据

执行：

```bash
objdump -s -j .command_table command-keep.elf
```

你应该看到 `.command_table` 中存在实际数据。

注意这里的数据不一定直接显示：

```text
hello
```

因为：

```c
"hello"
```

和：

```c
command_hello
```

都涉及地址。

最终可能看到的是：

```text
一些地址值
```

这正好可以继续用：

```bash
readelf -r commands.o
```

观察 relocation。

---

# 二十八、看 commands.o 的 relocation

执行：

```bash
readelf -r commands.o
```

或者：

```bash
objdump -dr commands.o
```

你会看到 `.command_table` 中存在对：

```text
hello
command_hello
```

等符号的 relocation。

于是：

```text
command_table
       │
       ├── name → "hello"
       │
       └── handler → command_hello
```

形成了：

```text
command_table
      │
      ├─────────────┐
      ▼             ▼
    string      command_hello
```

这也是为什么实际工程里：

```text
KEEP(.command_table)
```

往往不仅保护表本身，还会间接让 linker 保留表所引用的相关内容。

---

# 二十九、比较三个 ELF

现在我们有：

```text
normal.elf
gc.elf
command-gc.elf
command-keep.elf
```

建议分别执行：

```bash
size normal.elf
size gc.elf
size command-gc.elf
size command-keep.elf
```

重点观察：

```text
text
data
bss
```

通常：

```text
gc.elf
```

会比：

```text
normal.elf
```

更小。

而：

```text
command-keep.elf
```

会比：

```text
command-gc.elf
```

重新多出 `.command_table` 以及它需要保留的相关内容。

---

# 三十、用 `size` 做第一轮量化

例如：

```text
normal.elf

text = 100
```

开启 GC：

```text
gc.elf

text = 70
```

意味着：

```text
30 bytes
```

被回收。

这就是：

```text
--gc-sections
```

最直接的工程收益：

```text
Flash
 ↓
减少
```

对于 MCU 固件非常重要。

---

# 三十一、map 文件是今天的最终证据

先看：

```bash
grep -A 30 -B 5 "\.text" normal.map
```

然后：

```bash
grep -A 30 -B 5 "\.text" gc.map
```

你会看到：

```text
normal.map

.text
    .text.main
    .text.used_function
    .text.unused_function
```

而：

```text
gc.map

.text
    .text.main
    .text.used_function
```

`unused_function` 不见了。

---

# 三十二、看 GC 的专门信息

使用：

```bash
grep -i "unused section\|removing" gc.map
```

不过最可靠的直接证据还是链接时：

```bash
--print-gc-sections
```

例如：

```bash
ld \
    -T linker.ld \
    --gc-sections \
    --print-gc-sections \
    ...
```

终端会列出 linker 回收的 section。

所以今天我们有四种证据：

```text
                --gc-sections
                     │
       ┌─────────────┼─────────────┐
       ▼             ▼             ▼
     nm           objdump       readelf
       │             │             │
   symbol消失     机器码消失     section消失
                     │
                     ▼
                  map 文件
                     │
                     ▼
                链接布局变化
```

---

# 三十三、一个非常重要的概念：`KEEP()` 保护的是 Input Section

例如：

```ld
KEEP(*(.command_table))
```

匹配：

```text
commands1.o:.command_table
commands2.o:.command_table
commands3.o:.command_table
```

所以最终：

```text
.command_table
│
├── commands1.o
├── commands2.o
└── commands3.o
```

全部得到保护。

如果你写：

```ld
KEEP(commands.o(.command_table))
```

则只保护：

```text
commands.o
```

中的 `.command_table`。

因此：

```ld
KEEP(*(.command_table))
```

是非常常见的工程写法。

---

# 三十四、为什么不直接禁用 GC？

当然可以：

```bash
# 不使用 --gc-sections
```

但大型工程通常不会这么干。

例如：

```text
项目
├── 1000 个函数
├── 300 个驱动
├── 200 个协议
├── 100 个工具模块
└── ...
```

实际某个产品只需要：

```text
100 个函数
```

如果不 GC：

```text
所有东西
   ↓
进入 firmware
```

而：

```text
--gc-sections
```

可以：

```text
所有 Input Sections
       ↓
建立可达关系
       ↓
删除不用的
       ↓
生成更小 firmware
```

这也是现代嵌入式工程非常常见的：

```text
-ffunction-sections
-fdata-sections
--gc-sections
```

三件套。

---

# 三十五、`-fdata-sections` 也值得做一次

例如：

```c
int used_data = 10;

int unused_data = 999;
```

编译：

```bash
gcc -c \
    -ffunction-sections \
    -fdata-sections \
    main.c \
    -o main.o
```

查看：

```bash
objdump -h main.o
```

可能看到：

```text
.data.used_data
.data.unused_data
```

于是：

```text
--gc-sections
```

也能针对数据 Input Section 进行回收。

所以：

```text
-ffunction-sections
       ↓
函数拆分

-fdata-sections
       ↓
数据拆分

--gc-sections
       ↓
垃圾回收
```

---

# 三十六、这里必须注意一个坑

**`--gc-sections` 并不是简单地“删除所有没有被 C 代码调用的东西”。**

它分析的是：

```text
Input Section
+
Symbol
+
Relocation
+
GC roots
```

因此某些东西即使没有普通的 C 调用，也可能因为：

```text
entry symbol
特殊 section
动态引用
KEEP
```

等原因成为保留对象。

所以不要把它机械理解成：

```text
没调用 = 一定删除
```

正确理解应该是：

```text
没有从 GC roots 可达
+
没有被 KEEP 等机制保护
+
满足回收条件
        ↓
可能被删除
```

---

# 三十七、今天的核心实验关系

把整个实验浓缩：

```text
main.c
 │
 ├── main
 │
 ├── used_function
 │
 └── unused_function
 │
 ▼
-ffunction-sections
 │
 ├── .text.main
 ├── .text.used_function
 └── .text.unused_function
 │
 ▼
--gc-sections
 │
 ├── main          ← 保留
 ├── used_function ← 保留
 └── unused        ← 删除
```

然后：

```text
.command_table
       │
       ▼
--gc-sections
       │
       ▼
可能被删除
       │
       ▼
KEEP(*(.command_table))
       │
       ▼
强制保留
```

---

# 三十八、现在把前 8 个实验串起来

到目前为止，路线已经非常完整：

```text
实验 01
.o → ELF
│
├── Section
├── Symbol
└── Relocation

实验 02
-T linker.ld
│
└── SECTIONS
      ↓
   控制地址

实验 03
MEMORY
│
├── ROM
└── RAM
      ↓
VMA / LMA

实验 04
LOADADDR / ADDR / SIZEOF
      ↓
.data copy
.bss zero

实验 05
PHDRS
      ↓
Section → Segment

实验 06
ALIGN
      ↓
地址计算
padding

实验 07
SUBALIGN
      ↓
Input Section 排列

实验 08
--gc-sections
      ↓
Input Section 回收
      ↓
KEEP()
      ↓
强制保留
```

---

# 三十九、下一实验：`PROVIDE()` / linker symbols

下一关进入 linker script 的另一个核心能力：

# 实验 09：`PROVIDE`、`PROVIDE_HIDDEN` 与 linker symbol

我们会做这样的实验：

```ld
PROVIDE(__stack_top = ORIGIN(RAM) + LENGTH(RAM));
```

然后在 C/汇编里使用：

```text
__stack_top
```

同时比较：

```ld
foo = .;
PROVIDE(foo = .);
PROVIDE_HIDDEN(foo = .);
```

然后用：

```bash
nm
readelf -s
objdump -t
```

观察三种 symbol 的区别。

最终会建立：

```text
普通 C symbol
      │
      ├── global
      ├── local
      └── weak

linker script symbol
      │
      ├── foo = .
      ├── PROVIDE(foo = .)
      └── PROVIDE_HIDDEN(foo = .)
```

并进一步解释一个非常容易踩坑的问题：

> **为什么 linker script 里写了一个 symbol，但 `nm` 有时候看得到，有时候看不到？**

再往后就会进入：

```text
实验 10  PROVIDE / symbol visibility
实验 11  `. = . + SIZEOF(...)`
实验 12  `ORIGIN()` / `LENGTH()` 自动计算内存边界
实验 13  Archive `.a` 的成员提取
实验 14  `--start-group / --end-group`
实验 15  weak / strong / COMMON 符号解析
```

到这里，GNU `ld` 的学习路线就会从“**控制 section**”逐渐进入“**控制整个链接过程**”了。

