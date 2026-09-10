# GNU ld 实战课程 · 实验 11

## Strong / Weak / COMMON：GNU ld 到底如何决定“谁的符号有效”？

上一节我们已经打通了：

```text
.a
 ↓
Archive Member 提取
 ↓
Symbol Resolution
 ↓
--gc-sections
 ↓
KEEP()
```

今天正式进入 `ld` 最核心的一条主线：

```text
                    Symbol Resolution
                           │
             ┌─────────────┼─────────────┐
             ▼             ▼             ▼
          Strong          Weak         COMMON
             │             │             │
             └─────────────┼─────────────┘
                           ▼
                    linker 最终决策
                           │
                           ▼
                     一个最终地址
```

这节实验特别值得亲自跑，因为很多看起来“莫名其妙”的：

```text
multiple definition of xxx
undefined reference to xxx
weak symbol
```

本质都是 **符号绑定属性 + ld 的符号解析规则**。

---

# 一、先建立 ELF Symbol 的三个关键维度

以后看到：

```bash
readelf -s xxx.o
```

不要只看：

```text
Name
Value
```

至少要关注：

```text
Bind
Type
Ndx
```

例如：

```text
Bind = GLOBAL
Bind = WEAK
```

其中最重要的是：

```text
GLOBAL
WEAK
```

可以先粗略理解成：

```text
GLOBAL
   ↓
Strong symbol

WEAK
   ↓
Weak symbol
```

而 `COMMON` 则是另一种状态，它通常表现为：

```text
Ndx = COM
```

---

# 二、实验目录

创建：

```text
ld-lab/
├── start.S
├── main.c
├── strong_a.c
├── strong_b.c
├── weak_a.c
├── common_a.c
├── linker.ld
└── Makefile
```

今天先不需要复杂 linker script。

---

# 三、公共 `start.S`

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

# 四、公共 linker.ld

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

    .rodata :
    {
        *(.rodata)
        *(.rodata.*)
    } > ROM :text

    .data :
    {
        *(.data)
        *(.data.*)
    } > ROM :text

    .bss :
    {
        *(.bss)
        *(.bss.*)
        *(COMMON)
    } > ROM :text
}
```

这里：

```ld
*(COMMON)
```

先保留着。

后面我们会看到它为什么重要。

---

# 五、实验 11-1：两个 Strong Symbol 冲突

创建 `strong_a.c`：

```c
int value = 100;
```

创建 `strong_b.c`：

```c
int value = 200;
```

这里：

```text
strong_a.o
    │
    └── value = 100

strong_b.o
    │
    └── value = 200
```

两个都是：

```text
GLOBAL
```

也就是：

```text
Strong
```

---

# 六、编译

```bash
gcc -c strong_a.c -o strong_a.o
gcc -c strong_b.c -o strong_b.o
gcc -c main.c -o main.o
gcc -c start.S -o start.o
```

先看：

```bash
nm strong_a.o
```

应该类似：

```text
0000000000000000 D value
```

再：

```bash
nm strong_b.o
```

同样：

```text
0000000000000000 D value
```

注意这里的：

```text
D
```

表示 `.data` 中的已定义数据符号。

---

# 七、用 `readelf -s` 看得更详细

```bash
readelf -s strong_a.o
```

找到：

```text
value
```

重点观察：

```text
Bind
Ndx
```

应该类似：

```text
GLOBAL
.data
```

`strong_b.o` 同理。

---

# 八、第一次链接

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    strong_a.o \
    strong_b.o \
    -o strong-conflict.elf \
    -Map=strong-conflict.map
```

你应该得到类似：

```text
multiple definition of `value'
```

这正是我们预期的。

---

# 九、为什么 ld 不“随便选一个”？

因为：

```text
strong_a.o
    value = 100

strong_b.o
    value = 200
```

两个都是：

```text
GLOBAL
```

如果 linker 随便选：

```text
value = 100
```

那么：

```text
value = 200
```

就会悄悄消失。

这会导致：

```text
程序行为依赖链接顺序
```

而这对大型工程非常危险。

所以 GNU ld 默认选择：

```text
multiple strong definitions
        ↓
报错
```

---

# 十、实验 11-2：Strong + Weak

现在我们把 `strong_b.c` 改成：

```c
int value = 200;
```

然后新建 `weak_a.c`：

```c
__attribute__((weak))
int value = 100;
```

现在：

```text
weak_a.o
    value → WEAK

strong_b.o
    value → GLOBAL
