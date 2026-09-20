# GNU ld 实战课程 · 实验 19

## `SORT()` / `KEEP()` / `EXCLUDE_FILE()`：精确控制 Input Section 的收集、排序与保留

上一节我们完成了：

```text
实验 16  OVERLAY
实验 17  ASSERT()
实验 18  PROVIDE() / DEFINED()
```

现在进入一个非常关键的阶段：

> **当几十、几百个 `.o` 文件都产生大量 Input Section 时，GNU ld 到底按照什么顺序把它们放进 Output Section？**

这会直接影响：

* 启动代码
* 中断向量表
* `.init_array`
* C/C++ 全局构造函数
* section garbage collection
* 固件布局
* Map 文件可读性
* 最终 Flash 地址

今天重点实验：

```text
SORT()
KEEP()
EXCLUDE_FILE()
```

最终把：

```text
很多 Input Section
        ↓
匹配
        ↓
过滤
        ↓
排序
        ↓
KEEP
        ↓
Output Section
```

彻底跑一遍。

---

# 一、先把 GNU ld 的两个 Section 概念再次钉死

我们前面已经反复使用：

```text
Input Section
```

例如：

```text
main.o
    .text
    .data
    .bss

foo.o
    .text
    .data

bar.o
    .text
```

这些都是：

> **Input Section**

linker script：

```ld
.text :
{
    *(.text)
}
```

产生：

```text
Output Section
```

所以：

```text
                 ld
                  │
      ┌───────────┼───────────┐
      ▼           ▼           ▼
    main.o      foo.o       bar.o
    .text       .text       .text
      │           │           │
      └───────────┼───────────┘
                  ▼
               .text
           Output Section
```

今天所有操作：

```text
SORT
KEEP
EXCLUDE_FILE
```

主要是在控制：

> **Input Section 如何进入 Output Section。**

---

# 二、实验 19-1：先观察默认顺序

建立：

```text
lab19/
├── main.c
├── foo.c
├── bar.c
├── baz.c
├── start.S
└── linker.ld
```

三个函数：

### foo.c

```c
__attribute__((section(".text.foo")))
void foo(void)
{
}
```

### bar.c

```c
__attribute__((section(".text.bar")))
void bar(void)
{
}
```

### baz.c

```c
__attribute__((section(".text.baz")))
void baz(void)
{
}
```

---

# 三、编译

```bash
gcc -ffreestanding -fno-pie -fno-stack-protector \
    -c foo.c -o foo.o

gcc -ffreestanding -fno-pie -fno-stack-protector \
    -c bar.c -o bar.o

gcc -ffreestanding -fno-pie -fno-stack-protector \
    -c baz.c -o baz.o
```

然后：

```bash
objdump -h foo.o
objdump -h bar.o
objdump -h baz.o
```

重点：

```text
.text.foo
.text.bar
.text.baz
```

---

# 四、linker script

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
}
```

这里：

```ld
*(.text.*)
```

会匹配：

```text
.text.foo
.text.bar
.text.baz
```

---

# 五、链接

注意输入文件顺序：

```bash
ld \
    -T linker.ld \
    start.o \
    foo.o \
    bar.o \
    baz.o \
    -o sort01.elf \
    -Map=sort01.map
```

---

# 六、第一次用 `objdump -d`

```bash
objdump -d sort01.elf
```

你会看到：

```text
00400000 <foo>:
...

0040000x <bar>:
...

0040001x <baz>:
...
```

具体地址取决于代码大小。

现在最重要的问题：

> **为什么是 foo → bar → baz？**

因为：

```ld
*(.text.*)
```

本身没有要求字母排序。

Input Section 的收集顺序受到输入文件和 linker 的处理顺序影响。

---

# 七、Map 文件验证

打开：

```bash
less sort01.map
```

找到：

```text
.text
```

你应该看到类似：

```text
.text
  0x00400000
  foo.o(.text.foo)
  0x00400000 foo

  bar.o(.text.bar)
  0x0040000a bar

  baz.o(.text.baz)
  0x00400014 baz
```

这里第一次真正观察：

```text
Map
 ↓
Input Section
 ↓
Output Section 内部顺序
```

---

# 八、实验 19-2：加入 `SORT()`

现在 linker script 改成：

```ld
SECTIONS
{
    .text :
    {
        *(SORT(.text.*))
        *(.text)
    } > ROM
}
```

重新链接：

```bash
ld \
    -T linker.ld \
    start.o \
    foo.o \
    bar.o \
    baz.o \
    -o sort02.elf \
    -Map=sort02.map
