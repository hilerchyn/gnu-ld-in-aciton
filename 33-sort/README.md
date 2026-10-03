# GNU ld 实战课程：实验 33 —— `SORT()` 系列

上一节我们完成了 **实验 32：`INSERT BEFORE / INSERT AFTER`**。

这一节继续沿着：

```text
Section 定位
    ↓
Section 收集
    ↓
Section 排序
    ↓
自动 Registry
    ↓
C/C++ Runtime
```

向前推进。

这一次的核心不是“把 Section 放到哪里”，而是：

> **同一个 Output Section 里面，多个 Input Section 到底按照什么顺序排列？**

GNU ld 默认会按照链接时看到的顺序处理通配符匹配到的 Input Section；`SORT_BY_NAME` 可以按名称升序排序，`SORT_BY_ALIGNMENT` 按对齐要求降序排序，`SORT_BY_INIT_PRIORITY` 按 GCC 初始化优先级升序排序，而 `SORT` 是 `SORT_BY_NAME` 的别名。([Sourceware][1])

---

# 一、先建立整个知识模型

到现在为止，我们已经遇到了三个完全不同的问题。

## 问题 1：Section 放在哪里？

使用：

```ld
INSERT BEFORE .text;
INSERT AFTER .rodata;
```

解决。

---

## 问题 2：哪些 Input Section 放进来？

例如：

```ld
*(.my_init.*)
```

解决。

---

## 问题 3：放进来以后，谁先谁后？

使用：

```ld
SORT_BY_NAME()
SORT_BY_ALIGNMENT()
SORT_BY_INIT_PRIORITY()
```

解决。

所以：

```text
                    GNU ld Section Layout
                           │
             ┌─────────────┴─────────────┐
             │                           │
        放到哪里？                    放什么？
             │                           │
         INSERT                     wildcard
             │                           │
             └─────────────┬─────────────┘
                           │
                        什么顺序？
                           │
                         SORT
```

这三个维度一定要分清。

---

# 二、实验 33-1：先观察默认顺序

我们先制造三个 Input Section：

```text
a.o
b.o
c.o
```

分别包含：

```text
.my_init.30
.my_init.10
.my_init.20
```

我们的目标是观察：

```text
不排序
```

到底是什么结果。

---

# 三、实验目录

建议新建：

```text
ld-lab/
└── 33-sort/
    ├── a.c
    ├── b.c
    ├── c.c
    ├── main.c
    └── linker.ld
```

---

# 四、实验源码

## `a.c`

```c
__attribute__((section(".my_init.30"), used))
const char init_a[] = "A";
```

---

## `b.c`

```c
__attribute__((section(".my_init.10"), used))
const char init_b[] = "B";
```

---

## `c.c`

```c
__attribute__((section(".my_init.20"), used))
const char init_c[] = "C";
```

---

## `main.c`

```c
#include <stdio.h>

extern const char init_a[];
extern const char init_b[];
extern const char init_c[];

int main(void)
{
    printf("%s %s %s\n", init_a, init_b, init_c);
    return 0;
}
```

---

# 五、先编译成 `.o`

```bash
gcc -ffunction-sections -fdata-sections -c \
    a.c b.c c.c main.c
```

现在：

```text
a.o
b.o
c.o
main.o
```

已经生成。

---

# 六、观察 Input Section

执行：

```bash
readelf -SW a.o
```

重点：

```text
.my_init.30
```

再：

```bash
readelf -SW b.o
```

得到：

```text
.my_init.10
```

以及：

```bash
readelf -SW c.o
```

得到：

```text
.my_init.20
```

现在 ELF 世界里实际存在：

```text
b.o
 └── .my_init.10

c.o
 └── .my_init.20

a.o
 └── .my_init.30
```

注意：

> `.my_init.10`、`.my_init.20`、`.my_init.30` 现在只是 **Input Section**。

还没有形成：

```text
.my_registry
```

这样的 Output Section。

---

# 七、实验 33-2：不使用 SORT

创建：

```ld
SECTIONS
{
    .my_registry :
    {
        __my_registry_start = .;

        *(.my_init.*)

        __my_registry_end = .;
    }
}

INSERT BEFORE .text;
```