```

---

# 十一、查看 symbol

```bash
gcc -c weak_a.c -o weak_a.o
```

然后：

```bash
nm weak_a.o
```

通常会看到：

```text
W value
```

而：

```bash
nm strong_b.o
```

仍然：

```text
D value
```

所以：

```text
W
↓
Weak

D
↓
Strong data
```

---

# 十二、链接 Strong + Weak

创建一个新的 main：

```c
extern int value;

int main(void)
{
    return value;
}
```

编译：

```bash
gcc -c main.c -o main.o
```

链接：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    weak_a.o \
    strong_b.o \
    -o weak-strong.elf \
    -Map=weak-strong.map
```

这次应该成功。

---

# 十三、运行

```bash
./weak-strong.elf
echo $?
```

应该得到：

```text
200
```

而不是：

```text
100
```

也就是说：

```text
WEAK value = 100
GLOBAL value = 200

             ↓

GLOBAL 胜出

             ↓

最终 value = 200
```

---

# 十四、用 `nm` 验证

```bash
nm -n weak-strong.elf | grep value
```

最终只应该有一个：

```text
value
```

然后：

```bash
readelf -s weak-strong.elf | grep value
```

观察最终 symbol 的：

```text
Bind
```

最终应该是：

```text
GLOBAL
```

这就是非常经典的：

> **Strong overrides Weak**

---

# 十五、为什么 Weak Symbol 有用？

这其实是一个非常漂亮的工程机制。

假设库提供：

```c
__attribute__((weak))
void board_init(void)
{
}
```

默认：

```text
board_init()
```

什么都不做。

用户工程如果需要：

```c
void board_init(void)
{
    // 自己实现
}
```

那么：

```text
用户 Strong
     ↓
覆盖
     ↓
库 Weak
```

于是：

```text
默认行为
+
用户可覆盖
```

这就是 Weak Symbol 最经典的用途之一。

---

# 十六、做一个更典型的 Weak Hook

创建：

```text
default.c
```

```c
__attribute__((weak))
void app_hook(void)
{
}
```

创建：

```text
main.c
```

```c
extern void app_hook(void);

int main(void)
{
    app_hook();

    return 42;
}
```

如果只链接：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    default.o \
    -o default-hook.elf
```

使用：

```text
default app_hook
```

如果工程增加：

```text
user_hook.o
```

里面：

```c
void app_hook(void)
{
    // user implementation
}
```

那么：

```text
user_hook.o
     ↓
Strong app_hook

default.o
     ↓
Weak app_hook
```

最终：

```text
Strong
  ↓
覆盖
  ↓
Weak
```

这就是嵌入式 SDK、底层库中非常常见的模式。

---

# 十七、实验 11-3：Weak + Weak

现在更有意思。

创建：

### weak_a.c

```c
__attribute__((weak))
int value = 100;
```

### weak_b.c

```c
__attribute__((weak))
int value = 200;
```

编译：

```bash
gcc -c weak_a.c -o weak_a.o
gcc -c weak_b.c -o weak_b.o
```

然后：

```bash
nm weak_a.o
nm weak_b.o
```

两个都是：

```text
W value
```

---

# 十八、链接两个 Weak

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    weak_a.o \
    weak_b.o \
    -o weak-weak.elf \
    -Map=weak-weak.map
```

这次通常不会出现：

```text
multiple definition
```

因为两个都是 Weak。

但是：

> **到底选择哪一个？**

这正是下一层要观察的地方。

---

# 十九、千万不要把 Weak + Weak 当成 Strong + Weak

规则不是：

```text
Weak + Weak
    ↓
两个都合并
```

而是：

```text
Weak + Weak
    ↓
linker 选择一个
```

具体选择行为应以目标格式、linker 实现及输入顺序等为准。

因此工程上最稳妥的原则是：

```text
不要依赖多个同名 Weak Symbol 之间的“胜负”
```

Weak 最适合：

```text
Weak 默认实现
        +
一个 Strong 用户实现
```

而不是：

```text
Weak A
Weak B
Weak C
```

互相竞争。

---

# 二十、实验 11-4：COMMON Symbol

现在进入历史上非常重要的一类：

```text
COMMON
```

创建：

```text
common_a.c
```

```c
int value;
```

注意：

```c
int value;
```

没有初始化。

在 GCC 某些编译选项/版本下，它可能产生 COMMON symbol。

---

# 二十一、显式使用 `-fcommon`

为了让实验结果明确，我们直接：

```bash
gcc -fcommon -c common_a.c -o common_a.o
```

