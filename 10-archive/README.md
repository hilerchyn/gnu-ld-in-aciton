# GNU ld 实战课程 · 实验 10

## 静态库 `.a`：为什么 `ld` 有时候就是“不链接”？

这一节开始从 **linker script 布局**转向 `ld` 最核心的工作之一：

```text
Archive / Static Library
        ↓
Symbol Resolution
        ↓
决定哪些 .o 从 .a 中被取出来
        ↓
Section 合并
        ↓
Relocation
```

真正要搞懂的是：

> `.a` 并不是“把里面所有 `.o` 自动塞进 ELF”。

`ld` 会根据**当前尚未解析的符号**，决定是否从 archive 中提取某个成员。

---

# 一、先建立 `.a` 的正确模型

假设：

```text
libfoo.a
├── foo.o
├── bar.o
└── baz.o
```

不要把它理解成：

```text
libfoo.a
   ↓
全部链接
```

正确模型是：

```text
libfoo.a
   │
   ├── foo.o
   ├── bar.o
   └── baz.o
          │
          ▼
      linker 检查
          │
     ┌────┴────┐
     ▼         ▼
需要        不需要
     │         │
     ▼         ▼
提取 .o     留在 .a
```

也就是说：

> **Archive 是一个 `.o` 的仓库，`ld` 按需提取成员。**

---

# 二、实验目标

今天完成 5 个实验：

```text
实验 10-1
创建 libfoo.a

实验 10-2
main.o libfoo.a
正常链接

实验 10-3
libfoo.a main.o
观察顺序问题

实验 10-4
--whole-archive
强制提取所有成员

实验 10-5
--start-group / --end-group
解决循环依赖
```

最终建立：

```text
Object
  │
  ▼
Undefined Symbol
  │
  ▼
Archive Search
  │
  ▼
Extract Member
  │
  ▼
New Symbols
  │
  ▼
继续解析
```

---

# 三、实验目录

```text
ld-lab/
├── main.c
├── start.S
├── foo.c
├── bar.c
└── linker.ld
```

---

# 四、创建两个库成员

## `foo.c`

```c
int foo(void)
{
    return 40;
}
```

---

## `bar.c`

```c
int bar(void)
{
    return 100;
}
```

注意：

```text
foo.o
```

定义：

```text
foo
```

而：

```text
bar.o
```

定义：

```text
bar
```

两者互不依赖。

---

# 五、main.c

```c
extern int foo(void);

int main(void)
{
    return foo() + 2;
}
```

因此：

```text
main.o
    │
    └── undefined foo
```

而：

```text
foo.o
    │
    └── defines foo
```

---

# 六、start.S

继续使用：

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

# 七、linker.ld

为了把注意力放在 archive 上，这次 linker script 尽量简单：

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

---

# 八、编译三个 `.o`

```bash
gcc -c main.c -o main.o
gcc -c foo.c -o foo.o
gcc -c bar.c -o bar.o
gcc -c start.S -o start.o
```

先观察：

```bash
nm main.o
```

应该看到：

```text
U foo
T main
```

意思：

```text
foo
 ↓
Undefined

main
 ↓
Defined
```

然后：

```bash
nm foo.o
```

应该看到：

```text
T foo
```

而：

```bash
nm bar.o
```

应该：

```text
T bar
```

---

# 九、创建静态库

使用：

```bash
ar rcs libfoo.a foo.o bar.o
```

现在：

```text
libfoo.a
├── foo.o
└── bar.o
```

检查：

```bash
ar t libfoo.a
```

得到：

```text
foo.o
bar.o
```

---

# 十、观察 archive 中有什么

可以使用：

```bash
nm -s libfoo.a
```

或者：

```bash
nm -A libfoo.a
```

你会看到：

```text
libfoo.a:foo.o:
foo

libfoo.a:bar.o:
bar
```

这里开始出现一个非常重要的概念：

> `ld` 并不是直接对“`.a`”整体做符号解析，而是在 archive 中查找**哪个成员能够解决当前未定义符号**。

---

# 十一、实验 10-1：正确顺序

链接：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    libfoo.a \
    -o normal.elf \
    -Map=normal.map
