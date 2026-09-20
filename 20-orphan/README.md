# GNU ld 实战课程 · 实验 20

## Orphan Sections：为什么 `linker.ld` 没写，ELF 里却出现了它？

这一节正好接上上一节的 `SORT()` / `KEEP()` / `EXCLUDE_FILE()`。

前面我们学的是：

```text
Input Section
    ↓
linker script 主动匹配
    ↓
Output Section
```

但是现实中的 ELF 经常出现另一种情况：

```text
foo.o
 ├── .text.foo
 ├── .my_code
 ├── .my_data
 └── .my_bss

linker.ld
 ├── .text
 ├── .data
 └── .bss

没有写 .my_code
没有写 .my_data
没有写 .my_bss
```

然后：

```bash
ld ...
```

**居然成功了。**

而：

```bash
readelf -S app.elf
```

里面出现：

```text
.my_code
.my_data
.my_bss
```

这就是：

# Orphan Section（孤儿 Section）

GNU ld 官方文档明确规定：如果输入文件中的 section 没有被 linker script 明确放置，ld 不会简单地丢掉它；默认会尝试寻找合适的 Output Section，或者创建同名 Output Section 来容纳它。([Sourceware][1])

今天我们要把这个过程**从 ELF → linker → Map → `--orphan-handling`**完整拆开。

---

# 一、今天的实验路线

```text
实验 20-1
制造一个 Orphan Section

实验 20-2
观察 ld 自动创建 Output Section

实验 20-3
观察 Orphan 的地址到底放在哪里

实验 20-4
同名 Orphan Section 如何合并

实验 20-5
让 Orphan 匹配已有 Output Section

实验 20-6
--orphan-handling=warn

实验 20-7
--orphan-handling=error

实验 20-8
--orphan-handling=discard

实验 20-9
--unique 与 Orphan

实验 20-10
Map + readelf + objdump 三重验证

实验 20-11
为什么真实工程应该尽量避免“意外 Orphan”
```

---

# 二、先建立最小实验

目录：

```text
lab20/
├── main.c
├── orphan.c
├── start.S
└── linker.ld
```

---

# 三、`orphan.c`

我们故意制造一个 linker script 完全不知道的 Section：

```c
__attribute__((section(".my_code")))
void orphan_function(void)
{
}

__attribute__((section(".my_data")))
int orphan_data = 123;

__attribute__((section(".my_bss")))
int orphan_bss;
```

这里 GCC 的 `section` attribute 会把变量/函数放入指定 section。GCC 官方文档也明确说明了这一点。([Sourceware Snapshots][2])

于是：

```text
orphan.o

.text
.my_code
.my_data
.my_bss
```

---

# 四、先不要写 linker script

先编译：

```bash
gcc \
    -ffreestanding \
    -fno-pie \
    -fno-stack-protector \
    -ffunction-sections \
    -fdata-sections \
    -c orphan.c \
    -o orphan.o
```

检查：

```bash
objdump -h orphan.o
```

重点应该看到：

```text
.my_code
.my_data
.my_bss
```

---

# 五、这一步非常重要

现在我们已经证明：

```text
C source
   ↓
GCC
   ↓
orphan.o
   ↓
Input Sections
```

产生了：

```text
.my_code
.my_data
.my_bss
```

但是：

```text
linker.ld
```

完全没有：

```ld
.my_code
.my_data
.my_bss
```

---

# 六、`main.c`

```c
int main(void)
{
    return 0;
}
```

编译：

```bash
gcc \
    -ffreestanding \
    -fno-pie \
    -fno-stack-protector \
    -c main.c \
    -o main.o
```

---

# 七、`start.S`

```asm
.global _start

.text

_start:
    call main
    hlt
```

编译：

```bash
gcc -c start.S -o start.o
```

---

# 八、最简单的 linker script

```ld
ENTRY(_start)

MEMORY
{
    ROM (rx) : ORIGIN = 0x00400000, LENGTH = 64K
    RAM (rw) : ORIGIN = 0x00600000, LENGTH = 64K
}

SECTIONS
{
    .text :
    {
        *(.text)
        *(.text.*)
    } > ROM

    .data :
    {
        *(.data)
        *(.data.*)
    } > RAM

    .bss :
    {
        *(.bss)
        *(.bss.*)
        *(COMMON)
    } > RAM
}
```