```

---

# 九、观察排序结果

执行：

```bash
objdump -d sort02.elf
```

以及：

```bash
grep -A 30 '^\.text' sort02.map
```

现在：

```text
.text.bar
.text.baz
.text.foo
```

会按照名称排序。

也就是：

```text
bar
baz
foo
```

这就是：

# `SORT()`

---

# 十、`SORT()` 到底排序什么？

这一点非常重要。

```ld
SORT(.text.*)
```

排序的是：

> **匹配到的 Input Section 名称。**

不是：

```text
函数名
```

也不是：

```text
符号名
```

例如：

```text
.text.zebra
.text.apple
.text.monkey
```

排序结果：

```text
.text.apple
.text.monkey
.text.zebra
```

即：

```text
Input Section name
```

决定排序。

---

# 十一、实验 19-3：故意制造更明显的顺序

修改：

```c
foo.c
```

```c
__attribute__((section(".text.300")))
void foo(void)
{
}
```

`bar.c`：

```c
__attribute__((section(".text.100")))
void bar(void)
{
}
```

`baz.c`：

```c
__attribute__((section(".text.200")))
void baz(void)
{
}
```

重新编译。

然后：

```bash
ld \
    -T linker.ld \
    start.o \
    foo.o \
    bar.o \
    baz.o \
    -o sort03.elf \
    -Map=sort03.map
```

---

# 十二、观察

如果：

```ld
SORT(.text.*)
```

那么排序：

```text
.text.100
.text.200
.text.300
```

对应：

```text
bar
baz
foo
```

这已经非常接近真实工程的：

```text
priority
```

思想。

---

# 十三、但是数字排序有一个坑

假设：

```text
.text.2
.text.10
.text.20
```

字符串排序可能是：

```text
.text.10
.text.2
.text.20
```

因为：

```text
"1" < "2"
```

而不是数学意义：

```text
2 < 10 < 20
```

所以工程中经常写成：

```text
.text.010
.text.020
.text.100
```

这种固定宽度命名。

---

# 十四、实验 19-4：`KEEP()`

现在进入非常重要的：

```ld
KEEP()
```

先启用：

```bash
-Wl,--gc-sections
```

不过由于我们直接使用 `ld`，可以先理解其等价思想：

```text
--gc-sections
```

要求 linker 删除没有被引用到的 section。

我们用：

```bash
gcc \
    -ffreestanding \
    -fno-pie \
    -fno-stack-protector \
    -ffunction-sections \
    -c foo.c \
    -o foo.o
```

其他文件同样。

---

# 十五、为什么需要 `--gc-sections`？

假设：

```text
main()
```

只调用：

```text
foo()
```

那么：

```text
bar()
baz()
```

没有任何引用。

如果每个函数都独立 section：

```text
.text.foo
.text.bar
.text.baz
```

linker 可以：

```text
保留 foo
删除 bar
删除 baz
```

这就是：

```text
section garbage collection
```

---

# 十六、先做一个真正的实验

`main.c`：

```c
extern void foo(void);

int main(void)
{
    foo();

    return 0;
}
```

然后：

```bash
gcc \
    -ffreestanding \
    -fno-pie \
    -fno-stack-protector \
    -ffunction-sections \
    -c main.c \
    -o main.o
```

---

# 十七、链接时打开 GC

```bash
ld \
    --gc-sections \
    -T linker.ld \
    start.o \
    main.o \
    foo.o \
    bar.o \
    baz.o \
    -o gc01.elf \
    -Map=gc01.map
```

然后：

```bash
nm gc01.elf
```

观察：

```text
foo
```

存在。

而：

```text
bar
baz
```

可能已经消失。

---

# 十八、Map 文件怎么看 GC？

这是一个非常值得养成的习惯。

搜索：

```bash
grep -n "Discarded input sections" gc01.map
```

你可能看到：

```text
Discarded input sections

.text.bar
.text.baz
```

这意味着：

```text
输入 section
      ↓
没有被保留
      ↓
GC
      ↓