保存：

```text
linker-nosort.ld
```

---

# 八、链接

故意按照：

```text
a.o
b.o
c.o
```

这个顺序：

```bash
gcc \
    a.o \
    b.o \
    c.o \
    main.o \
    -Wl,-T,linker-nosort.ld \
    -Wl,-Map=nosort.map \
    -o nosort.elf
```

---

# 九、readelf 验证

```bash
readelf -SW nosort.elf
```

找到：

```text
.my_registry
```

再：

```bash
objdump -h nosort.elf
```

你应该看到 `.my_registry`。

---

# 十、最重要：分析 Map

```bash
grep -A20 -B2 '\.my_registry' nosort.map
```

重点观察：

```text
.my_registry

 *(.my_init.*)

 .my_init.30   ... a.o
 .my_init.10   ... b.o
 .my_init.20   ... c.o
```

如果当前 binutils/GCC 环境保持普通输入顺序，你会看到 Input Section 按链接输入顺序参与布局。

这正是 GNU ld 文档所描述的默认行为：没有排序命令时，通配符匹配到的文件和 Section 通常按照它们在链接过程中被看到的顺序放置。([Sourceware][2])

---

# 十一、这里出现第一个重要结论

我们现在有：

```text
Input Section 名称：

.my_init.30
.my_init.10
.my_init.20
```

但是：

```text
ld 不会因为名字里面有
30 / 10 / 20
就自动认为应该：

10
20
30
```

默认情况下：

```text
链接顺序
    ↓
影响 Input Section 顺序
```

如果我们需要：

```text
10
20
30
```

就应该明确告诉 ld：

```ld
SORT_BY_NAME
```

---

# 十二、实验 33-3：`SORT_BY_NAME`

修改 linker script：

```ld
SECTIONS
{
    .my_registry :
    {
        __my_registry_start = .;

        *(SORT_BY_NAME(.my_init.*))

        __my_registry_end = .;
    }
}

INSERT BEFORE .text;
```

保存：

```text
linker-sort-name.ld
```

这里有一个非常重要的语法细节：

正确：

```ld
*(SORT_BY_NAME(.my_init.*))
```

而不是：

```ld
SORT_BY_NAME(*(.my_init.*))
```

我上一节如果把这两种形式混淆了，这里以这个实际可运行的形式为准。

GNU ld 的典型语法就是：

```ld
*(SORT_BY_NAME(.text*))
```

官方文档也是这样描述的。([Sourceware][2])

---

# 十三、重新链接

```bash
gcc \
    a.o \
    b.o \
    c.o \
    main.o \
    -Wl,-T,linker-sort-name.ld \
    -Wl,-Map=sort-name.map \
    -o sort-name.elf
```

---

# 十四、Map 验证

```bash
grep -A20 -B2 '\.my_registry' sort-name.map
```

现在应该看到类似：

```text
.my_registry
                0x000000000000....

*(SORT_BY_NAME(.my_init.*))

.my_init.10     ... b.o
.my_init.20     ... c.o
.my_init.30     ... a.o
```

注意：

```text
a.o
b.o
c.o
```

的链接顺序仍然是：

```text
a
b
c
```

但是 Input Section 已经变成：

```text
.my_init.10
.my_init.20
.my_init.30
```

---

# 十五、验证实际二进制内容

执行：

```bash
objdump -s -j .my_registry sort-name.elf
```

你应该看到类似：

```text
Contents of section .my_registry:
    4200 4300 4100
```

对应：

```text
B
C
A
```

也就是：

```text
.my_init.10 → B
.my_init.20 → C
.my_init.30 → A
```

所以：

```text
SORT_BY_NAME
      ↓
Input Section Name
      ↓
字典序升序
```

---

# 十六、实验 33-4：`SORT` 是什么？

直接写：

```ld
*(SORT(.my_init.*))
```

实际上就是：

```ld
*(SORT_BY_NAME(.my_init.*))
```

因为：

```text
SORT = SORT_BY_NAME
```

这是 GNU ld 官方文档明确规定的。([Sourceware][2])

所以：

```ld
*(SORT(.my_init.*))
```

可以作为简写。

但在课程和大型项目中，我更建议：