```

执行：

```bash
./normal.elf
echo $?
```

应该：

```text
42
```

因为：

```text
main.o
   │
   │ needs foo
   ▼
libfoo.a
   │
   │ foo.o defines foo
   ▼
提取 foo.o
   │
   ▼
foo()
   │
   ▼
return 40
   │
   ▼
main → 42
```

---

# 十二、为什么 `bar.o` 没被提取？

这是今天最重要的第一个观察点。

虽然：

```text
libfoo.a
├── foo.o
└── bar.o
```

但：

```text
main.o
```

只需要：

```text
foo
```

因此 linker：

```text
foo.o
    ↓
提取

bar.o
    ↓
不提取
```

检查：

```bash
nm -n normal.elf
```

你应该看到：

```text
foo
main
_start
```

但：

```text
bar
```

通常不会出现在最终 ELF。

---

# 十三、用 map 文件确认 archive 提取

打开：

```bash
less normal.map
```

搜索：

```text
libfoo.a
```

或者：

```bash
grep -A 20 -B 5 "libfoo.a" normal.map
```

你会看到 archive 成员参与链接的信息。

重点找：

```text
foo.o
```

而：

```text
bar.o
```

不会成为实际输入 section。

---

# 十四、这就是 Archive 的核心算法

可以先用简化模型理解：

```text
当前：

Undefined:
    foo

Archive:
    foo.o → defines foo
    bar.o → defines bar

搜索 archive
       │
       ▼
发现 foo.o
       │
       ▼
提取 foo.o
       │
       ▼
Undefined 被解决
       │
       ▼
继续处理
```

如果没有：

```text
Undefined bar
```

那么：

```text
bar.o
```

没有必要被取出来。

---

# 十五、实验 10-2：把库放到前面

现在故意改变顺序：

```bash
ld \
    -T linker.ld \
    start.o \
    libfoo.a \
    main.o \
    -o wrong-order.elf \
    -Map=wrong-order.map
```

这次可能得到：

```text
undefined reference to `foo'
```

这不是 `foo.o` 不存在。

因为：

```text
libfoo.a
```

确实包含：

```text
foo.o
```

问题在于：

```text
linker 处理 libfoo.a 时
```

当时可能还没有看到：

```text
main.o
```

所以 linker 当时并不知道：

```text
foo
```

是一个需要解决的 undefined symbol。

于是：

```text
libfoo.a
   ↓
没有需要提取的成员
   ↓
继续
```

之后：

```text
main.o
   ↓
出现 undefined foo
```

但：

```text
libfoo.a
```

已经处理过去了。

于是最终：

```text
foo
 ↓
仍然 undefined
 ↓
链接失败
```

---

# 十六、这就是经典的库顺序规则

对于：

```text
A 依赖 B
```

通常：

```text
A B
```

即：

```bash
ld main.o libfoo.a
```

而不是：

```bash
ld libfoo.a main.o
```

可以记成：

```text
依赖者
   ↓
被依赖者
```

或者：

```text
main.o → libfoo.a
```

---

# 十七、用一个图记住

```text
main.o
  │
  │ undefined foo
  ▼
libfoo.a
  │
  └── foo.o
```

所以：

```text
main.o libfoo.a
```

正确。

而：

```text
libfoo.a main.o
```

可能失败。

---

# 十八、用 `--trace` 观察 linker 实际处理了什么

重新执行：

```bash
ld \
    -T linker.ld \
    --trace \
    start.o \
    main.o \
    libfoo.a \
    -o trace.elf
```

`--trace` 会让 linker 输出它处理的输入文件。

也可以使用：

```bash
ld \
    -T linker.ld \
    --trace-symbol=foo \
    start.o \
    main.o \
    libfoo.a \
    -o trace.elf
```

这个更有意思。

它专门追踪：

```text
foo
```

在哪里：

```text
定义
引用
```

---

# 十九、`--trace-symbol` 非常值得记住

当工程变得复杂：

```text
1000 个 .o
200 个 .a
```

你遇到：

```text
undefined reference to foo
```

不要盲目翻文件。

可以：

