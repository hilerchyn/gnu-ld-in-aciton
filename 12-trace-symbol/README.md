# GNU ld 实战课程 · 实验 12

## `--trace-symbol` + `-y` + `readelf -r`：追踪一个 Symbol 的完整生命周期

上一节我们已经把：

```text
.a
 ↓
Archive Member 提取
 ↓
Strong / Weak / COMMON
 ↓
Symbol Resolution
```

打通了。

这一节继续往前走，不再只是判断“符号存在不存在”，而是做一次真正的 **Symbol 追踪实验**：

```text
源代码
  ↓
.o
  ↓
Undefined Symbol
  ↓
Archive Search
  ↓
Definition
  ↓
Symbol Resolution
  ↓
Relocation
  ↓
最终 ELF 地址
```

GNU `ld` 官方文档明确说明，`-y symbol` / `--trace-symbol=symbol` 会打印该 symbol 出现在哪些参与链接的文件中，这个选项尤其适合排查“这个 undefined symbol 到底是谁引用的”。([Sourceware][1])

---

# 一、今天的实验目标

我们构造这样一条依赖链：

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

最终得到：

```text
main.o
   │
   │ reference
   ▼
 foo
   ▲
   │ definition
   │
 b.o
```

然后用五种工具分别观察：

```text
nm
readelf -s
readelf -r
objdump -dr
ld --trace-symbol=foo
```

最后再通过：

```text
map
```

把整个过程串起来。

---

# 二、实验目录

```text
ld-lab/
├── main.c
├── a.c
├── b.c
├── start.S
└── linker.ld
```

---

# 三、main.c

```c
extern int a(void);

int main(void)
{
    return a();
}
```

这里：

```text
main()
   ↓
a()
```

所以：

```text
main.o
```

会产生：

```text
U a
```

---

# 四、a.c

```c
extern int foo(void);

int a(void)
{
    return foo() + 1;
}
```

所以：

```text
a.o
```

同时拥有：

```text
T a
U foo
```

也就是说：

```text
a.o
 ├── defines a
 └── references foo
```

---

# 五、b.c

```c
int foo(void)
{
    return 40;
}
```

所以：

```text
b.o
```

只有：

```text
T foo
```

---

# 六、start.S

继续使用我们的最小启动代码：

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

---

# 八、第一步：编译所有 `.o`

```bash
gcc -c main.c -o main.o
gcc -c a.c -o a.o
gcc -c b.c -o b.o
gcc -c start.S -o start.o
```

---

# 九、先用 `nm` 看符号

## main.o

```bash
nm main.o
```

应该看到类似：

```text
                 U a
0000000000000000 T main
```

也就是：

```text
main
 └── T main

a
 └── U a
```

---

# 十、观察 a.o

```bash
nm a.o
```

应该类似：

```text
0000000000000000 T a
                 U foo
```

这里非常关键：

```text
T a
```

表示：

```text
a 被 a.o 定义
```

而：

```text
U foo
```

表示：

```text
foo 尚未解决
```

---

# 十一、观察 b.o

```bash
nm b.o
```

应该：

```text
0000000000000000 T foo
```

于是现在整个依赖关系已经可以画出来：

```text
main.o
    │
    └── U a
          │
          ▼
        a.o
          │
          ├── T a
          │
          └── U foo
                │
                ▼
              b.o
                │
                └── T foo
```

---

# 十二、第二步：建立两个静态库

```bash
ar rcs libA.a a.o
ar rcs libB.a b.o
```

检查：

```bash
ar t libA.a
```

得到：

```text
a.o
```

检查：

```bash
ar t libB.a
```

得到：

```text
b.o
```

---

# 十三、现在链接

顺序：

```text
main.o
libA.a
libB.a
```

命令：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    libA.a \
    libB.a \
    -o trace.elf \
    -Map=trace.map
```

应该成功。

运行：

```bash
./trace.elf
echo $?
```

结果：

```text
41
```

因为：

```text
foo() = 40

a()
 = foo() + 1
 = 41

main()
 = a()
 = 41