然后：

```bash
nm common_a.o
```

你可能看到：

```text
0000000000000004 C value
```

这里：

```text
C
```

表示：

```text
COMMON
```

---

# 二十二、`readelf -s`

```bash
readelf -s common_a.o
```

寻找：

```text
value
```

你会看到它的：

```text
Ndx
```

表现为：

```text
COM
```

这与：

```text
.data
.bss
```

不同。

---

# 二十三、COMMON 到底是什么意思？

历史上：

```c
int value;
```

这类未初始化的全局定义可能被编译器表示为：

```text
COMMON
```

它表达的意思大致是：

> “我需要一个叫 `value` 的未初始化存储空间。”

最终 linker 决定：

```text
value
 ↓
放在哪里
 ↓
通常归入 .bss
```

所以：

```text
COMMON
   ↓
linker allocation
   ↓
.bss
```

---

# 二十四、制造两个 COMMON

创建：

### common_a.c

```c
int value;
```

### common_b.c

```c
int value;
```

使用：

```bash
gcc -fcommon -c common_a.c -o common_a.o
gcc -fcommon -c common_b.c -o common_b.o
```

然后：

```bash
nm common_a.o
nm common_b.o
```

两个都应该类似：

```text
C value
```

---

# 二十五、链接两个 COMMON

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    common_a.o \
    common_b.o \
    -o common.elf \
    -Map=common.map
```

通常不会像：

```text
GLOBAL + GLOBAL
```

那样直接报：

```text
multiple definition
```

因为 COMMON 的语义不同。

---

# 二十六、观察最终 `.bss`

```bash
readelf -S common.elf
```

寻找：

```text
.bss
```

再：

```bash
nm -n common.elf | grep value
```

最终：

```text
value
```

会落在：

```text
.bss
```

---

# 二十七、两个 COMMON 的空间怎么办？

假设：

```text
common_a:
int a;

common_b:
int a;
```

linker 需要一个最终的：

```text
a
```

它会处理 COMMON allocation，并为其分配存储空间。

如果不同对象对同名 COMMON 的大小要求不同：

```text
A:
a = 4 bytes

B:
a = 100 bytes
```

linker 会按照 COMMON 的规则处理最终空间需求，而不是简单地把两个变量拼成：

```text
4 + 100
```

这里一定不要把 COMMON 想象成普通 `.bss` Input Section。

---

# 二十八、`*(COMMON)` 为什么出现在 linker script？

还记得我们之前写：

```ld
.bss :
{
    *(.bss)
    *(.bss.*)
    *(COMMON)
} > ROM :text
```

这里：

```ld
*(COMMON)
```

就是告诉 linker：

> **把 COMMON symbols 分配到这个 Output Section。**

传统 linker script 中：

```ld
*(COMMON)
```

经常放进：

```text
.bss
```

于是：

```text
COMMON
   │
   ▼
.bss
```

这就是它的经典用法。

---

# 二十九、但是现代 GCC 为什么经常看不到 COMMON？

这是一个非常重要的现实问题。

现代 GCC 默认行为通常倾向于：

```text
-fno-common
```

也就是说：

```c
int value;
```

通常直接作为：

```text
.bss
```

定义处理。

所以你可能发现：

```bash
gcc -c common_a.c -o common_a.o
nm common_a.o
```

不是：

```text
C value
```

而是：

```text
B value
```

这并不是实验错了。

这是 GCC 编译选项行为导致的。

如果你想专门研究传统 COMMON：

```bash
gcc -fcommon -c common_a.c -o common_a.o
```

---

# 三十、`-fcommon` vs `-fno-common`

可以这样记：

```text
-fcommon
    ↓
未初始化全局定义
    ↓
可能进入 COMMON

-fno-common
    ↓
直接产生真正的定义
    ↓
通常进入 .bss
```

因此：

```text
旧时代 C 编译行为
        ↓
COMMON 很常见

现代 GCC
        ↓
-fno-common
        ↓
COMMON 少很多
```

---

# 三十一、为什么现代 GCC 倾向 `-fno-common`？

看这个经典问题：

### a.c

```c
int value;
```

### b.c

```c
int value;
```

如果采用 COMMON 传统语义：

```text
两个“暂时定义”
        ↓
linker 合并
```

程序可能悄悄成功。

但这很容易掩盖：

> **程序员实际上定义了两个同名全局变量。**

使用：

```text
-fno-common
```

则更早暴露问题：

```text
a.o
 value → .bss

b.o
 value → .bss

       ↓