Discarded
```

所以 Map 文件不只是看“最终有什么”。

还可以看：

> **linker 删除了什么。**

---

# 十九、现在使用 `KEEP()`

假设我们有：

```text
vector.o
```

其中：

```c
__attribute__((section(".isr_vector")))
void reset_handler(void)
{
}
```

这个 section 可能没有普通 C 代码引用。

但是：

> 它绝对不能被 GC 删除。

所以 linker：

```ld
.isr_vector :
{
    KEEP(*(.isr_vector))
} > ROM
```

这就是：

# `KEEP()`

---

# 二十、实验 19-5：真正做一个 Vector Table

`vector.c`：

```c
typedef void (*handler_t)(void);

void reset_handler(void)
{
}

void irq_handler(void)
{
}

__attribute__((section(".isr_vector")))
handler_t vector_table[] =
{
    reset_handler,
    irq_handler,
};
```

编译：

```bash
gcc \
    -ffreestanding \
    -fno-pie \
    -fno-stack-protector \
    -fdata-sections \
    -ffunction-sections \
    -c vector.c \
    -o vector.o
```

---

# 二十一、先不要 KEEP

linker：

```ld
SECTIONS
{
    .text :
    {
        *(.text)
        *(.text.*)
    } > ROM

    .isr_vector :
    {
        *(.isr_vector)
    } > ROM
}
```

链接：

```bash
ld \
    --gc-sections \
    -T linker.ld \
    start.o \
    main.o \
    vector.o \
    -o vector01.elf \
    -Map=vector01.map
```

然后：

```bash
nm vector01.elf
```

以及：

```bash
readelf -S vector01.elf
```

你可能发现：

```text
.isr_vector
```

已经被 GC 删除。

---

# 二十二、为什么？

因为 linker 的角度：

```text
.isr_vector
```

没有普通 relocation 链连接到它。

于是：

```text
GC root
    ↓
没有到 .isr_vector 的引用
    ↓
删除
```

但是 CPU 启动时可能通过硬件约定直接访问：

```text
Flash 起始地址
```

根本不存在一个普通 C：

```c
vector_table();
```

调用。

所以：

```text
程序逻辑上“没引用”
```

不等于：

```text
硬件上“不需要”
```

这就是 `KEEP()` 的价值。

---

# 二十三、加入 KEEP

修改：

```ld
.isr_vector :
{
    KEEP(*(.isr_vector))
} > ROM
```

重新：

```bash
ld \
    --gc-sections \
    -T linker.ld \
    start.o \
    main.o \
    vector.o \
    -o vector02.elf \
    -Map=vector02.map
```

然后：

```bash
readelf -S vector02.elf
```

应该重新看到：

```text
.isr_vector
```

---

# 二十四、用 `objdump -s` 看 Vector Table

```bash
objdump -s \
    --section=.isr_vector \
    vector02.elf
```

然后：

```bash
objdump -d vector02.elf
```

结合：

```bash
nm -n vector02.elf
```

你可以验证：

```text
vector_table
    ↓
reset_handler address
irq_handler address
```

确实已经进入最终 ELF。

---

# 二十五、`KEEP()` 最重要的理解

不要把：

```ld
KEEP(*(.isr_vector))
```

理解成：

> “保留 `.isr_vector` Output Section。”

更准确：

> **匹配到的 Input Section 不允许被 `--gc-sections` 丢弃。**

例如：

```ld
.isr_vector :
{
    KEEP(*(.isr_vector))
}
```

其中：

```text
*(.isr_vector)
```

是：

```text
匹配
```

而：

```text
KEEP(...)
```

是：

```text
防 GC
```

两者职责不同。

---

# 二十六、实验 19-6：`KEEP()` + `SORT()`

这两个可以组合。

例如：

```ld
.init_array :
{
    KEEP(*(SORT(.init_array.*)))
    KEEP(*(.init_array))
} > ROM
```

含义：

```text
.init_array.*
       ↓
SORT
       ↓
排序
       ↓
KEEP
       ↓
不能被 GC
```

这就是 GCC/C++ 全局构造函数布局中非常常见的思想。

---

# 二十七、先制造多个 init section

创建：

```text
init_a.c
init_b.c
init_c.c
```

例如：

```c
typedef void (*init_func)(void);

void init_a(void)
{
}

__attribute__((section(".init_array.300")))
init_func init_a_entry = init_a;
```

第二个：

```c
typedef void (*init_func)(void);

void init_b(void)
{
}

__attribute__((section(".init_array.100")))
init_func init_b_entry = init_b;
```

第三个：

```c
typedef void (*init_func)(void);