```

---

# 十四、现在使用 `--trace-symbol=foo`

重新链接：

```bash
ld \
    -T linker.ld \
    --trace-symbol=foo \
    start.o \
    main.o \
    libA.a \
    libB.a \
    -o trace-symbol.elf \
    -Map=trace-symbol.map
```

这里：

```text
--trace-symbol=foo
```

就是今天的主角。

GNU `ld` 文档定义它为：

```text
-y symbol
--trace-symbol=symbol
```

并说明它会打印该 symbol 出现在哪些被链接文件中。([Sourceware][1])

---

# 十五、你应该看到什么？

输出通常会包含类似：

```text
a.o: reference to foo
b.o: definition of foo
```

不同 binutils 版本的具体文字可能略有差异，但核心信息是：

```text
a.o
 ↓
reference foo

b.o
 ↓
definition foo
```

这比单纯：

```bash
nm
```

更进一步。

因为：

```bash
nm a.o
```

只告诉你：

```text
a.o 有 U foo
```

而：

```bash
ld --trace-symbol=foo
```

告诉你：

> **linker 在这次实际链接过程中观察到了 foo 的引用/定义。**

---

# 十六、`-y foo` 是短写法

下面：

```bash
ld \
    -T linker.ld \
    -y foo \
    start.o \
    main.o \
    libA.a \
    libB.a \
    -o trace-short.elf
```

与：

```bash
ld \
    -T linker.ld \
    --trace-symbol=foo \
    ...
```

是同一个功能。

官方文档明确将：

```text
-y symbol
```

列为：

```text
--trace-symbol=symbol
```

的短形式。([Sourceware][1])

---

# 十七、同时追踪两个 Symbol

我们可以：

```bash
ld \
    -T linker.ld \
    --trace-symbol=a \
    --trace-symbol=foo \
    start.o \
    main.o \
    libA.a \
    libB.a \
    -o trace-two.elf
```

现在可以观察：

```text
a
foo
```

整个链条：

```text
main.o → a
a.o    → foo
b.o    → foo
```

---

# 十八、第三步：观察 Relocation

现在开始进入真正重要的一步。

```bash
readelf -r main.o
```

你应该看到：

```text
a
```

相关 relocation。

然后：

```bash
readelf -r a.o
```

你应该看到：

```text
foo
```

相关 relocation。

于是：

```text
main.o
   │
   └── relocation → a

a.o
   │
   └── relocation → foo
```

而：

```text
b.o
   │
   └── defines foo
```

---

# 十九、用 `objdump -dr` 一次看机器码 + relocation

这是我非常推荐掌握的命令：

```bash
objdump -dr main.o
```

以及：

```bash
objdump -dr a.o
```

为什么用：

```text
-dr
```

？

因为：

```text
-d
```

反汇编。

而：

```text
-r
```

显示 relocation。

所以：

```bash
objdump -dr a.o
```

会把：

```text
机器指令
+
relocation
```

放在一起。

这对理解 linker 非常有帮助。

---

# 二十、你会看到类似这样的东西

`a.o` 中可能类似：

```text
0000000000000000 <a>:
   ...
   call   ...
            R_X86_64_PLT32    foo-0x4
```

这里不要死记：

```text
R_X86_64_PLT32
```

我们目前真正需要理解的是：

```text
call
 │
 └── relocation
       │
       └── foo
```

也就是：

> 编译器生成 `a()` 时，并不知道 `foo()` 最终在哪个地址，所以先留下 relocation。

---

# 二十一、链接前 vs 链接后

## 链接前

```text
a.o

call ?
     │
     └── relocation → foo
```

## 链接后

```text
trace.elf

call 0x400xxx
        ↑
        │
      foo
```

这就是：

```text
Relocation Resolution
```

---

# 二十二、第四步：反汇编最终 ELF

```bash
objdump -d trace.elf
```

找到：

```text
<main>
```

然后：

```text
<a>
```

然后：

```text
<foo>
```

形成：

```text
main
 │
 │ call
 ▼
a
 │
 │ call
 ▼