multiple definition
```

所以错误更容易被发现。

---

# 三十二、现在把 Strong / Weak / COMMON 放到一起

可以先记住这个简化优先级：

```text
              Strong
                 │
                 ▼
               Weak
                 │
                 ▼
              COMMON
```

但这个图不能机械理解成“所有场景只有一个绝对排序”。

更准确地说：

```text
多个同名 Symbol
       │
       ├── Strong + Strong
       │       ↓
       │   通常报错
       │
       ├── Strong + Weak
       │       ↓
       │   Strong 胜出
       │
       ├── Weak + Weak
       │       ↓
       │   可选取一个
       │
       └── COMMON
               ↓
         特殊分配语义
```

这比简单记“Strong > Weak > Common”更加准确。

---

# 三十三、用 `nm` 建立快速判断能力

以后看到：

```bash
nm xxx.o
```

如果：

```text
T foo
```

表示：

```text
foo
→ .text 中的强定义
```

如果：

```text
W foo
```

表示：

```text
foo
→ Weak
```

如果：

```text
U foo
```

表示：

```text
foo
→ Undefined
```

如果：

```text
C foo
```

表示：

```text
foo
→ COMMON
```

如果：

```text
D foo
```

表示：

```text
foo
→ .data 中定义
```

如果：

```text
B foo
```

表示：

```text
foo
→ .bss 中定义
```

这张表非常值得记：

| `nm` | 含义            |
| ---- | ------------- |
| `T`  | `.text` 强定义   |
| `t`  | `.text` local |
| `D`  | `.data`       |
| `B`  | `.bss`        |
| `W`  | Weak          |
| `U`  | Undefined     |
| `C`  | COMMON        |

---

# 三十四、再用 `readelf -s` 进行精确验证

当 `nm` 不够时：

```bash
readelf -s xxx.o
```

重点看：

```text
Num
Value
Size
Type
Bind
Vis
Ndx
Name
```

例如：

```text
GLOBAL
```

和：

```text
WEAK
```

是：

```text
Bind
```

而：

```text
.data
.bss
COM
```

主要体现在：

```text
Ndx
```

这两个维度不要混淆。

---

# 三十五、实验 11-5：用 map 看“谁赢了”

对于：

```text
weak-strong.elf
```

执行：

```bash
grep -A 30 -B 5 "value" weak-strong.map
```

再：

```bash
nm -n weak-strong.elf | grep value
```

以及：

```bash
readelf -s weak-strong.elf | grep value
```

三个结果对照：

```text
源文件
 ↓
.o
 ↓
nm/readelf
 ↓
ld symbol resolution
 ↓
最终 ELF
 ↓
map
```

这就是今天最完整的验证链。

---

# 三十六、再观察 relocation

如果：

```c
extern int value;

int main(void)
{
    return value;
}
```

那么：

```bash
readelf -r main.o
```

应该看到：

```text
value
```

相关 relocation。

也就是说：

```text
main.o
   │
   └── relocation → value
                       │
                       ▼
                linker resolution
                       │
             ┌─────────┴─────────┐
             ▼                   ▼
       weak value           strong value
             │                   │
             └─────────┬─────────┘
                       ▼
                  最终地址
```

这把：

```text
Symbol Resolution
```

和我们实验 01 的：

```text
Relocation
```

重新连接起来了。

---

# 三十七、现在回头看 `.a`

上一节我们学：

```text
main.o
  ↓
undefined foo
  ↓
libfoo.a
  ↓
提取 foo.o
```

今天我们又知道：

```text
foo.o
   ↓
Strong / Weak / COMMON
```

因此 `.a` 的成员提取其实也依赖：

```text
Symbol Resolution
```

整个过程：

```text
main.o
 │
 │ U foo
 ▼
libfoo.a
 │
 │ foo.o
 ▼
GLOBAL foo
 │
 ▼
resolve
 │
 ▼
relocation
```

所以：

> **Archive 和 Symbol Resolution 不是两门孤立知识，而是一条链。**

---

# 三十八、再把 `--gc-sections` 接回来

如果：

```text
foo.o
```

被 archive 提取出来之后：

```text
--gc-sections
```

仍然可能继续检查：

```text
foo.o
 ├── .text.foo
 ├── .text.unused
 └── .data.foo
```

然后：

```text
.text.foo
    ↓
reachable
    ↓
保留

.text.unused
    ↓
unreachable
    ↓
删除
```

所以现在完整链条是：

```text
.a
 │
 ▼