void init_c(void)
{
}

__attribute__((section(".init_array.200")))
init_func init_c_entry = init_c;
```

---

# 二十八、编译

```bash
gcc \
    -ffreestanding \
    -fno-pie \
    -fno-stack-protector \
    -fdata-sections \
    -ffunction-sections \
    -c init_a.c -o init_a.o

gcc \
    -ffreestanding \
    -fno-pie \
    -fno-stack-protector \
    -fdata-sections \
    -ffunction-sections \
    -c init_b.c -o init_b.o

gcc \
    -ffreestanding \
    -fno-pie \
    -fno-stack-protector \
    -fdata-sections \
    -ffunction-sections \
    -c init_c.c -o init_c.o
```

---

# 二十九、查看 Input Section

```bash
objdump -h init_a.o
```

你应该看到：

```text
.init_array.300
```

然后：

```bash
objdump -h init_b.o
```

：

```text
.init_array.100
```

以及：

```bash
objdump -h init_c.o
```

：

```text
.init_array.200
```

---

# 三十、linker script

```ld
SECTIONS
{
    .text :
    {
        *(.text)
        *(.text.*)
    } > ROM

    .init_array :
    {
        KEEP(*(SORT(.init_array.*)))
        KEEP(*(.init_array))
    } > ROM
}
```

---

# 三十一、链接

```bash
ld \
    --gc-sections \
    -T linker.ld \
    start.o \
    main.o \
    init_a.o \
    init_b.o \
    init_c.o \
    -o init-array.elf \
    -Map=init-array.map
```

---

# 三十二、Map 验证

```bash
grep -A 30 "\.init_array" init-array.map
```

重点观察：

```text
.init_array.100
.init_array.200
.init_array.300
```

应该按照：

```text
100
200
300
```

排序。

也就是：

```text
init_b
init_c
init_a
```

---

# 三十三、`SORT()` + `KEEP()` 的执行逻辑

可以画成：

```text
.init_array.*
       │
       ▼
    SORT()
       │
       ▼
100
200
300
       │
       ▼
    KEEP()
       │
       ▼
最终 Output Section
```

这就是：

```ld
KEEP(*(SORT(.init_array.*)))
```

为什么如此强大。

---

# 三十四、实验 19-7：`EXCLUDE_FILE()`

现在进入第三个核心功能。

假设：

```text
foo.o
bar.o
baz.o
```

全部都有：

```text
.text.foo
.text.bar
.text.baz
```

但我们希望：

```text
foo.o
```

里面的 `.text.*`：

> 不进入当前这个 Output Section。

可以写：

```ld
*(EXCLUDE_FILE (foo.o) .text.*)
```

于是：

```text
foo.o
    .text.foo
       ↓
    排除

bar.o
    .text.bar
       ↓
    收集

baz.o
    .text.baz
       ↓
    收集
```

---

# 三十五、实验 19-8：真正操作 `EXCLUDE_FILE`

linker：

```ld
SECTIONS
{
    .text :
    {
        *(EXCLUDE_FILE (foo.o) .text.*)
        *(.text)
    } > ROM

    .special_text :
    {
        foo.o(.text.*)
    } > ROM
}
```

这里形成：

```text
普通 .text
    ↓
除了 foo.o

.special_text
    ↓
专门收 foo.o
```

---

# 三十六、链接

```bash
ld \
    -T linker.ld \
    start.o \
    foo.o \
    bar.o \
    baz.o \
    -o exclude.elf \
    -Map=exclude.map
```

---

# 三十七、验证

```bash
readelf -S exclude.elf
```

应该看到：

```text
.text
.special_text
```

然后：

```bash
grep -A 30 "\.text" exclude.map
```

确认：

```text
.text
    bar.o(.text.bar)
    baz.o(.text.baz)
```

而：

```text
.special_text
    foo.o(.text.foo)
```

---

# 三十八、`EXCLUDE_FILE()` 的本质

普通：

```ld
*(.text.*)
```

意思：

```text
所有输入文件
    ↓
匹配 .text.*
```

而：

```ld
*(EXCLUDE_FILE(foo.o) .text.*)
```

意思：

```text
所有输入文件
    ↓
匹配 .text.*
    ↓