```bash
ld \
    --trace-symbol=foo \
    ...
```

或者 GNU ld 对应的等效选项：

```bash
-Wl,--trace-symbol=foo
```

在通过 GCC 驱动器链接时使用。

它能帮助你定位：

```text
谁引用 foo
谁定义 foo
```

---

# 二十、实验 10-3：`--whole-archive`

现在我们故意要求：

> 不管有没有引用，把 archive 里面所有成员都拿出来。

使用：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    --whole-archive \
    libfoo.a \
    --no-whole-archive \
    -o whole.elf \
    -Map=whole.map
```

现在：

```text
libfoo.a
├── foo.o  ← 提取
└── bar.o  ← 也提取
```

验证：

```bash
nm -n whole.elf | grep -E 'foo|bar'
```

应该同时出现：

```text
foo
bar
```

---

# 二十一、`--whole-archive` 到底改变了什么？

普通模式：

```text
libfoo.a
   │
   ├── foo.o → needed → extract
   │
   └── bar.o → unused → ignore
```

`--whole-archive`：

```text
libfoo.a
   │
   ├── foo.o → extract
   └── bar.o → extract
```

所以它相当于：

> **关闭 archive 的按需提取策略。**

---

# 二十二、为什么不总是使用 `--whole-archive`？

因为可能让最终 ELF 膨胀。

例如：

```text
libbig.a
```

里面有：

```text
1000 个 .o
```

实际只需要：

```text
20 个
```

普通链接：

```text
20 个
```

而：

```text
--whole-archive
```

可能：

```text
1000 个
```

全部进入链接。

所以它通常只用于：

```text
注册表
插件
静态构造
特殊表
必须保留的模块
```

等特殊场景。

---

# 二十三、这里和上一节的 `KEEP()` 有一个很容易混淆的地方

它们解决的是不同层面的问题：

```text
--whole-archive
```

控制：

```text
Archive Member
```

而：

```ld
KEEP(*(.foo))
```

控制：

```text
Input Section GC
```

所以：

```text
.a
│
├── foo.o
├── bar.o
└── baz.o
       │
       ▼
Archive extraction
       │
       ▼
Input Sections
       │
       ▼
--gc-sections
       │
       ▼
KEEP()
```

顺序上可以理解成两个阶段。

---

# 二十四、实验 10-4：两个库互相依赖

现在做真正有意思的实验。

建立：

```text
libA.a
├── a.o

libB.a
├── b.o
```

---

## `a.c`

```c
extern int b(void);

int a(void)
{
    return b() + 1;
}
```

---

## `b.c`

```c
extern int a(void);

int b(void)
{
    return a() + 1;
}
```

注意：

```text
a → b
b → a
```

形成：

```text
      ┌───────┐
      │       ▼
    a.o → b
     ↑       │
     │       ▼
     └──── b.o
```

这是典型循环依赖。

---

# 二十五、main.c

改成：

```c
extern int a(void);

int main(void)
{
    return a();
}
```

---

# 二十六、编译

```bash
gcc -c main.c -o main.o
gcc -c a.c -o a.o
gcc -c b.c -o b.o
```

创建：

```bash
ar rcs libA.a a.o
ar rcs libB.a b.o
```

---

# 二十七、第一次链接

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    libA.a \
    libB.a \
    -o circular.elf \
    -Map=circular.map
```

这里要仔细观察结果。

处理过程：

```text
main.o
   ↓
undefined a

libA.a
   ↓
找到 a.o
   ↓
提取 a.o

a.o
   ↓
产生 undefined b

libB.a
   ↓
找到 b.o
   ↓
提取 b.o

b.o
   ↓
需要 a

a 已经存在
   ↓
解决
```

因此这个简单例子：

```text
libA.a libB.a
```

**可能是可以成功的。**

这点非常重要：

> “有循环依赖”并不意味着两个 archive 放一起一定失败。

失败通常发生在更复杂的：

```text
A 中多个成员
B 中多个成员
```

相互触发的情况下。

---

# 二十八、制造真正的循环 Archive 问题

建立：

```text
A1.o
A2.o

B1.o
B2.o
```