foo
```

---

# 二十三、用 `nm` 看最终地址

```bash
nm -n trace.elf | grep -E 'main| a$|foo'
```

可能得到：

```text
00000000004000xx T _start
00000000004000xx T main
00000000004000xx T a
00000000004000xx T foo
```

现在：

```text
foo
```

已经不再是：

```text
U foo
```

而是：

```text
T foo
```

而且：

```text
Value
```

已经有了最终 VMA。

---

# 二十四、第五步：用 `readelf -s` 验证

```bash
readelf -s trace.elf | grep -E 'main| a$|foo'
```

重点观察：

```text
Value
Size
Type
Bind
Ndx
Name
```

你会看到：

```text
foo
```

已经拥有最终地址。

---

# 二十五、非常重要：为什么最终 ELF 里没有 relocation？

对于我们的这个简单静态链接实验：

```bash
readelf -r trace.elf
```

通常不会再看到：

```text
foo
a
```

相关的普通静态 relocation。

因为 linker 已经完成：

```text
foo
 ↓
最终地址
 ↓
修补指令
```

所以：

```text
.o
```

阶段：

```text
relocation unresolved
```

而：

```text
最终 ELF
```

阶段：

```text
relocation resolved
```

---

# 二十六、这就是 linker 真正干的事情

把整个过程串起来：

```text
             a.c
              │
              ▼
             a.o
              │
        ┌─────┴─────┐
        │           │
       T a         U foo
        │           │
        │           ▼
        │         libB.a
        │           │
        │           ▼
        │          b.o
        │           │
        │           ▼
        │          T foo
        │
        ▼
      libA.a
        │
        ▼
       main.o
        │
        ▼
       U a
```

然后 linker：

```text
Archive Search
      ↓
Symbol Resolution
      ↓
Relocation Resolution
      ↓
Section Layout
      ↓
Final ELF
```

---

# 二十七、Map 文件：今天的核心证据

打开：

```bash
less trace.map
```

或者：

```bash
grep -A 30 -B 5 "libA.a" trace.map
```

以及：

```bash
grep -A 30 -B 5 "libB.a" trace.map
```

你应该看到：

```text
libA.a(a.o)
```

进入了：

```text
.text
```

以及：

```text
libB.a(b.o)
```

也进入：

```text
.text
```

---

# 二十八、为什么 `libA.a` 的 a.o 会被提取？

链接器处理：

```text
main.o
```

时：

```text
Undefined:
    a
```

然后处理：

```text
libA.a
```

发现：

```text
a.o
```

提供：

```text
T a
```

所以：

```text
a.o
```

被提取。

---

# 二十九、a.o 被提取之后发生了什么？

突然增加：

```text
Undefined:
    foo
```

所以 linker 接着处理：

```text
libB.a
```

发现：

```text
b.o
```

提供：

```text
T foo
```

于是：

```text
b.o
```

被提取。

所以真正的链条是：

```text
main.o
  │
  │ U a
  ▼
libA.a
  │
  ▼
a.o
  │
  │ U foo
  ▼
libB.a
  │
  ▼
b.o
  │
  │ T foo
  ▼
resolve
```

---

# 三十、这就是 Archive Search 的动态性

这是上一节之后必须升级的认识：

> **linker 在扫描 archive 时，当前的 undefined symbol 集合是动态变化的。**

开始：

```text
U = { a }
```

处理：

```text
libA.a
```

提取 `a.o`：

```text
U = { foo }
```

处理：

```text
libB.a
```

提取 `b.o`：

```text
U = { }
```

最终：

```text
U = empty
```

这就是链接成功。

---

# 三十一、做一个故意失败的实验

交换：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    libB.a \
    libA.a \
    -o wrong-order.elf \
    -Map=wrong-order.map
```

为什么可能失败？

处理：

```text
main.o
```

产生：

```text
U = { a }
```

然后：

```text
libB.a
```

里面只有：

```text
foo
```

但是当前：

```text
U = { a }
```

没有：

```text
foo
```

所以：

```text
b.o
```