但是 foo.o 不要
```

所以：

```text
EXCLUDE_FILE
```

可以理解成：

# “按输入文件过滤 Input Section”。

---

# 三十九、`EXCLUDE_FILE()` 特别适合什么？

例如：

```text
startup.o
```

里面有：

```text
.text.startup
```

但你希望 startup 代码进入：

```text
.startup
```

而不是普通：

```text
.text
```

可以：

```ld
.text :
{
    *(EXCLUDE_FILE(startup.o) .text*)
}

.startup :
{
    startup.o(.text*)
}
```

于是：

```text
普通代码
    ↓
.text

startup.o
    ↓
.startup
```

---

# 四十、实验 19-9：三者组合

现在做今天最重要的 linker script：

```ld
SECTIONS
{
    .isr_vector :
    {
        KEEP(*(.isr_vector))
    } > ROM

    .startup :
    {
        startup.o(.text*)
    } > ROM

    .text :
    {
        *(EXCLUDE_FILE(startup.o) .text.*)
        *(.text)
    } > ROM

    .init_array :
    {
        KEEP(*(SORT(.init_array.*)))
        KEEP(*(.init_array))
    } > ROM
}
```

现在：

```text
.isr_vector
    KEEP

.startup
    EXCLUDE_FILE 对应逻辑

.text
    排除 startup.o
    收集普通代码

.init_array
    SORT
    KEEP
```

这已经是一个很像真实工程的 Section 管理框架。

---

# 四十一、现在把整个 Input Section 流程画出来

```text
                     .o files
                        │
          ┌─────────────┼──────────────┐
          ▼             ▼              ▼
       startup.o      foo.o          init.o
          │             │              │
          ▼             ▼              ▼
      .text.startup  .text.foo    .init_array.200
                        │
                        │
              ┌─────────┴─────────┐
              ▼                   ▼
       EXCLUDE_FILE            SORT
              │                   │
              ▼                   ▼
          .text              .init_array
              │                   │
              │                 KEEP
              │                   │
              └─────────┬─────────┘
                        ▼
                  Output Sections
```

---

# 四十二、实验 19-10：`SORT_BY_NAME()`

`SORT()` 可以进一步拆成更明确的形式：

```ld
SORT_BY_NAME(.text.*)
```

例如：

```ld
.text :
{
    SORT_BY_NAME(.text.*)
} > ROM
```

语义非常直观：

```text
按照 section name
排序
```

---

# 四十三、`SORT_BY_ALIGNMENT()`

假设：

```text
.text.a
alignment = 1

.text.b
alignment = 16

.text.c
alignment = 4096
```

可以：

```ld
SORT_BY_ALIGNMENT(.text.*)
```

让 linker 按：

```text
alignment
```

排序。

这在某些需要控制：

```text
对齐
填充
Flash 布局
```

的工程里很有价值。

---

# 四十四、为什么 Alignment 排序值得注意？

假设：

```text
Section A
alignment = 4096
```

如果前面地址没有对齐：

```text
0x401003
```

那么 linker 必须插入：

```text
padding
```

直到：

```text
0x402000
```

因此 section 的排列顺序不仅影响：

```text
地址
```

还可能影响：

```text
Flash padding
```

所以：

```text
SORT_BY_ALIGNMENT
```

可以用来优化某些布局。

---

# 四十五、实验 19-11：观察 padding

创建两个 section：

```c
__attribute__((section(".special.a"), aligned(4096)))
char a;

__attribute__((section(".special.b")))
char b;
```

然后：

```ld
.special :
{
    *(.special.*)
} > ROM
```

执行：

```bash
objdump -h special.elf
```

观察：

```text
VMA
Size
Align
```

再：

```bash
objdump -s special.elf
```

观察中间可能存在的大量 padding。

然后尝试：

```ld
.special :
{
    SORT_BY_ALIGNMENT(.special.*)
} > ROM
```

比较 Map 和最终 ELF。

---

# 四十六、实验 19-12：`SORT_BY_INIT_PRIORITY()`

对于：

```text
.init_array.N
```

还可以使用：

```ld
SORT_BY_INIT_PRIORITY(.init_array.*)
```

其目的就是：

> 根据初始化 priority 组织 `.init_array`。

例如：

```text
.init_array.100
.init_array.200
.init_array.300
```

按照初始化优先级排列。

典型写法可以是：

```ld
.init_array :
{
    KEEP(*(SORT_BY_INIT_PRIORITY(.init_array.*)))
    KEEP(*(.init_array))
} > ROM
```

---

# 四十七、为什么 `.init_array` 特别重要？

C++：

```cpp
GlobalObject object;
```

程序启动时：

```text
object constructor
```

必须执行。

编译器通常不会简单生成：

```text
main()
    ↓