```ld
*(SORT_BY_NAME(.my_init.*))
```

原因很简单：

> **一眼看出排序依据。**

---

# 十七、实验 33-5：改变 `.o` 输入顺序

现在故意：

```bash
gcc \
    c.o \
    a.o \
    b.o \
    main.o \
    -Wl,-T,linker-nosort.ld \
    -Wl,-Map=order-cab.map \
    -o order-cab.elf
```

然后：

```bash
grep -A15 '\.my_registry' order-cab.map
```

你会看到：

```text
.my_init.20
.my_init.30
.my_init.10
```

也就是：

```text
c
a
b
```

再使用：

```bash
gcc \
    c.o \
    a.o \
    b.o \
    main.o \
    -Wl,-T,linker-sort-name.ld \
    -Wl,-Map=order-cab-sort.map \
    -o order-cab-sort.elf
```

再次：

```bash
grep -A15 '\.my_registry' order-cab-sort.map
```

仍然：

```text
.my_init.10
.my_init.20
.my_init.30
```

这就是一个非常漂亮的实验：

```text
                 不排序              SORT_BY_NAME
                  │                       │
a b c 输入顺序    │                       │
                  ▼                       ▼
30 10 20          30 10 20              10 20 30

c a b 输入顺序    │                       │
                  ▼                       ▼
20 30 10          10 20 30
```

所以：

> `SORT_BY_NAME` 把“链接输入顺序”与“最终 Registry 顺序”解耦了。

---

# 十八、实验 33-6：为什么这对 Registry 很有用？

假设我们有：

```text
driver_uart.o
driver_spi.o
driver_i2c.o
driver_can.o
```

每个驱动都定义：

```text
.driver.100
.driver.200
.driver.300
.driver.400
```

那么 linker 可以直接形成：

```text
.driver_registry
    │
    ├── driver.100
    ├── driver.200
    ├── driver.300
    └── driver.400
```

不需要：

```c
static Driver drivers[] = {
    uart,
    spi,
    i2c,
    can
};
```

这就是：

# Linker-assisted Registry

后面我们会把它完整实现出来。

---

# 十九、实验 33-7：`SORT_BY_ALIGNMENT`

接下来换一个问题。

假设：

```text
.align.8
.align.16
.align.32
```

三个 Input Section 的 alignment 分别是：

```text
8
16
32
```

我们希望：

```text
32
16
8
```

GNU ld 的：

```ld
SORT_BY_ALIGNMENT
```

就是干这个的。

它按照 Input Section alignment **降序**排列。官方文档还特别说明，这样通常可以减少因为对齐造成的 padding。([Sourceware][2])

---

# 二十、准备源码

## `align8.c`

```c
__attribute__((section(".align.08"), aligned(8), used))
const char align8 = '8';
```

---

## `align16.c`

```c
__attribute__((section(".align.16"), aligned(16), used))
const char align16 = '6';
```

---

## `align32.c`

```c
__attribute__((section(".align.32"), aligned(32), used))
const char align32 = '2';
```

---

# 二十一、编译

```bash
gcc -c \
    align8.c \
    align16.c \
    align32.c
```

---

# 二十二、先确认 Input Section alignment

分别：

```bash
readelf -SW align8.o
```

```bash
readelf -SW align16.o
```

```bash
readelf -SW align32.o
```

重点看最后的：

```text
Algn
```

应该分别接近：

```text
8
16
32
```

例如：

```text
.align.08    ...  8
.align.16    ... 16
.align.32    ... 32
```

---

# 二十三、创建 linker script

```ld
SECTIONS
{
    .align_registry :
    {
        __align_start = .;

        *(SORT_BY_ALIGNMENT(.align.*))

        __align_end = .;
    }
}

INSERT BEFORE .text;
```

保存：

```text
linker-sort-align.ld
```

---

# 二十四、为了让实验更纯粹

我们暂时直接使用：

```bash
ld
```

而不是 GCC。

因为我们现在只研究：

```text
Input Section
→
Output Section
→
排序
```

所以：

```bash
ld \
    -T linker-sort-align.ld \
    align8.o \
    align16.o \
    align32.o \
    -Map=align.map \
    -o align.elf
```