不提取。

继续：

```text
libA.a
```

提取：

```text
a.o
```

于是：

```text
U = { foo }
```

但是：

```text
libB.a
```

已经扫描完。

最终：

```text
U = { foo }
```

所以：

```text
undefined reference to foo
```

---

# 三十二、现在 `--trace-symbol=foo` 就特别有价值

执行失败版本：

```bash
ld \
    -T linker.ld \
    --trace-symbol=foo \
    start.o \
    main.o \
    libB.a \
    libA.a \
    -o wrong-order.elf
```

你会发现：

```text
a.o
```

确实引用：

```text
foo
```

但：

```text
b.o
```

可能根本没有进入最终链接。

这就是一个非常经典的排错场景：

```text
“明明 libB.a 里有 foo，为什么 undefined？”
```

答案：

> **不是符号不存在，而是 archive member 没有被提取。**

---

# 三十三、这时候 Map 文件怎么看？

```bash
grep -A 30 -B 5 "libB.a" wrong-order.map
```

重点不是问：

> `libB.a` 是否出现在命令行？

而是问：

> **`libB.a(b.o)` 是否真的进入了最终输出？**

这是看 `.a` 的核心技巧。

---

# 三十四、实验 12-2：使用 `--start-group`

现在故意：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    --start-group \
    libB.a \
    libA.a \
    --end-group \
    -o group.elf \
    -Map=group.map
```

这次：

```text
libB.a
libA.a
```

即使顺序反过来，也能通过 group 反复搜索解决依赖。

GNU `ld` 文档说明，`--start-group archives --end-group` 会反复搜索这些 archive，直到不再产生新的未定义引用；代价是可能增加链接时间。([Sourceware][1])

---

# 三十五、`--start-group` 的内部过程

可以粗略理解成：

```text
第 1 轮：

libB.a
  ↓
没有 foo 被需要
  ↓
不提取

libA.a
  ↓
提取 a.o
  ↓
产生 U foo


第 2 轮：

libB.a
  ↓
现在需要 foo
  ↓
提取 b.o
  ↓
foo resolved

libA.a
  ↓
没有新成员
```

最终：

```text
undefined = empty
```

链接成功。

---

# 三十六、现在用 `--trace-symbol` + `--start-group`

```bash
ld \
    -T linker.ld \
    --trace-symbol=foo \
    --start-group \
    libB.a \
    libA.a \
    --end-group \
    start.o \
    main.o \
    -o group-trace.elf \
    -Map=group-trace.map
```

为了避免输入顺序干扰，实际实验时建议保持：

```text
start.o
main.o
group
```

即：

```bash
ld \
    -T linker.ld \
    --trace-symbol=foo \
    start.o \
    main.o \
    --start-group \
    libB.a \
    libA.a \
    --end-group \
    -o group-trace.elf \
    -Map=group-trace.map
```

---

# 三十七、用 `readelf -r` 看“引用关系”

分别：

```bash
readelf -r main.o
```

```bash
readelf -r a.o
```

你会得到：

```text
main.o
    relocation → a

a.o
    relocation → foo
```

而：

```text
b.o
```

没有对 `foo` 的 undefined relocation，因为：

```c
int foo(void)
```

本身就是定义。

所以：

```text
main.o
 └── relocation → a

a.o
 └── relocation → foo

b.o
 └── definition foo
```

---

# 三十八、用 `objdump -dr` 进一步验证

```bash
objdump -dr main.o
```

观察：

```text
call
  ↓
a
  ↓
relocation
```

然后：

```bash
objdump -dr a.o
```

观察：

```text
call
  ↓
foo
  ↓
relocation
```

最终：

```bash
objdump -d group.elf
```

观察：

```text
main
 ↓
call a

a
 ↓
call foo

foo
 ↓
return 40
```

这样：

```text
源代码
 ↓
机器码
 ↓
relocation
 ↓
symbol resolution
 ↓
最终机器码
```

完整闭环。

---

# 三十九、实验 12-3：让 `foo` 的地址发生变化

现在修改 linker script：

```ld
.text :
{
    *(.text)
    *(.text.*)
} > ROM :text