constructor
```

而是把构造函数入口组织到：

```text
.init_array
```

最终启动代码：

```text
_start
   ↓
runtime initialization
   ↓
.init_array
   ↓
constructor
   ↓
main
```

所以：

```text
.init_array
```

实际上是：

> **编译器、linker、startup runtime 三者之间的桥梁。**

---

# 四十八、今天第一次真正看到“linker 决定执行顺序”

例如：

```text
.init_array.100
.init_array.200
.init_array.300
```

最终：

```text
100
 ↓
200
 ↓
300
```

就意味着启动阶段：

```text
constructor 100
       ↓
constructor 200
       ↓
constructor 300
```

所以 linker 不只是：

> “分配地址。”

它实际上还可以参与：

# **执行顺序的构造。**

---

# 四十九、实验 19-13：完整验证命令矩阵

以后做这类实验，建议固定执行：

### Input Section

```bash
objdump -h foo.o
objdump -h bar.o
objdump -h baz.o
```

### ELF Section

```bash
readelf -S final.elf
```

### Section 内容

```bash
objdump -s final.elf
```

### 反汇编

```bash
objdump -d final.elf
```

### Symbol

```bash
nm -n final.elf
```

### Map

```bash
less final.map
```

### GC

```bash
grep -n "Discarded input sections" final.map
```

---

# 五十、实验 19-14：建立一个“Section 审计表”

例如：

| Input Section     | 来源        | 处理          | Output Section |
| ----------------- | --------- | ----------- | -------------- |
| `.isr_vector`     | vector.o  | KEEP        | `.isr_vector`  |
| `.text.startup`   | startup.o | EXCLUDE     | `.startup`     |
| `.text.foo`       | foo.o     | SORT        | `.text`        |
| `.text.bar`       | bar.o     | SORT        | `.text`        |
| `.init_array.100` | init.o    | SORT + KEEP | `.init_array`  |
| `.init_array.200` | init.o    | SORT + KEEP | `.init_array`  |

这个表非常适合在大型 linker script 调试时使用。

---

# 五十一、Map 文件现在应该这样分析

以后看到：

```text
.text
```

不要只看：

```text
.text = 0x1234
```

而要向下展开：

```text
.text
 ├── foo.o(.text.foo)
 ├── bar.o(.text.bar)
 ├── baz.o(.text.baz)
 └── ...
```

然后问：

```text
为什么 foo 在这里？
为什么 bar 在这里？
为什么某个 section 没了？
```

如果用了：

```text
SORT
```

问：

```text
为什么这个顺序？
```

如果用了：

```text
KEEP
```

问：

```text
为什么 GC 没删掉？
```

如果用了：

```text
EXCLUDE_FILE
```

问：

```text
这个 Input Section 为什么没有进入这里？
```

这才是 Map 文件真正的高级用法。

---

# 五十二、今天三个命令的区别必须记牢

## `SORT()`

解决：

> **顺序问题**

```ld
SORT(.text.*)
```

---

## `KEEP()`

解决：

> **GC 删除问题**

```ld
KEEP(*(.isr_vector))
```

---

## `EXCLUDE_FILE()`

解决：

> **来源文件过滤问题**

```ld
*(EXCLUDE_FILE(startup.o) .text.*)
```

所以：

```text
SORT
 ↓
排序

KEEP
 ↓
防 GC

EXCLUDE_FILE
 ↓
按文件过滤
```

三者职责完全不同。

---

# 五十三、组合起来就是一个 Section 管道

可以把：

```ld
KEEP(*(SORT(.init_array.*)))
```

理解成：

```text
所有 .init_array.*
        ↓
      SORT
        ↓
     按名字排序
        ↓
      KEEP
        ↓
     防止 GC
        ↓
  .init_array Output Section
```

而：

```ld
*(EXCLUDE_FILE(startup.o) .text.*)
```

则：

```text
所有 .text.*
        ↓
排除 startup.o
        ↓
剩余 Input Sections
        ↓