让：

```text
A1 → B2
B1 → A2
A2 → B1
```

这种情况下，单次从左到右扫描可能无法解决所有依赖。

这是 archive link order 最经典的坑。

---

# 二十九、解决方案：重复库

最简单的办法之一：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    libA.a \
    libB.a \
    libA.a \
    -o repeat.elf
```

为什么？

第一次：

```text
libA.a
 ↓
提取部分成员
```

然后：

```text
libB.a
 ↓
提取部分成员
```

再次：

```text
libA.a
 ↓
发现新的 undefined
 ↓
提取之前没提取的成员
```

---

# 三十、正式方案：`--start-group`

GNU ld 提供：

```bash
--start-group
--end-group
```

例如：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    --start-group \
    libA.a \
    libB.a \
    --end-group \
    -o group.elf \
    -Map=group.map
```

linker 会反复扫描：

```text
libA.a
libB.a
libA.a
libB.a
...
```

直到：

```text
没有新的 archive member 可以被提取
```

这就是：

```text
Group Search
```

---

# 三十一、把它理解成固定点算法

普通 archive：

```text
A
 ↓
扫描一次
 ↓
结束
```

Group：

```text
A
 ↓
B
 ↓
A
 ↓
B
 ↓
...
 ↓
直到稳定
```

可以抽象成：

```text
Symbols(n+1)
=
Resolve(
    Symbols(n),
    Archives
)
```

直到：

```text
Symbols(n+1) == Symbols(n)
```

也就是：

```text
达到 fixed point
```

这就是 `--start-group` 非常漂亮的本质。

---

# 三十二、但是 `--start-group` 不是免费的

因为它可能：

```text
反复扫描 archive
```

大型工程：

```text
1000 个 archive
```

如果大量使用：

```bash
--start-group
```

链接时间可能明显增加。

所以通常：

```text
优先正确安排库顺序
        ↓
只有真正循环依赖时
        ↓
使用 --start-group
```

---

# 三十三、今天一定要做的 Map 分析

对于：

```text
normal.elf
whole.elf
group.elf
```

分别：

```bash
grep -A 30 -B 5 "Archive" normal.map
```

以及：

```bash
grep -A 30 -B 5 "libfoo.a" normal.map
```

观察：

```text
foo.o
bar.o
```

到底哪些进入了最终链接。

这一步特别重要，因为：

```text
命令行
```

只能告诉你：

```text
“我写了 libfoo.a”
```

而：

```text
map
```

告诉你：

> **linker 最终到底从这个 archive 里面拿了什么。**

---

# 三十四、再用 `nm` 做最终验证

普通链接：

```bash
nm -n normal.elf | grep -E 'foo|bar'
```

应该：

```text
foo
```

而没有：

```text
bar
```

`--whole-archive`：

```bash
nm -n whole.elf | grep -E 'foo|bar'
```

应该：

```text
foo
bar
```

于是：

```text
normal.elf
    ↓
foo.o extracted

whole.elf
    ↓
foo.o + bar.o extracted
```

---

# 三十五、再用 `objdump` 验证机器码

```bash
objdump -d normal.elf
```

寻找：

```text
<foo>
```

然后：

```bash
objdump -d whole.elf
```

寻找：

```text
<foo>
<bar>
```

所以现在我们有完整证据链：

```text
Archive
   │
   ▼
Map
   │
   ▼
Symbol
   │
   ▼
Machine Code
```

---

# 三十六、今天最重要的符号状态变化

整个过程可以画成：

```text
main.o
   │
   ▼
Undefined foo
   │
   ▼
扫描 libfoo.a
   │
   ▼
foo.o
   │
   ▼
Defined foo
   │
   ▼
foo.o 被加入链接
```

如果：

```text
libfoo.a
```

在：

```text
main.o
```

之前：

```text
扫描库
   ↓
当前没有 foo undefined
   ↓
不提取 foo.o
   ↓
main.o 出现 undefined foo
   ↓
库已经扫描完
   ↓
失败
```

这就是：

> **Archive 搜索顺序依赖当前 symbol state。**

---