注意：

```text
没有：
.my_code
.my_data
.my_bss
```

---

# 九、链接

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    orphan.o \
    -o orphan01.elf \
    -Map=orphan01.map
```

你可能会期待：

```text
ld: section `.my_code' not handled
```

但是：

**通常不会。**

这正是今天的主题。

---

# 十、查看 ELF

```bash
readelf -S orphan01.elf
```

你应该可能看到：

```text
.my_code
.my_data
.my_bss
```

也就是说：

```text
linker.ld
没有写
      ↓
ld
      ↓
自动处理
      ↓
ELF 中出现
```

这就是：

# Orphan Section。

GNU ld 默认的 orphan handling 模式是 `place`。([Sourceware][3])

---

# 十一、为什么叫 Orphan？

因为 linker script 没有认领它。

例如：

```text
Input Section

.text
    ↓
linker.ld 认领

.data
    ↓
linker.ld 认领

.bss
    ↓
linker.ld 认领

.my_code
    ↓
没人认领
    ↓
Orphan
```

所以：

```text
Orphan
=
Input Section 没有被 linker script 明确放置
```

---

# 十二、第一条规则：同名 Output Section 存在

假设：

```ld
SECTIONS
{
    .my_code :
    {
        *(.my_code)
    } > ROM
}
```

那么：

```text
.my_code
```

就不再是 Orphan。

因为：

```text
linker script
    ↓
明确匹配
.my_code
```

---

# 十三、第二条规则：如果不存在同名 Output Section

如果：

```text
linker.ld
```

没有：

```ld
.my_code
```

那么 ld 可以：

```text
自动创建：

.my_code
```

这就是：

```text
Orphan Input Section
        ↓
自动创建
        ↓
.my_code Output Section
```

GNU ld 文档明确描述了这个行为：如果没有匹配的 Output Section，linker 会创建新的 Output Section，并使用 orphan section 的名字。([Sourceware][1])

---

# 十四、实验 20-1：观察 Map

执行：

```bash
grep -A 20 -B 5 "\.my_code" orphan01.map
```

再：

```bash
grep -A 20 -B 5 "\.my_data" orphan01.map
```

再：

```bash
grep -A 20 -B 5 "\.my_bss" orphan01.map
```

重点看：

```text
.my_code
    orphan.o(.my_code)

.my_data
    orphan.o(.my_data)

.my_bss
    orphan.o(.my_bss)
```

这里你会第一次在 Map 文件里看到：

> **不是 linker script 主动写出的 Output Section，也可以出现在最终布局中。**

---

# 十五、实验 20-2：观察 `objdump -h`

```bash
objdump -h orphan01.elf
```

重点：

```text
.my_code
.my_data
.my_bss
```

记录：

```text
Name
Size
VMA
LMA
File off
Algn
```

建议手工做表：

| Section    | VMA | LMA | Size | 类型   |
| ---------- | --: | --: | ---: | ---- |
| `.text`    | ... | ... |  ... | Code |
| `.my_code` | ... | ... |  ... | Code |
| `.data`    | ... | ... |  ... | Data |
| `.my_data` | ... | ... |  ... | Data |
| `.bss`     | ... | ... |  ... | BSS  |
| `.my_bss`  | ... | ... |  ... | BSS  |

---

# 十六、这里出现一个非常重要的问题

为什么：

```text
.my_code
```

会放到：

```text
.text
```

附近？

为什么：

```text
.my_data
```

会放到：

```text
.data
```

附近？

为什么：

```text
.my_bss
```

会放到：

```text
.bss
```

附近？

答案是：

> GNU ld 会根据 orphan section 的属性和已有 Output Section 的属性，寻找合适的位置。

现代目标上，ld 会尽量让 orphan section 出现在具有相同属性的 section 附近，例如 code/data、loadable/non-loadable 等。([Sourceware][1])

所以不要把它理解成：

```text
“ld 随便找个空位置”
```

而应该理解成：

```text
ld 根据 section 属性
尝试推断
“它应该属于哪一类”
```

---

# 十七、一个非常关键的实验

把 linker script 改成：