可能出现：

```text
cannot find entry symbol _start
```

之类的 warning。

这不是本实验重点。

因为我们没有提供真正的 `_start`。

---

# 二十五、Map 文件是这次实验的核心

执行：

```bash
grep -A20 -B2 '\.align_registry' align.map
```

你应该看到类似：

```text
.align_registry
    ...
 *(SORT_BY_ALIGNMENT(.align.*))

 .align.32
 .align.16
 .align.08
```

即：

```text
32
↓
16
↓
8
```

---

# 二十六、这里出现一个非常重要的现象：Padding

Map 里通常还会看到：

```text
*fill*
```

例如：

```text
.align.32
*fill*
.align.16
*fill*
.align.08
```

这是因为：

```text
Section A 结束
      ↓
下一个 Section 要求 16-byte alignment
      ↓
location counter 向前移动
      ↓
产生 padding
```

所以：

# Alignment Sorting ≠ 没有 Padding

而是：

> **尽可能通过先放高 alignment Section，减少总体 padding。**

GNU ld 文档正是基于这个原因说明 `SORT_BY_ALIGNMENT` 的用途。([Sourceware][2])

---

# 二十七、readelf 验证

```bash
readelf -SW align.elf
```

找到：

```text
.align_registry
```

观察：

```text
Addr
Off
Size
Algn
```

然后：

```bash
objdump -h align.elf
```

观察：

```text
.align_registry
```

的：

```text
SIZE
VMA
LMA
ALIGN
```

---

# 二十八、objdump 查看实际内容

```bash
objdump -s -j .align_registry align.elf
```

你会看到类似：

```text
32-byte aligned section
        ↓
'2'

16-byte aligned section
        ↓
'6'

8-byte aligned section
        ↓
'8'
```

因此最终内存类似：

```text
0x1000   '2'
         ...
0x1010   '6'
         ...
0x1018   '8'
```

---

# 二十九、实验 33-8：`SORT_BY_NAME` vs `SORT_BY_ALIGNMENT`

现在把三个 Section：

```text
.align.08
.align.16
.align.32
```

同时满足：

```text
名字顺序
08
16
32
```

和：

```text
alignment
8
16
32
```

因此两个排序结果恰好相反：

```text
SORT_BY_NAME

08
16
32
```

而：

```text
SORT_BY_ALIGNMENT

32
16
8
```

这说明：

> 排序不是针对“Section 内容”，而是针对 linker 看到的 Input Section 元数据。

---

# 三十、实验 33-9：`SORT_BY_INIT_PRIORITY`

现在进入真正有意思的部分。

GNU ld 支持：

```ld
SORT_BY_INIT_PRIORITY
```

它专门用于 GCC 产生的初始化优先级 Section。

例如：

```text
.init_array.00101
.init_array.00200
.init_array.00300
```

按照：

```text
101
200
300
```

的数字顺序排列。

GNU ld 文档明确说明，`.init_array.NNNNN` 中的数字就是初始化优先级，并且 `SORT_BY_INIT_PRIORITY` 按这个优先级升序排列。([Sourceware][2])

---

# 三十一、实验 33-10：制造 C++ 初始化优先级

准备：

## `p101.cpp`

```cpp
struct A
{
    A();
};

A a __attribute__((init_priority(101)));

A::A()
{
}
```

---

## `p200.cpp`

```cpp
struct B
{
    B();
};

B b __attribute__((init_priority(200)));

B::B()
{
}
```

---

## `p300.cpp`

```cpp
struct C
{
    C();
};

C c __attribute__((init_priority(300)));

C::C()
{
}
```

---

## `main.cpp`

```cpp
int main()
{
    return 0;
}
```

---

# 三十二、编译

```bash
g++ -c \
    p101.cpp \
    p200.cpp \
    p300.cpp \
    main.cpp
```

---

# 三十三、观察 `.o`

这是非常重要的一步。

执行：

```bash
readelf -SW p101.o
```

搜索：

```text
init_array
```

你应该看到：

```text
.init_array.00101
```

然后：

```bash
readelf -SW p200.o | grep init_array
```

得到：

```text
.init_array.00200
```

以及：