# 三十七、把 `.a` 和 `--gc-sections` 再连接起来

这里有一个非常重要的双层过滤：

```text
libfoo.a
│
├── foo.o
├── bar.o
└── baz.o
      │
      ▼
Archive extraction
      │
      ├── foo.o
      └── bar.o
             │
             ▼
       --gc-sections
             │
             ▼
        Input Section
             │
             ▼
          KEEP()
```

也就是说：

### 第一关

```text
Archive
```

决定：

> `.a` 中哪个 `.o` 进入链接。

### 第二关

```text
--gc-sections
```

决定：

> 进入链接的 Input Section 哪些最终保留。

这是非常重要的区别。

---

# 三十八、因此出现一个经典现象

你可能看到：

```text
libfoo.a
```

明明包含：

```text
foo.o
```

但最终：

```bash
nm firmware.elf
```

找不到：

```text
foo
```

这时不能只问：

> “库有没有？”

而应该依次检查：

```text
① Archive 有没有被搜索到？

② Archive 中的 foo.o 有没有被提取？

③ foo.o 中的 .text.foo 有没有进入 Output Section？

④ --gc-sections 有没有把它回收？

⑤ 有没有 linker script / KEEP / symbol visibility 等因素？
```

这就是以后排查链接问题的标准思路。

---

# 三十九、实验 10 总结

今天真正掌握了：

```text
ar
```

创建 archive：

```bash
ar rcs libfoo.a foo.o bar.o
```

查看：

```bash
ar t libfoo.a
```

符号：

```bash
nm -s libfoo.a
```

---

## 普通 Archive

```text
main.o libfoo.a
```

依赖者在前：

```text
main → foo
```

通常正确。

---

## `--whole-archive`

```bash
--whole-archive
libfoo.a
--no-whole-archive
```

强制提取所有成员。

---

## `--start-group`

```bash
--start-group
libA.a
libB.a
--end-group
```

用于解决多个 archive 之间复杂的循环依赖。

---

# 四十、今天的完整知识图

```text
                         ld
                          │
                ┌─────────┴─────────┐
                │                   │
              .o                  .a
                │                   │
                │             Archive Search
                │                   │
                │             ┌─────┴─────┐
                │             ▼           ▼
                │          extract      ignore
                │             │
                └──────┬──────┘
                       ▼
                 Symbol Resolution
                       │
                       ▼
                    Sections
                       │
                       ▼
                 --gc-sections
                       │
                ┌──────┴──────┐
                ▼             ▼
              delete         KEEP
                │             │
                └──────┬──────┘
                       ▼
                    ELF
                       │
             ┌─────────┼─────────┐
             ▼         ▼         ▼
          readelf    objdump     nm
             │         │         │
             └─────────┼─────────┘
                       ▼
                    map file
```

---

# 四十一、下一实验：Weak / Strong / COMMON

下一节进入 GNU ld **符号解析最容易出坑的一关**：

# 实验 11：Strong、Weak、COMMON——到底谁覆盖谁？

我们会制造：

```c
// a.c
int value = 100;
```

```c
// b.c
int value = 200;
```

然后直接：

```bash
ld a.o b.o
```

观察：

```text
multiple definition of `value'
```

再改成：

```c
__attribute__((weak))
int value = 100;
```

观察：

```text
strong
   ↓
覆盖
   ↓
weak
```

然后进入：

```text
COMMON symbol
```

使用：

```c
int value;
```

结合：

```bash
-fcommon
-fno-common
```

观察 GCC 与 `ld` 在 COMMON 符号上的历史行为差异。

最终建立真正完整的符号解析模型：

```text
             Symbol Resolution
                     │
       ┌─────────────┼─────────────┐
       ▼             ▼             ▼
    Strong          Weak        COMMON
       │             │             │
       └──────┬──────┴─────────────┘
              ▼
          ld 决策
              │
              ▼
       最终唯一地址
```

这一关之后，再结合今天的 `.a`，就能解释大量经典错误：

```text
multiple definition
undefined reference
weak symbol
library order
COMMON
```

到那时，GNU `ld` 的 **Symbol Resolution** 这条主线就真正打通了。