```ld
SECTIONS
{
    .text :
    {
        *(.text)
        *(.text.*)
    } > ROM

    .data :
    {
        *(.data)
        *(.data.*)
    } > RAM

    .bss :
    {
        *(.bss)
        *(.bss.*)
        *(COMMON)
    } > RAM

    .tail :
    {
        BYTE(0)
    } > ROM
}
```

重新链接：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    orphan.o \
    -o orphan02.elf \
    -Map=orphan02.map
```

然后：

```bash
objdump -h orphan02.elf
```

以及：

```bash
grep -A 30 "\.my_code" orphan02.map
```

观察 `.my_code` 到底被放到了哪里。

---

# 十八、为什么 Map 文件特别重要？

因为 orphan 的具体位置：

```text
不能只靠 linker.ld 推断。
```

必须观察：

```text
Map
 ↓
最终 Output Section
 ↓
地址
 ↓
Input Section
```

这也是以后遇到：

```text
“为什么我的 section 地址突然变了？”
```

时，第一个应该看的地方：

```bash
grep -n "\.my_" xxx.map
```

---

# 十九、实验 20-3：同名 Orphan 会合并

制造两个文件：

```text
a.c
b.c
```

`a.c`：

```c
__attribute__((section(".custom")))
int a = 1;
```

`b.c`：

```c
__attribute__((section(".custom")))
int b = 2;
```

编译：

```bash
gcc -ffreestanding -fno-pie -fdata-sections \
    -c a.c -o a.o

gcc -ffreestanding -fno-pie -fdata-sections \
    -c b.c -o b.o
```

---

# 二十、linker.ld 不写 `.custom`

仍然：

```ld
SECTIONS
{
    .text :
    {
        *(.text)
        *(.text.*)
    } > ROM

    .data :
    {
        *(.data)
        *(.data.*)
    } > RAM
}
```

链接：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    a.o \
    b.o \
    -o orphan03.elf \
    -Map=orphan03.map
```

---

# 二十一、观察 Map

```bash
grep -A 20 "\.custom" orphan03.map
```

应该看到类似：

```text
.custom
    a.o(.custom)
    b.o(.custom)
```

也就是说：

```text
a.o:.custom
b.o:.custom
```

被合并到：

```text
.custom
```

这个规则也由 GNU ld 的 orphan 机制规定：如果多个 orphan input section 同名，它们会合并到同一个新建 Output Section。([Sourceware][1])

---

# 二十二、这和普通 `*(.custom)` 有什么区别？

如果 linker script 写：

```ld
.custom :
{
    *(.custom)
} > RAM
```

那么：

```text
.custom
```

是：

```text
显式 Output Section
```

如果 linker script 完全没写：

```text
.custom
```

最后 ELF 仍然出现：

```text
.custom
```

则：

```text
Orphan 自动创建
```

最终 ELF 看起来可能非常相似。

但是：

> **布局的控制权完全不同。**

显式：

```text
你控制
```

Orphan：

```text
ld 猜测
```

---

# 二十三、这就是为什么工程中不应该依赖 Orphan 的自动布局

例如：

```text
.my_code
```

你希望：

```text
ROM
0x00410000
```

但 linker script 没写：

```ld
.my_code
```

于是：

```text
ld 自动决定
```

那么：

```text
GCC 升级
Binutils 升级
新增 section
修改 PHDRS
修改其它 section
```

都有可能改变最终布局。

因此：

# 对重要的自定义 Section，最好显式放置。

---

# 二十四、实验 20-4：让 Orphan 进入已有 Output Section

现在做一个很有意思的实验。

linker script：

```ld
SECTIONS
{
    .text :
    {
        *(.text)
        *(.text.*)
    } > ROM
}
```

然后我们制造：

```c
__attribute__((section(".text")))
void special(void)
{
}
```

这里 Input Section 名字：

```text
.text
```

和 Output Section：

```text
.text
```

完全相同。

根据 GNU ld 的规则：

> 如果 orphan input section 的名字恰好匹配已有 Output Section，那么它会被放到该 Output Section 的末尾。([Sourceware][1])

所以：

```text
.text
 ├── 原来的匹配 section
 └── orphan .text
```

---

# 二十五、实验验证