. = ALIGN(0x100);

.special :
{
    *(.special)
} > ROM :text
```

再让 `foo` 放进：

```asm
.section .special
```

或者在 C 中通过：

```c
__attribute__((section(".special")))
int foo(void)
{
    return 40;
}
```

这样：

```text
foo
```

不再紧跟 `.text`，而是进入：

```text
.special
```

然后：

```bash
nm -n group.elf | grep foo
```

比较：

```text
foo
```

的地址。

再：

```bash
readelf -S group.elf
```

查看：

```text
.special
```

地址。

最后：

```bash
grep -A 20 -B 5 ".special" group.map
```

这能再次证明：

> **Symbol 最终地址不是由源代码决定，而是由 Input Section → Output Section → VMA 布局共同决定。**

---

# 四十、`--trace-symbol` 的一个实战技巧

如果工程报：

```text
undefined reference to `foo'
```

不要马上：

```bash
grep -R "foo" .
```

先做：

```bash
ld \
    --trace-symbol=foo \
    ...
```

它能告诉你：

```text
哪些参与链接的文件中出现 foo
```

官方文档明确将这个选项定位为排查 undefined symbol 来源的工具。([Sourceware][1])

如果是通过 GCC 驱动链接：

```bash
gcc \
    ... \
    -Wl,--trace-symbol=foo
```

GNU GCC 文档也说明，像 `--start-group` 这类 linker 选项需要通过 `-Wl,` 传给 linker；否则 GCC 驱动可能不会按预期传递该选项。([Sourceware][2])

---

# 四十一、今天形成一个非常实用的排错矩阵

遇到：

```text
undefined reference to foo
```

按照：

```text
① nm xxx.o
        ↓
foo 是 U 还是 T/W/B/D？

② nm libxxx.a
        ↓
库里真的有 foo 吗？

③ ld --trace-symbol=foo
        ↓
谁引用？谁定义？

④ readelf -r
        ↓
哪个 relocation 依赖 foo？

⑤ Map
        ↓
定义 foo 的 .o 是否真的进入？

⑥ readelf -S
        ↓
它最终属于哪个 Output Section？

⑦ nm final.elf
        ↓
最终 foo 地址是多少？
```

这比“重新排库顺序试试”可靠得多。

---

# 四十二、今天最重要的一张图

```text
                main.c
                  │
                  ▼
                main.o
                  │
                  │ U a
                  ▼
              libA.a
                  │
                  ▼
                 a.o
             ┌────┴────┐
             │         │
          T a          U foo
                        │
                        ▼
                     libB.a
                        │
                        ▼
                       b.o
                        │
                        │ T foo
                        ▼
                  Symbol Resolution
                        │
                        ▼
                    foo = 0x....
                        │
                        ▼
                    Relocation
                        │
                        ▼
                    final ELF
```

---

# 四十三、五个工具各自负责什么？

这一点建议以后形成肌肉记忆。

| 工具                  | 主要回答                   |
| ------------------- | ---------------------- |
| `nm`                | 这个文件有哪些 symbol？        |
| `readelf -s`        | ELF symbol 的完整属性是什么？   |
| `readelf -r`        | 哪些地方存在 relocation？     |
| `objdump -dr`       | relocation 对应哪条机器指令？   |
| `ld --trace-symbol` | 这次链接中谁引用/定义了这个 symbol？ |
| `map`               | linker 最终把它放在哪里？       |

所以：

```text
nm
 ↓
“有什么？”

readelf -r
 ↓
“谁依赖谁？”

--trace-symbol
 ↓
“这次链接到底是谁参与了？”

map
 ↓
“最后放哪了？”

objdump
 ↓
“机器码最终变成什么？”
```

---

# 四十四、今天的实验命令总表

### 编译

```bash
gcc -c main.c -o main.o
gcc -c a.c -o a.o
gcc -c b.c -o b.o
gcc -c start.S -o start.o
```

### 创建 archive