```bash
readelf -SW p300.o | grep init_array
```

得到：

```text
.init_array.00300
```

这一步非常漂亮，因为你现在亲眼看到了：

```text
C++ 属性
    ↓
init_priority(101)
    ↓
ELF Input Section
    ↓
.init_array.00101
```

---

# 三十四、创建实验 linker script

```ld
SECTIONS
{
    .my_init_array :
    {
        __my_init_start = .;

        *(SORT_BY_INIT_PRIORITY(.init_array.*))

        __my_init_end = .;
    }
}

INSERT BEFORE .init_array;
```

保存：

```text
linker-init-priority.ld
```

---

# 三十五、链接

```bash
g++ \
    p101.o \
    p200.o \
    p300.o \
    main.o \
    -Wl,-T,linker-init-priority.ld \
    -Wl,-Map=init-priority.map \
    -o init-priority.elf
```

---

# 三十六、readelf 验证

```bash
readelf -SW init-priority.elf
```

找到：

```text
.my_init_array
```

你应该看到：

```text
.my_init_array
.init_array
```

也就是说：

```text
我们自己的 Registry
```

被插到了默认：

```text
.init_array
```

之前。

---

# 三十七、Map 是最关键的验证

```bash
grep -A25 -B2 '\.my_init_array' init-priority.map
```

应该出现：

```text
.my_init_array
    ...

*(SORT_BY_INIT_PRIORITY(.init_array.*))

.init_array.00101    p101.o
.init_array.00200    p200.o
.init_array.00300    p300.o
```

即：

```text
101
 ↓
200
 ↓
300
```

---

# 三十八、现在把链接顺序打乱

故意：

```bash
g++ \
    p300.o \
    p101.o \
    p200.o \
    main.o \
    -Wl,-T,linker-init-priority.ld \
    -Wl,-Map=init-priority-2.map \
    -o init-priority-2.elf
```

再：

```bash
grep -A20 '\.my_init_array' init-priority-2.map
```

依然应该：

```text
.init_array.00101
.init_array.00200
.init_array.00300
```

所以：

```text
.o 输入顺序
       ↓
不再决定最终 priority 顺序
```

而是：

```text
init_priority
       ↓
.init_array.NNNNN
       ↓
SORT_BY_INIT_PRIORITY
       ↓
最终顺序
```

---

# 三十九、这里已经出现真正的“编译器 → ELF → linker”流水线

现在把整个过程串起来：

```text
C++ 源码

__attribute__((init_priority(101)))
              │
              ▼
           GCC
              │
              ▼
.init_array.00101
              │
              ▼
         ELF .o
              │
              ▼
           GNU ld
              │
       SORT_BY_INIT_PRIORITY
              │
              ▼
.init_array.00101
.init_array.00200
.init_array.00300
```

这已经不是单纯学习：

```text
ld 命令
```

而是在研究：

# 编译器如何利用 linker 构建运行时数据结构

---

# 四十、实验 33-11：直接研究系统默认 `.init_array`

实际上你会发现，系统默认 linker script 本身就会处理：

```ld
*(SORT_BY_INIT_PRIORITY(.init_array.*)
  SORT_BY_INIT_PRIORITY(.ctors.*))
```

这也是为什么：

```bash
ld --verbose
```

非常值得反复阅读。

你可以：

```bash
ld --verbose > default-linker.txt
```

然后：

```bash
grep -n -A8 -B5 'init_array' default-linker.txt
```

你会发现默认 script 已经在使用：

```text
SORT_BY_INIT_PRIORITY
```

这意味着：

> 我们现在学习的东西，不是为了“造一个玩具 linker script”，而是在拆解 GCC/Linux 实际工具链正在使用的机制。

---

# 四十一、实验 33-12：`SORT_BY_NAME` 和 `SORT_BY_INIT_PRIORITY` 的区别

假设：

```text
.init_array.00101
.init_array.00200
.init_array.01000
```

对于这些名字：

```text
SORT_BY_NAME
```

通常也能得到：

```text
00101
00200
01000
```

看起来没区别。

但是语义不同：

```text
SORT_BY_NAME
    ↓
按照 Section 名称排序
```

而：