`special.c`：

```c
__attribute__((section(".text")))
void special(void)
{
}
```

编译：

```bash
gcc \
    -ffreestanding \
    -fno-pie \
    -fno-stack-protector \
    -c special.c \
    -o special.o
```

然后：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    special.o \
    -o orphan04.elf \
    -Map=orphan04.map
```

查看：

```bash
grep -A 20 "^\.text" orphan04.map
```

你应该能看到：

```text
.text
    ...
    special.o(.text)
```

这里就非常直观：

```text
同名
 ↓
进入已有 Output Section
```

---

# 二十六、实验 20-5：`--orphan-handling=warn`

这是实际排查工程问题非常好用的选项。

执行：

```bash
ld \
    --orphan-handling=warn \
    -T linker.ld \
    start.o \
    main.o \
    orphan.o \
    -o orphan-warn.elf \
    -Map=orphan-warn.map
```

如果存在：

```text
.my_code
.my_data
.my_bss
```

linker 会：

```text
正常放置
+
warning
```

GNU ld 官方文档定义了：

```text
place
discard
warn
error
```

四种 orphan handling 模式；默认是 `place`。([Sourceware][4])

---

# 二十七、为什么 `warn` 非常适合我们现在的课程？

因为：

```text
默认 place
```

让程序正常构建。

但是：

```text
warn
```

会告诉你：

> “嘿，你的 linker script 没有明确处理这个 section。”

于是你可以：

```text
发现问题
 ↓
查看 Map
 ↓
决定是否显式加入 linker.ld
```

这是一种非常好的 linker script 开发模式。

---

# 二十八、实验 20-6：`--orphan-handling=error`

现在：

```bash
ld \
    --orphan-handling=error \
    -T linker.ld \
    start.o \
    main.o \
    orphan.o \
    -o orphan-error.elf \
    -Map=orphan-error.map
```

这次：

```text
.my_code
.my_data
.my_bss
```

只要没有被 linker script 明确处理：

```text
ld
 ↓
error
 ↓
链接失败
```

---

# 二十九、这其实非常适合生产工程

如果你希望：

> **任何新的 Section 都必须经过 linker script 审核。**

那么：

```bash
--orphan-handling=error
```

非常有价值。

工程规则变成：

```text
开发者新增：

__attribute__((section(".foo")))

        ↓

ld
        ↓

发现 .foo 没有显式布局
        ↓

ERROR
```

于是开发者必须：

```ld
.foo :
{
    *(.foo)
} > ROM
```

明确告诉 linker：

> `.foo` 应该放在哪里。

---

# 三十、这和 `ASSERT()` 形成非常好的组合

上一节：

```text
ASSERT()
```

检查：

```text
地址是否合法
```

这一节：

```text
--orphan-handling=error
```

检查：

```text
Section 是否经过显式设计
```

于是：

```text
Input Section
       ↓
是否被显式处理？
       ↓
      YES
       ↓
布局
       ↓
ASSERT
       ↓
地址安全
```

这已经是一套完整的 linker 安全机制。

---

# 三十一、实验 20-7：`--orphan-handling=discard`

还有：

```bash
--orphan-handling=discard
```

它的效果是：

```text
Orphan
 ↓
/DISCARD/
```

也就是：

```text
没有被 linker script 明确处理
        ↓
直接丢弃
```

官方文档明确说明，`discard` 会把 orphan section 放入 `/DISCARD/`。([Sourceware][4])

---

# 三十二、实验

```bash
ld \
    --orphan-handling=discard \
    -T linker.ld \
    start.o \
    main.o \
    orphan.o \
    -o orphan-discard.elf \
    -Map=orphan-discard.map