```bash
ar rcs libA.a a.o
ar rcs libB.a b.o
```

### 查看 archive

```bash
ar t libA.a
ar t libB.a
```

### 查看 symbol

```bash
nm main.o
nm a.o
nm b.o
nm -s libA.a
nm -s libB.a
```

### 查看 relocation

```bash
readelf -r main.o
readelf -r a.o
```

### 查看机器码 + relocation

```bash
objdump -dr main.o
objdump -dr a.o
```

### 正常链接

```bash
ld \
    -T linker.ld \
    start.o main.o \
    libA.a libB.a \
    -o trace.elf \
    -Map=trace.map
```

### Symbol tracing

```bash
ld \
    -T linker.ld \
    --trace-symbol=foo \
    start.o main.o \
    libA.a libB.a \
    -o trace-symbol.elf \
    -Map=trace-symbol.map
```

### Group

```bash
ld \
    -T linker.ld \
    start.o main.o \
    --start-group \
    libB.a libA.a \
    --end-group \
    -o group.elf \
    -Map=group.map
```

---

# 四十五、把实验 01～12 的主线重新串起来

现在整个课程已经不再是零散命令，而是一条完整的 linker pipeline：

```text
                 C / ASM
                    │
                    ▼
              Compiler / as
                    │
                    ▼
                   .o
                    │
          ┌─────────┼─────────┐
          │         │         │
          ▼         ▼         ▼
       Section    Symbol   Relocation
          │         │         │
          └─────────┼─────────┘
                    ▼
                 ld input
                    │
             ┌──────┴──────┐
             ▼             ▼
           .a            .o
             │
             ▼
       Archive Search
             │
             ▼
      Symbol Resolution
             │
       ┌─────┼─────┐
       ▼     ▼     ▼
    Strong Weak COMMON
             │
             ▼
        Section GC
             │
          KEEP()
             │
             ▼
       Linker Script
             │
     ┌───────┼────────┐
     ▼       ▼        ▼
  MEMORY  SECTIONS   PHDRS
     │       │
     │   ┌───┼────┐
     │   ▼   ▼    ▼
     │ ALIGN SUBALIGN KEEP
     │
     └───────┬───────┘
             ▼
        Final VMA/LMA
             │
             ▼
          Relocation
             │
             ▼
             ELF
             │
    ┌────────┼─────────┐
    ▼        ▼         ▼
 readelf  objdump     nm
    │        │         │
    └────────┼─────────┘
             ▼
          map file
```

这张图基本就是我们到目前为止这套 GNU `ld` 实战课的主干。

---

# 四十六、下一实验：从“符号解析”进入“段与地址空间”

下一节建议进入一个非常关键的转折点：

## 实验 13：`AT()`、`LOADADDR()`、VMA/LMA——一个 Section 为什么有两个地址？

我们会正式构造：

```text
ROM
0x00400000
   │
   ├── .text
   ├── .rodata
   └── .data 的加载镜像
            │
            │ boot 时复制
            ▼
RAM
0x00600000
   │
   ├── .data
   └── .bss
```

重点实验：

```ld
.data :
{
    __data_start = .;
    *(.data)
    __data_end = .;
} > RAM AT > ROM
```

然后：

```ld
__data_load = LOADADDR(.data);
```

我们会同时验证：

```bash
readelf -S
readelf -l
nm
objdump -h
objdump -s
```

并通过 map 文件回答一个非常关键的问题：

> **为什么 `.data` 的 VMA 是 RAM 地址，但 ELF 文件里的初始数据却位于 ROM/Flash 镜像区域？**

然后进一步进入：

```text
VMA
LMA
AT()
LOADADDR()
ADDR()
SIZEOF()
```

最终把之前实验里你重点关注的：

```text
.data 从 ROM 搬到 RAM
```

彻底从 linker 的角度推导出来。

[1]: https://sourceware.org/binutils/docs/ld.pdf?utm_source=chatgpt.com "The GNU linker"
[2]: https://www.sourceware.org/binutils/docs/ld.pdf?utm_source=chatgpt.com "The GNU linker"