```text
SORT_BY_INIT_PRIORITY
    ↓
按照 init_priority 语义排序
```

所以：

> 如果你处理的是 `.init_array.NNNNN`，优先使用 `SORT_BY_INIT_PRIORITY` 表达意图。

---

# 四十二、实验 33-13：嵌套 SORT

GNU ld 允许有限的嵌套排序。

例如：

```ld
*(SORT_BY_NAME(SORT_BY_ALIGNMENT(.foo.*)))
```

其含义是：

```text
先按 Section 名称
    ↓
如果名称相同
    ↓
再按 alignment
```

而：

```ld
*(SORT_BY_ALIGNMENT(SORT_BY_NAME(.foo.*)))
```

则是：

```text
先按 alignment
    ↓
如果 alignment 相同
    ↓
再按名称
```

GNU ld 文档明确规定了这种有限的嵌套规则，而且最多允许一层嵌套；并不是任意 SORT 都可以无限嵌套。([Sourceware][2])

---

# 四十三、为什么要理解“主排序 + 次排序”？

例如：

```text
.foo.a   alignment=16
.foo.b   alignment=8
.foo.c   alignment=16
.foo.d   alignment=8
```

如果：

```ld
SORT_BY_ALIGNMENT(SORT_BY_NAME(.foo.*))
```

可以理解成：

```text
16:
    .foo.a
    .foo.c

8:
    .foo.b
    .foo.d
```

而：

```ld
SORT_BY_NAME(SORT_BY_ALIGNMENT(.foo.*))
```

则是：

```text
.foo.a
.foo.b
.foo.c
.foo.d
```

名称是主排序键。

alignment 是次排序键。

---

# 四十四、实验 33-14：Map 文件为什么特别适合验证 SORT？

因为：

```bash
readelf -SW
```

只能告诉你：

```text
.my_registry
```

存在。

而：

```bash
objdump -h
```

只能告诉你：

```text
.my_registry
```

的地址和大小。

但：

```text
Map
```

会告诉你：

```text
.my_registry
    │
    ├── .my_init.10 ← b.o
    ├── .my_init.20 ← c.o
    └── .my_init.30 ← a.o
```

所以：

# SORT 实验中，Map 文件是第一验证工具。

GNU ld 官方文档也特别建议，当你不清楚 Input Section 被映射到哪里时，可以使用 `-M` 生成 map；Map 能精确显示 Input Section 如何映射到 Output Section。([Sourceware][2])

---

# 四十五、实验 33-15：完整 Registry

现在做一个真正有用的例子。

定义：

```c
typedef void (*init_fn)(void);
```

然后：

## `uart.c`

```c
static void uart_init(void)
{
}

__attribute__((section(".driver.100"), used))
init_fn uart_driver = uart_init;
```

---

## `spi.c`

```c
static void spi_init(void)
{
}

__attribute__((section(".driver.200"), used))
init_fn spi_driver = spi_init;
```

---

## `i2c.c`

```c
static void i2c_init(void)
{
}

__attribute__((section(".driver.300"), used))
init_fn i2c_driver = i2c_init;
```

---

# 四十六、linker script

```ld
SECTIONS
{
    .driver_registry :
    {
        __driver_registry_start = .;

        KEEP(*(SORT_BY_NAME(.driver.*)))

        __driver_registry_end = .;
    }
}

INSERT BEFORE .text;
```

这里出现三个我们已经学过的机制：

```text
KEEP
SORT
INSERT
```

组合起来：

```text
KEEP
 ↓
不要 GC

SORT
 ↓
按名字排序

INSERT
 ↓
放入默认 ELF 布局
```

---

# 四十七、C 代码遍历 Registry

```c
typedef void (*init_fn)(void);

extern init_fn __driver_registry_start[];
extern init_fn __driver_registry_end[];

static void run_drivers(void)
{
    for (init_fn *p = __driver_registry_start;
         p < __driver_registry_end;
         ++p)
    {
        (*p)();
    }
}
```

现在：

```text
uart.c
spi.c
i2c.c
```

只负责：

```text
“注册自己”
```

不需要修改：

```text
registry.c
```

---

# 四十八、这就是 linker 最漂亮的应用之一

传统方式：