```

然后：

```bash
readelf -S orphan-discard.elf
```

观察：

```text
.my_code
.my_data
.my_bss
```

是否还存在。

再：

```bash
nm orphan-discard.elf
```

查看：

```text
orphan_function
orphan_data
orphan_bss
```

是否消失。

---

# 三十三、但是这里要非常谨慎

`discard` 不是：

> “帮我清理垃圾 section。”

它实际上是：

> **所有 orphan 都不要。**

所以如果某个新版本 GCC 突然产生：

```text
.foo.metadata
```

或者某个库加入：

```text
.special_runtime
```

而你的 linker script 没处理：

```text
--orphan-handling=discard
```

可能直接把它丢掉。

因此：

```text
生产固件
```

通常要非常谨慎使用。

---

# 三十四、实验 20-8：`--unique`

现在进入一个稍高级的选项：

```bash
--unique
```

GNU ld 文档说明，`--unique[=SECTION]` 可以让匹配的每个 Input Section 都生成独立 Output Section；没有指定 SECTION 时，可以作用于 orphan input sections。([Sourceware][4])

例如：

```bash
ld \
    --unique \
    -T linker.ld \
    start.o \
    main.o \
    orphan.o \
    -o unique.elf \
    -Map=unique.map
```

---

# 三十五、为什么需要 `--unique`？

默认：

```text
a.o:.custom
b.o:.custom
c.o:.custom
```

可能合并：

```text
.custom
```

而：

```text
--unique
```

可以让：

```text
a.o:.custom
```

成为一个独立 Output Section，

```text
b.o:.custom
```

又是另一个。

最终可能看到：

```text
.custom
.custom
.custom
```

具体显示名称/后缀行为与目标和工具链版本有关，但核心语义是：

> **不要把这些输入 section 普通地合并到一个 Output Section。**

---

# 三十六、这对于 `--gc-sections` 很有意义

假设：

```text
foo.o
    .text.foo

bar.o
    .text.bar
```

如果：

```text
-function-sections
```

已经把函数拆开，那么：

```text
GC
```

可以独立删除。

而：

```text
--unique
```

进一步强调：

```text
Input Section
=
独立布局实体
```

所以：

```text
Section 粒度
```

会变得更细。

---

# 三十七、但我们暂时不要滥用 `--unique`

因为它可能增加：

```text
Output Section 数量
```

进而影响：

```text
ELF
Program Header
Section alignment
padding
Map
```

所以真实工程里：

```text
--unique
```

应该是：

> **有明确布局需求时使用。**

不是默认打开。

---

# 三十八、实验 20-9：Orphan + `readelf -S`

现在我们正式建立一个分析流程。

```bash
readelf -S orphan01.elf
```

记录：

```text
Ndx
Name
Type
Address
Offset
Size
EntSize
Flags
Align
```

特别关注：

```text
.my_code
```

Flags 可能类似：

```text
AX
```

因为它是代码。

而：

```text
.my_data
```

可能类似：

```text
WA
```

而：

```text
.my_bss
```

可能：

```text
NOBITS
WA
```

这就是我们判断 orphan 被放到哪一类区域的重要依据。

---

# 三十九、实验 20-10：`objdump -h`

执行：

```bash
objdump -h orphan01.elf
```

重点：

```text
.my_code
.my_data
.my_bss
```

看：

```text
CONTENTS
ALLOC
LOAD
CODE
DATA
```

例如：

```text
.my_code
CONTENTS, ALLOC, LOAD, READONLY, CODE
```

而：

```text
.my_bss
ALLOC
```

可能没有：

```text
CONTENTS
```

因为它可能是：

```text
SHT_NOBITS
```

这又一次把：

```text
Section Type
+
Section Flags
```

与：

```text
Orphan placement
```

联系起来。

---

# 四十、实验 20-11：Map 文件分析模板

以后看到 Orphan，我建议固定按照这个表分析：

| 问题                 | 查看位置                        |
| ------------------ | --------------------------- |
| Input Section 是否存在 | `objdump -h orphan.o`       |
| linker.ld 是否匹配     | `linker.ld`                 |
| 是否成为 Orphan        | `ld --orphan-handling=warn` |
| 最终 Output Section  | `readelf -S`                |
| 最终地址               | `objdump -h`                |
| 来源 `.o`            | `map`                       |
| 是否被 GC             | `Discarded input sections`  |
| 是否进入 Segment       | `readelf -l`                |

这套流程非常适合排查：

```text
“为什么我的自定义 section 跑到奇怪的地址？”
```

---

# 四十一、实验 20-12：观察 Segment

这是今天非常容易漏掉的一步。

执行：

```bash
readelf -l orphan01.elf
```

不要只看：

```text
Section Header Table
```

还要看：

```text
Program Header Table
```

因为：

```text
Section
```

决定：

```text
链接布局
```

而：

```text
Segment
```

决定：

```text
装载布局
```

所以：

```text
.my_code
```

即使：

```text
Section 地址
```

看起来正确，也要继续确认：

```text
它到底进入哪个 PT_LOAD？
```

---

# 四十二、如果你发现 Orphan 改变了 Segment 呢？

例如：

```text
原来：