.text Output Section
```

---

# 五十四、一个非常重要的高级细节：`KEEP` 不等于“永远保留”

严格来说：

```ld
KEEP()
```

的主要作用是：

> 在 `--gc-sections` 的垃圾回收过程中，不要丢弃匹配的 Input Section。

它并不是一个：

```text
“无论什么情况下都永远存在”
```

的万能关键字。

例如：

```text
没有输入 section
```

那么：

```ld
KEEP(*(.foo))
```

也不会凭空制造：

```text
.foo
```

所以：

```text
KEEP
```

首先仍然需要：

```text
Input Section 存在
```

---

# 五十五、这也是为什么必须先 `objdump -h`

当你写：

```ld
KEEP(*(.isr_vector))
```

却发现：

```text
没有 .isr_vector
```

第一反应不是：

> “KEEP 不工作。”

而应该：

```bash
objdump -h vector.o
```

检查：

```text
.isr_vector
```

到底有没有生成。

这也是整个课程一直强调的：

# 不要猜 linker，直接观察 ELF。

---

# 五十六、实验 19 的最终工程布局

现在可以设计成：

```text
ROM
0x00400000
│
├── .isr_vector
│       KEEP
│
├── .startup
│       startup.o
│
├── .text
│       SORT
│       ├── foo
│       ├── bar
│       └── baz
│
├── .rodata
│
├── .init_array
│       SORT
│       KEEP
│
└── data image
```

RAM：

```text
0x00600000
│
├── .data
├── .bss
├── heap
├── overlay
└── stack
```

然后：

```text
ASSERT
```

负责：

```text
ROM 不溢出
RAM 不碰撞
Heap/Stack 不碰撞
Overlay 不碰撞
```

这时候 linker script 已经非常接近一个真正的：

```text
Embedded Firmware Linker Script
```

---

# 五十七、实验 19 总结：从“收集”到“控制”

我们之前：

```ld
.text :
{
    *(.text*)
}
```

只是：

> **把 section 收进来。**

现在已经可以：

```ld
.text :
{
    *(EXCLUDE_FILE(startup.o) .text.*)
    SORT(.text.*)
}
```

实现：

```text
选择
 ↓
过滤
 ↓
排序
 ↓
放置
```

同时：

```ld
KEEP(*(.isr_vector))
```

保证：

```text
硬件需要但软件没有普通引用的 section
```

不会因为：

```text
--gc-sections
```

而被误删。

---

# 五十八、整个 GNU ld 主线已经推进到这里

```text
实验 01～10
基础链接
│
├── Input Section
├── Output Section
├── Symbol
├── Relocation
├── Archive
└── GC
        ↓
实验 11～14
VMA / LMA
│
├── AT()
├── LOADADDR()
├── SIZEOF()
├── .data copy
└── .bss clear
        ↓
实验 15
PHDRS / Segment
        ↓
实验 16
OVERLAY
        ↓
实验 17
ASSERT()
        ↓
实验 18
PROVIDE()
DEFINED()
        ↓
实验 19
SORT()
KEEP()
EXCLUDE_FILE()
```

下一阶段就可以开始进入一个非常重要的主题：

# 实验 20：Orphan Sections —— 为什么你没有在 linker.ld 里写某个 Section，ld 却偷偷帮你放进 ELF？

这个实验非常值得做，因为它会解释大量真实工程里最令人困惑的现象：

```text
我没写：

.foo

为什么 ELF 里出现了 .foo？

为什么它被放到了这里？

为什么它跑到了 .data 后面？

为什么地址突然变了？

为什么升级 GCC/binutils 后布局发生变化？
```

我们会故意创建：

```text
foo.o
    .my_code
    .my_data
    .my_bss
```

然后 **完全不在 linker.ld 中匹配它们**。

再用：

```bash
ld
readelf -S
objdump -h
objdump -t
nm
```

以及：

```text
Map
```

逐层追踪 GNU ld 的：

```text
Orphan Section Placement
```

然后进一步进入：

```text
INSERT BEFORE
INSERT AFTER
```

最后把课程推进到：

```text
实验 20  Orphan Sections
实验 21  INSERT BEFORE / AFTER
实验 22  `SUBALIGN()` / `ALIGN_WITH_INPUT()`
实验 23  完整 MCU linker.ld
实验 24  ELF → BIN / HEX
实验 25  startup.S + linker.ld + Makefile
实验 26  自制裸机固件镜像
```

这样就会从“会写几个 section”真正进入**能够读懂并设计复杂工程 linker script**的阶段。