```c
Driver drivers[] =
{
    uart_driver,
    spi_driver,
    i2c_driver,
};
```

问题：

```text
新增 driver
    ↓
必须修改 registry.c
```

而 linker Registry：

```text
uart.c
    ↓
.driver.100

spi.c
    ↓
.driver.200

i2c.c
    ↓
.driver.300

        ↓

      ld

        ↓

.driver_registry
```

新增：

```text
can.c
```

只需要：

```c
__attribute__((section(".driver.400")))
```

就自动进入 Registry。

这就是：

# Linker-based Registration

---

# 四十九、实验 33-16：加入 `--gc-sections`

现在编译：

```bash
gcc \
    -ffunction-sections \
    -fdata-sections \
    -c \
    uart.c spi.c i2c.c main.c
```

链接：

```bash
gcc \
    uart.o \
    spi.o \
    i2c.o \
    main.o \
    -Wl,-T,driver.ld \
    -Wl,--gc-sections \
    -Wl,-Map=driver.map \
    -o driver.elf
```

如果没有：

```ld
KEEP
```

Registry 中的对象可能因为没有普通 C 引用而被 GC。

所以：

```ld
KEEP(*(SORT_BY_NAME(.driver.*)))
```

非常关键。

---

# 五十、现在形成一个完整设计模式

```text
                 每个模块
                    │
                    ▼
             自己定义 Section
                    │
                    ▼
              .driver.NNN
                    │
                    ▼
                   ld
                    │
          ┌─────────┴─────────┐
          │                   │
        SORT                KEEP
          │                   │
      定义顺序              防止 GC
          │                   │
          └─────────┬─────────┘
                    │
                    ▼
             Driver Registry
                    │
                    ▼
                 C 遍历
```

---

# 五十一、这节课必须掌握的四种 SORT

| 命令                      | 排序依据          | 顺序   |
| ----------------------- | ------------- | ---- |
| `SORT`                  | 名称            | 升序   |
| `SORT_BY_NAME`          | 名称            | 升序   |
| `SORT_BY_ALIGNMENT`     | alignment     | 降序   |
| `SORT_BY_INIT_PRIORITY` | init priority | 数字升序 |

其中：

```text
SORT == SORT_BY_NAME
```

官方文档明确如此定义。([Sourceware][2])

---

# 五十二、最容易写错的语法

### 错误思维

```ld
SORT_BY_NAME(*(.foo.*))
```

### 正确

```ld
*(SORT_BY_NAME(.foo.*))
```

也就是：

```text
         wildcard
            │
            ▼
           *(
              SORT_BY_NAME(
                  .foo.*
              )
           )
```

记成：

> **先 `*()`，里面再 SORT。**

---

# 五十三、`KEEP + SORT` 的正确组合

推荐：

```ld
KEEP(*(SORT_BY_NAME(.plugin.*)))
```

而不是：

```ld
SORT_BY_NAME(KEEP(*(.plugin.*)))
```

因为：

```text
KEEP
```

是 Input Section 保留机制；

```text
SORT
```

是 Input Section 排序机制。

通常写成：

```text
KEEP(
    *(
        SORT_BY_NAME(...)
    )
)
```

最直观。

---

# 五十四、这节实验的完整验证清单

以后你做任何 `SORT` 实验，可以固定执行：

### ① Input Section

```bash
readelf -SW xxx.o
```

确认：

```text
.my_init.*
```

---

### ② linker script

```bash
cat linker.ld
```

确认：

```ld
*(SORT_BY_NAME(...))
```

---

### ③ 链接

```bash
gcc ... \
    -Wl,-T,linker.ld \
    -Wl,-Map=xxx.map
```

---

### ④ Output Section

```bash
readelf -SW xxx.elf
```

---

### ⑤ Section Header

```bash
objdump -h xxx.elf
```

---

### ⑥ 实际数据

```bash
objdump -s -j .my_registry xxx.elf
```

---

### ⑦ Symbol

```bash
nm -n xxx.elf
```

---

### ⑧ 最关键：Map

```bash
grep -A30 -B3 '\.my_registry' xxx.map
```

---

# 五十五、把实验 32 和实验 33 组合起来