PT_LOAD RX
    .text
    .rodata

PT_LOAD RW
    .data
    .bss
```

后来新增：

```text
.my_code
```

如果 ld 把它自动插入某个位置：

```text
Section
   ↓
Segment mapping
```

可能发生：

```text
File offset
Virtual address
Segment size
Alignment
```

变化。

于是：

```text
Orphan
```

不只是影响：

```text
Section Address
```

还可能影响：

```text
Program Header
```

这就是为什么生产工程里最好不要依赖大量隐式 orphan placement。

---

# 四十三、实验 20-13：使用 `--orphan-handling=warn` 做工程审计

这其实是我最推荐你现在开始养成的习惯：

每当 linker script 有较大修改：

```bash
ld \
    --orphan-handling=warn \
    -T linker.ld \
    ... \
    -o final.elf \
    -Map=final.map
```

然后：

```text
如果出现 warning
    ↓
检查新的 orphan
    ↓
确认是不是故意
```

如果是：

```text
GCC / library 自动新增
```

那么：

```ld
显式加入 linker.ld
```

如果是：

```text
真正不需要
```

再决定：

```text
/DISCARD/
```

或者：

```text
--orphan-handling=discard
```

---

# 四十四、进一步升级：生产工程使用 `error`

最终成熟工程可以考虑：

```bash
ld \
    --orphan-handling=error \
    ...
```

这样：

```text
新 Section
 ↓
没有 linker script 规则
 ↓
立即失败
```

这与上一节的：

```ld
ASSERT()
```

组合后：

```text
Section policy
    ↓
orphan-handling=error
    ↓
Layout policy
    ↓
ASSERT()
    ↓
ELF
```

已经是相当严格的链接布局控制。

---

# 四十五、为什么这个实验非常重要？

因为现在你应该能解释一个真实工程里很常见的问题：

> “我明明没改 linker.ld，为什么升级 GCC 后 ELF 的 section 地址发生变化？”

可能的原因就是：

```text
GCC 新增了 Input Section
       ↓
你的 linker.ld 没匹配
       ↓
它成为 Orphan
       ↓
ld 自动放置
       ↓
后面的 section 地址全部变化
```

例如：

```text
.text
0x400000
```

原来：

```text
.text size = 0x1000
```

新增 orphan：

```text
.my_code = 0x200
```

如果被放进：

```text
.text 附近
```

那么后面：

```text
.rodata
.data image
```

都有可能移动。

这就是：

# 隐式布局的连锁反应。

---

# 四十六、把 Orphan 与上一节 `SORT()` 联系起来

上一节：

```text
显式：

.text :
{
    *(SORT(.text.*))
}
```

是：

```text
主动控制
```

而：

```text
没有写：

.my_code
```

是：

```text
被动交给 ld
```

因此：

```text
显式 Section
    ↓
你的规则

Orphan Section
    ↓
ld 的规则
```

如果你正在做：

```text
MCU
Bootloader
固件
RTOS
内核
链接地址固定的驱动
```

一般更希望：

```text
你的规则
```

而不是：

```text
ld 猜测
```

---

# 四十七、实验 20-14：最终版 linker script

今天可以把 linker script 改成一个更严格的版本：

```ld
ENTRY(_start)

MEMORY
{
    ROM (rx) : ORIGIN = 0x00400000, LENGTH = 64K
    RAM (rw) : ORIGIN = 0x00600000, LENGTH = 64K
}

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
        SORT(.text.*)
    } > ROM

    .rodata :
    {
        *(.rodata)
        *(.rodata.*)
    } > ROM

    .init_array :
    {
        KEEP(*(SORT(.init_array.*)))
        KEEP(*(.init_array))
    } > ROM

    .data :
    {
        _sdata = .;

        *(.data)
        *(.data.*)

        _edata = .;
    } > RAM AT > ROM

    .bss :
    {
        _sbss = .;

        *(.bss)
        *(.bss.*)
        *(COMMON)

        _ebss = .;
    } > RAM

    ASSERT(
        _ebss <= ORIGIN(RAM) + LENGTH(RAM),
        "ERROR: RAM overflow"
    );
}
```

然后生产环境：

```bash
ld \
    --orphan-handling=error \
    -T linker.ld \
    ... \
    -o firmware.elf \
    -Map=firmware.map