Archive Extraction
 │
 ▼
.o
 │
 ▼
Symbol Resolution
 │
 ▼
Input Sections
 │
 ▼
GC
 │
 ▼
KEEP
 │
 ▼
Section Layout
 │
 ▼
Relocation
 │
 ▼
ELF
```

这已经是 GNU `ld` 最核心的工作流之一。

---

# 三十九、今天推荐你实际跑的命令

## Strong 冲突

```bash
gcc -c strong_a.c -o strong_a.o
gcc -c strong_b.c -o strong_b.o

nm strong_a.o
nm strong_b.o

readelf -s strong_a.o
readelf -s strong_b.o

ld -T linker.ld \
   start.o main.o \
   strong_a.o strong_b.o \
   -o strong-conflict.elf \
   -Map=strong-conflict.map
```

---

## Strong + Weak

```bash
gcc -c weak_a.c -o weak_a.o
gcc -c strong_b.c -o strong_b.o

nm weak_a.o
nm strong_b.o

ld -T linker.ld \
   start.o main.o \
   weak_a.o strong_b.o \
   -o weak-strong.elf \
   -Map=weak-strong.map
```

然后：

```bash
./weak-strong.elf
echo $?
```

---

## COMMON

```bash
gcc -fcommon -c common_a.c -o common_a.o
gcc -fcommon -c common_b.c -o common_b.o

nm common_a.o
nm common_b.o

readelf -s common_a.o
readelf -s common_b.o
```

然后：

```bash
ld -T linker.ld \
   start.o main.o \
   common_a.o common_b.o \
   -o common.elf \
   -Map=common.map
```

---

# 四十、今天最重要的“排错顺序”

以后遇到：

```text
undefined reference to xxx
```

建议按：

```text
① nm xxx.o
② nm libxxx.a
③ readelf -s
④ 检查 .a 顺序
⑤ 检查 archive 是否真的提取
⑥ 检查 --gc-sections
⑦ 检查 KEEP
⑧ 检查 linker script
```

如果遇到：

```text
multiple definition of xxx
```

先：

```bash
nm -A *.o
```

找：

```text
xxx
```

然后判断：

```text
GLOBAL + GLOBAL
```

还是：

```text
GLOBAL + WEAK
```

还是：

```text
COMMON + COMMON
```

不同组合，处理方式完全不同。

---

# 四十一、到这里，学习路线进入一个关键节点

前 11 个实验已经从“会写 linker script”逐渐转变成：

```text
                         GNU ld
                           │
             ┌─────────────┴─────────────┐
             │                           │
          Input Files                 Script
             │                           │
      ┌──────┼──────┐              ┌─────┴─────┐
      ▼      ▼      ▼              ▼           ▼
     .o     .a     .so          SECTIONS     MEMORY
      │      │
      │      ▼
      │  Archive Search
      │
      └──────┬──────────────┐
             ▼              ▼
        Symbol Resolution   Section Layout
             │              │
      ┌──────┼──────┐       ├── ALIGN
      ▼      ▼      ▼       ├── SUBALIGN
   Strong   Weak  COMMON    └── KEEP
             │
             ▼
          Relocation
             │
             ▼
          ELF Output
             │
       ┌─────┼─────┐
       ▼     ▼     ▼
    readelf objdump nm
             │
             ▼
          map file
```

---

# 四十二、下一实验：`ld` 的“符号追踪器”

下一节建议进入：

## 实验 12：`--trace-symbol` + `-y` + Map —— 追踪一个 Symbol 的完整生命周期

我们不再只是问：

> “这个符号在哪里？”

而是让 `ld` 直接告诉我们：

```text
谁引用它
   ↓
谁定义它
   ↓
哪个 archive member 被提取
   ↓
最终地址是多少
```

实验会构造：

```text
main.o
   │
   │ U foo
   ▼
libA.a
   │
   └── a.o
          │
          │ U foo
          ▼
libB.a
   │
   └── b.o
          │
          └── T foo
```

然后使用：

```bash
ld --trace-symbol=foo ...
```

配合：

```bash
nm
readelf -s
readelf -r
objdump -dr
```

最终画出：

```text
                foo

main.o ──────────────┐
                     │ reference
                     ▼
                  Symbol
                     ▲
                     │ definition
                     │
libB.a → b.o ────────┘

          ↓

      ld resolution

          ↓

      final address

          ↓

      relocation resolved
```

这一节之后，**Symbol Resolution、Archive Search、Relocation** 三条主线就真正汇合了。