现在你已经可以写：

```ld
SECTIONS
{
    .driver_registry :
        ALIGN(16)
    {
        __driver_start = .;

        KEEP(*(SORT_BY_NAME(.driver.*)))

        __driver_end = .;
    }
}

INSERT BEFORE .text;
```

这句话已经包含：

```text
ALIGN
  ↓
Output Section 对齐

KEEP
  ↓
防止 GC

SORT
  ↓
Registry 顺序

Wildcard
  ↓
收集模块

INSERT
  ↓
扩展默认 linker script

Symbol
  ↓
C 访问 Registry
```

这已经是非常接近实际项目的 linker script 了。

---

# 五十六、实验 33 的最终知识地图

```text
                         SORT
                          │
             ┌────────────┼────────────┐
             │            │            │
          NAME       ALIGNMENT    INIT_PRIORITY
             │            │            │
             ▼            ▼            ▼
        字典序升序     对齐降序      优先级升序
             │            │            │
             └────────────┼────────────┘
                          │
                          ▼
                    Input Sections
                          │
                          ▼
                    Output Section
                          │
                    ┌─────┴─────┐
                    │           │
                  KEEP       INSERT
                    │           │
                    ▼           ▼
                 不被 GC      默认布局
```

---

# 五十七、到这里课程进入一个重要分水岭

之前的实验更多是在研究：

```text
“ld 怎么摆放东西？”
```

从现在开始，我们开始研究：

```text
“如何利用 ld 构建程序的架构机制？”
```

已经可以做：

```text
Plugin Registry
Driver Registry
Command Registry
Device Registry
Protocol Registry
Init Registry
Factory Registry
```

这也是为什么 Linux、RTOS、Bootloader、Firmware 等大型工程中 linker script 往往远比初学者想象得重要。

---

# 五十八、下一节：实验 34 —— `REVERSE` + `SORT_NONE` + `EXCLUDE_FILE`

实验 33 之后，下一步自然进入：

```text
实验 34-1
REVERSE

实验 34-2
REVERSE + SORT_BY_NAME

实验 34-3
SORT_NONE

实验 34-4
EXCLUDE_FILE

实验 34-5
EXCLUDE_FILE + SORT

实验 34-6
EXCLUDE_FILE + KEEP

实验 34-7
同名 Input Section 的文件级控制

实验 34-8
构造“默认收集，排除某个 .o”

实验 34-9
Map 分析 EXCLUDE_FILE 到底排除了什么

实验 34-10
构造 Plugin Blacklist

实验 34-11
构造 Bootloader / Application 双区域
```

尤其是：

```ld
*(SORT_BY_NAME(EXCLUDE_FILE(foo.o) .text.*))
```

与：

```ld
*(EXCLUDE_FILE(foo.o) SORT_BY_NAME(.text.*))
```

的区别。

GNU ld 对这里的语法位置有明确限制：`EXCLUDE_FILE` 可以放在排序命令里面，但不能反过来把排序命令放进 `EXCLUDE_FILE`。([Sourceware][1])

之后再继续进入一个更重要的阶段：

```text
实验 35
Memory Region 高级控制

实验 36
PHDRS 深入

实验 37
Section → Segment

实验 38
FILEHDR / PHDRS / SIZEOF_HEADERS

实验 39
AT / LOADADDR / LMA

实验 40
ROM → RAM 初始化表

实验 41
Overlay + Copy Table

实验 42
Firmware Image Layout

实验 43
Bootloader + Application 双镜像

实验 44
ELF → Binary / HEX

实验 45
最终综合实验：
自己设计一个完整 Firmware Linker Script
```

这一阶段会把我们前面学过的：

```text
MEMORY
SECTIONS
INSERT
SORT
KEEP
ALIGN
ASSERT
NOCROSSREFS
OVERLAY
AT
LOADADDR
PHDRS
```

真正串成一个完整的 **Bootloader/Firmware 链接布局系统**。

[1]: https://sourceware.org/binutils/docs/ld.pdf?utm_source=chatgpt.com "The GNU linker"
[2]: https://www.sourceware.org/binutils/docs-2.36/ld.pdf?utm_source=chatgpt.com "68  The GNU linker"