```

这样：

```text
显式布局
+
Orphan 禁止
+
ASSERT
```

形成一个很完整的保护层。

---

# 四十八、今天最重要的 7 个结论

## ① Orphan 是什么？

```text
Input Section
+
linker script 没有明确放置
=
Orphan
```

---

## ② 默认怎么办？

```text
--orphan-handling=place
```

也就是：

```text
ld 尝试自动放置。
```

([Sourceware][3])

---

## ③ 同名 Output Section 已存在怎么办？

```text
.my_code Input
       ↓
已有 .my_code Output
       ↓
放进去
```

如果 orphan input section 与已有 Output Section 同名，GNU ld 会把它放到该 Output Section 的末尾。([Sourceware][1])

---

## ④ 没有同名 Output Section 怎么办？

```text
.my_code
   ↓
自动创建
.my_code Output Section
```

([Sourceware][1])

---

## ⑤ 多个同名 Orphan？

```text
a.o:.custom
b.o:.custom
c.o:.custom
```

通常：

```text
.custom
 ├── a.o
 ├── b.o
 └── c.o
```

([Sourceware][1])

---

## ⑥ 如何发现 Orphan？

开发阶段：

```bash
--orphan-handling=warn
```

严格工程：

```bash
--orphan-handling=error
```

([Sourceware][4])

---

## ⑦ 如何分析？

永远：

```text
objdump -h input.o
       ↓
ld
       ↓
readelf -S
       ↓
objdump -h final.elf
       ↓
readelf -l
       ↓
nm
       ↓
Map
```

不要只看一个工具。

---

# 四十九、把实验 20 放回整个课程主线

现在路线变成：

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
PHDRS / PT_LOAD
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
        ↓
实验 20
ORPHAN SECTIONS
        ↓
```

下一步进入：

# 实验 21：`INSERT BEFORE` / `INSERT AFTER`

这一节会更进一步。

我们不再从零写完整 linker script，而是拿 GNU ld 的**默认 linker script**来改：

```bash
ld --verbose
```

得到默认布局，然后只插入：

```ld
INSERT AFTER .text;
```

或者：

```ld
INSERT BEFORE .data;
```

例如我们自己增加：

```text
.my_metadata
```

让它自动插到：

```text
.text
    ↓
.my_metadata
    ↓
.fini
```

而不用复制整个巨大默认 linker script。

这个实验会顺便解释一个非常重要的工程问题：

> **为什么大型工程通常不应该复制一整份系统默认 linker script，而应该尽可能用 `INSERT BEFORE/AFTER` 做局部扩展。**

然后再进入：

```text
实验 22  SUBALIGN() / ALIGN_WITH_INPUT()
实验 23  Output Section Fill / FILL()
实验 24  `/DISCARD/` 与垃圾 Section 管理
实验 25  完整 MCU linker.ld
实验 26  ELF → BIN / HEX
实验 27  startup.S + linker.ld
实验 28  从零制作一个可启动裸机 ELF
```

这时候我们就会开始把前面学的所有东西真正合并成一个完整的 **GNU ld 裸机固件工程**。

[1]: https://sourceware.org/binutils/docs-2.43/ld.pdf?utm_source=chatgpt.com "The GNU linker"
[2]: https://snapshots.sourceware.org/gcc/docs/latest/gcc/Common-Attributes.html?utm_source=chatgpt.com "Common Attributes (Using the GNU Compiler Collection (GCC))"
[3]: https://sourceware.org/binutils/docs/ld.pdf?utm_source=chatgpt.com "The GNU linker"
[4]: https://sourceware.org/binutils/docs-2.40/ld.pdf?utm_source=chatgpt.com "The GNU linker"

