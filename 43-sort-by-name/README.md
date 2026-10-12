# GNU ld 实战课程 · 实验 43
## `SORT_BY_NAME()` + `SORT_BY_ALIGNMENT()` + `EXCLUDE_FILE()`：输入 Section 的排序、筛选与布局优化

上一节实验 42，我们研究了 `EXTERN()`、`-u`、`KEEP()` 和 `--gc-sections`，解决了链接器如何引入模块、保留注册表以及回收无用代码的问题。

本节继续沿着原来的路线，研究另一个关键问题：

**当多个目标文件向同一个输出 Section 提供内容时，GNU ld 如何决定它们的排列顺序？**

这次继续使用嵌入式插件注册表作为实验场景。我们将创建四个插件，让它们分别具有不同的 Section 名称和对齐要求，再逐步比较：

- 默认输入顺序。
- `SORT_BY_NAME()` 按名称排序。
- `SORT_BY_ALIGNMENT()` 按对齐要求排序。
- `EXCLUDE_FILE()` 排除指定目标文件。
- 排序、筛选与 Map 文件的综合分析。

本节的实验使用 x86-64 Linux、GCC 和 GNU Binutils。下面给出的具体地址和大小，已经在 GCC 14.2、GNU ld 2.44 的环境中验证。其他版本可能存在细微差异。

官方参考：[GNU ld 官方手册：Input Section Wildcard Patterns](https://sourceware.org/binutils/docs/ld.html?utm_source=chatgpt.com)。

---

# 一、本节学习目标

完成实验 43 后，你应该能够回答以下问题。

| 问题 | 对应知识点 |
|---|---|
| 输入 Section 默认按什么顺序排列？ | 输入文件顺序与通配符匹配 |
| `SORT_BY_NAME()` 排序的是什么？ | Section 名称 |
| `SORT_BY_ALIGNMENT()` 如何排序？ | 按对齐要求降序排列 |
| 排序为什么可能减少填充空间？ | Section 对齐与地址布局 |
| 排序一定能减少 ELF 大小吗？ | 不一定，需要实测 |
| `EXCLUDE_FILE()` 能否直接删除一个 Section？ | 不能，它只排除当前匹配规则 |
| 排除的 Section 最后去了哪里？ | 其他匹配规则或孤儿 Section 处理 |
| 排序结果如何验证？ | `readelf`、`objdump`、`nm` |
| Map 文件如何显示排序效果？ | 输入 Section 的地址和排列顺序 |

本节最重要的原则是：

**不要只看 linker script 写了什么，要检查最终 ELF 中的实际地址，并通过 Map 文件解释地址为什么这样排列。**

---

# 二、先理解输入 Section 与输出 Section

假设有四个插件：

```text
plugin_alpha.o
└── .plugin.alpha

plugin_mu.o
└── .plugin.mu

plugin_zeta.o
└── .plugin.zeta

plugin_skip.o
└── .plugin.skip
```

我们希望把它们放入同一个输出 Section：

```ld
.plugins :
{
    *(.plugin.*)
}
```

这里有两个不同的概念。

**输入 Section：**

```text
.plugin.alpha
.plugin.mu
.plugin.zeta
.plugin.skip
```

**输出 Section：**

```text
.plugins
```

GNU ld 会将匹配的输入 Section 按照链接脚本中的规则组合到输出 Section 中。

如果没有使用排序命令，链接器通常按照输入文件和 Section 的出现顺序处理匹配项。`SORT_BY_NAME()` 和 `SORT_BY_ALIGNMENT()` 可以改变这一顺序。[Sourceware](https://sourceware.org/binutils/docs/ld.html?utm_source=chatgpt.com)

我们先通过实验观察默认行为，再加入排序规则。

---

# 三、实验目录

创建目录：

```bash
mkdir -p 43-section-sorting
cd 43-section-sorting
```

本节需要这些文件：

```text
43-section-sorting/
├── start.S
├── plugin_alpha.c
├── plugin_mu.c
├── plugin_zeta.c
├── plugin_skip.c
├── linker-base.ld
├── linker-sort-name.ld
├── linker-sort-align.ld
└── linker-exclude.ld
```

我们只研究链接器的布局行为，因此暂时不引入复杂的业务逻辑。

---

# 四、实验 43-1：编写最小启动代码

创建 `start.S`：

```asm
.global _start

.section .text.start,"ax",@progbits

.type _start,@function

_start:
    jmp _start

.size _start, .-_start

.section .note.GNU-stack,"",@progbits
```

这里：

```asm
.section .text.start,"ax",@progbits
```

将入口代码放在 `.text.start` 中。

后续的 linker script 会优先安排这个 Section：

```ld
.text :
{
    *(.text.start)
    *(.text .text.*)
}
```

入口符号：

```text
_start
```

由：

```ld
ENTRY(_start)
```

指定。

这个程序只用于分析 ELF 文件，不需要实际执行。

---

# 五、实验 43-2：创建四个插件

这次我们故意让每个插件具有不同的对齐要求。

这样，`SORT_BY_ALIGNMENT()` 的效果就能直接反映在地址上。

## 5.1 插件 Alpha

创建 `plugin_alpha.c`：

```c
__attribute__((section(".plugin.alpha"), used, aligned(1)))
const unsigned char plugin_alpha[] = {
    0xA1
};
```

这个对象被放入：

```text
.plugin.alpha
```

并要求对齐值为 1。

## 5.2 插件 Mu

创建 `plugin_mu.c`：

```c
__attribute__((section(".plugin.mu"), used, aligned(8)))
const unsigned char plugin_mu[] = {
    0xB2
};
```

其输入 Section 为：

```text
.plugin.mu
```

对齐要求为 8 字节。

## 5.3 插件 Zeta

创建 `plugin_zeta.c`：

```c
__attribute__((section(".plugin.zeta"), used, aligned(16)))
const unsigned char plugin_zeta[] = {
    0xC3
};
```

其输入 Section 为：

```text
.plugin.zeta
```

对齐要求为 16 字节。

## 5.4 插件 Skip

创建 `plugin_skip.c`：

```c
__attribute__((section(".plugin.skip"), used, aligned(4)))
const unsigned char plugin_skip[] = {
    0xD4
};
```

其输入 Section 为：

```text
.plugin.skip
```

对齐要求为 4 字节。

这里的 `used` 要求编译器生成对应对象，但它本身不负责控制 GNU ld 的 Section 垃圾回收。本节暂时不启用 `--gc-sections`，以便单独观察排序。

---

# 六、实验 43-3：编译四个目标文件

执行：

```bash
CFLAGS="-O0 \
-ffreestanding \
-fno-pie \
-fno-pic \
-fno-asynchronous-unwind-tables \
-fno-unwind-tables \
-fdata-sections"

gcc $CFLAGS -c start.S -o start.o

gcc $CFLAGS -c plugin_alpha.c -o plugin_alpha.o
gcc $CFLAGS -c plugin_mu.c -o plugin_mu.o
gcc $CFLAGS -c plugin_zeta.c -o plugin_zeta.o
gcc $CFLAGS -c plugin_skip.c -o plugin_skip.o
```

现在查看输入 Section：

```bash
readelf -SW plugin_alpha.o
readelf -SW plugin_mu.o
readelf -SW plugin_zeta.o
readelf -SW plugin_skip.o
```

也可以集中检查：

```bash
for f in plugin_alpha.o plugin_mu.o plugin_zeta.o plugin_skip.o
do
    echo "===== $f ====="
    readelf -SW "$f" | grep '\.plugin\.'
done
```

在本节验证环境中，关键输出如下：

| 目标文件 | 输入 Section | 大小 | `sh_addralign` |
|---|---|---:|---:|
| `plugin_alpha.o` | `.plugin.alpha` | `0x1` | 1 |
| `plugin_mu.o` | `.plugin.mu` | `0x1` | 8 |
| `plugin_zeta.o` | `.plugin.zeta` | `0x1` | 16 |
| `plugin_skip.o` | `.plugin.skip` | `0x1` | 4 |

这里最重要的是最后一列。

`sh_addralign` 是 ELF Section Header 中的对齐要求。

例如：

```text
.plugin.zeta
sh_addralign = 16
```

表示该输入 Section 的地址必须满足 16 字节对齐约束。

**注意：Section 的大小与对齐要求是两回事。**

这四个 Section 都只有 1 字节，但它们的对齐要求不同。

接下来我们就能看到，这种差异如何影响最终地址。

---

# 七、实验 43-4：建立默认链接脚本

创建 `linker-base.ld`：

```ld
ENTRY(_start)

SECTIONS
{
    . = 0x00400000;

    .text :
    {
        *(.text.start)
        *(.text .text.*)
    }

    /*
     * 插件注册表。
     *
     * 不指定排序方式，
     * 按输入文件顺序匹配 Section。
     */
    .plugins : ALIGN(16)
    {
        __plugins_start = .;

        *(.plugin.*)

        __plugins_end = .;
    }
}
```

这里使用：

```ld
.plugins : ALIGN(16)
```

使输出 Section `.plugins` 满足 16 字节对齐要求。

注意，输出 Section 的对齐与输入 Section 的对齐是两个不同层次的约束。

即使输出 Section 的起始地址已经满足 16 字节对齐，内部的输入 Section 仍然需要满足各自的对齐要求。

链接命令如下：

```bash
ld \
    -T linker-base.ld \
    -Map=base.map \
    -o base.elf \
    start.o \
    plugin_alpha.o \
    plugin_mu.o \
    plugin_zeta.o \
    plugin_skip.o
```

这里故意按照下面的顺序传入目标文件：

```text
plugin_alpha.o
plugin_mu.o
plugin_zeta.o
plugin_skip.o
```

后续三个实验都保持这个输入文件顺序不变。

这样我们才能把地址变化归因于排序规则，而不是输入文件顺序的变化。

---

# 八、实验 43-4：检查默认排列结果

先执行：

```bash
nm -n base.elf | \
grep -E 'plugin_(alpha|mu|zeta|skip)|__plugins'
```

在本节验证环境中，输出为：

```text
0000000000400010 R __plugins_start
0000000000400010 R plugin_alpha
0000000000400018 R plugin_mu
0000000000400020 R plugin_zeta
0000000000400024 R plugin_skip
0000000000400025 R __plugins_end
```

因此，各对象的地址如下：

| 对象 | 地址 | 相对起始地址的偏移 |
|---|---:|---:|
| `plugin_alpha` | `0x400010` | `0x0` |
| `plugin_mu` | `0x400018` | `0x8` |
| `plugin_zeta` | `0x400020` | `0x10` |
| `plugin_skip` | `0x400024` | `0x14` |

为什么地址不是连续的？

因为链接器必须满足各个输入 Section 的对齐要求。

以 `plugin_alpha` 为例：

```text
地址：0x400010
大小：1 字节
```

下一个 Section 是 `plugin_mu`，要求 8 字节对齐。

当前地址：

```text
0x400010 + 1 = 0x400011
```

将其向上对齐到 8 字节边界：

```text
ALIGN_UP(0x400011, 8) = 0x400018
```

所以：

```text
plugin_mu = 0x400018
```

接下来，`plugin_mu` 占用 1 字节：

```text
0x400018 + 1 = 0x400019
```

`plugin_zeta` 要求 16 字节对齐：

```text
ALIGN_UP(0x400019, 16) = 0x400020
```

于是：

```text
plugin_zeta = 0x400020
```

最后：

```text
0x400020 + 1 = 0x400021
```

`plugin_skip` 要求 4 字节对齐：

```text
ALIGN_UP(0x400021, 4) = 0x400024
```

所以最终地址为：

```text
plugin_skip = 0x400024
```

整个 `.plugins` 输出 Section 的结束地址是：

```text
0x400025
```

起始地址为：

```text
0x400010
```

因此总大小：

```text
0x400025 - 0x400010 = 0x15
```

即：

```text
21 字节
```

这里的 21 字节不仅包括四个对象，还包括对象之间因对齐产生的填充。

---

# 九、实验 43-5：使用 `SORT_BY_NAME()`

现在修改排序规则。

创建 `linker-sort-name.ld`：

```ld
ENTRY(_start)

SECTIONS
{
    . = 0x00400000;

    .text :
    {
        *(.text.start)
        *(.text .text.*)
    }

    .plugins : ALIGN(16)
    {
        __plugins_start = .;

        SORT_BY_NAME(.plugin.*)

        __plugins_end = .;
    }
}
```

这里：

```ld
SORT_BY_NAME(.plugin.*)
```

表示将匹配该通配符的输入 Section 按名称升序排列。

官方手册指出，`SORT_BY_NAME` 根据名称升序排序，而 `SORT` 是它的别名。[Sourceware](https://sourceware.org/binutils/docs/ld.html?utm_source=chatgpt.com)

本实验的输入 Section 名称是：

```text
.plugin.alpha
.plugin.mu
.plugin.zeta
.plugin.skip
```

排序后应该是：

```text
.plugin.alpha
.plugin.mu
.plugin.skip
.plugin.zeta
```

注意：

**`SORT_BY_NAME()` 排序的是匹配到的输入 Section，不是按照变量名 `plugin_alpha`、`plugin_mu` 等进行排序。**

变量名与 Section 名称恰好存在对应关系，只是为了便于观察。

## 9.1 执行链接

```bash
ld \
    -T linker-sort-name.ld \
    -Map=sort-name.map \
    -o sort-name.elf \
    start.o \
    plugin_alpha.o \
    plugin_mu.o \
    plugin_zeta.o \
    plugin_skip.o
```

## 9.2 检查符号地址

执行：

```bash
nm -n sort-name.elf | \
grep -E 'plugin_(alpha|mu|zeta|skip)|__plugins'
```

本节验证环境中的输出：

```text
0000000000400010 R __plugins_start
0000000000400010 R plugin_alpha
0000000000400018 R plugin_mu
000000000040001c R plugin_skip
0000000000400020 R plugin_zeta
0000000000400021 R __plugins_end
```

与默认版本相比，发生了什么？

原来：

```text
plugin_zeta = 0x400020
plugin_skip = 0x400024
```

现在：

```text
plugin_skip = 0x40001c
plugin_zeta = 0x400020
```

`plugin_skip` 被排到了 `plugin_zeta` 前面。

而且，`.plugins` 的总大小从：

```text
0x15
```

减少到：

```text
0x11
```

即从 21 字节减少到 17 字节。

## 9.3 为什么排序后填充减少了？

新的排列顺序：

```text
alpha → mu → skip → zeta
```

地址分布：

| 对象 | 起始地址 | 大小 | 对齐要求 |
|---|---:|---:|---:|
| Alpha | `0x400010` | 1 | 1 |
| Mu | `0x400018` | 1 | 8 |
| Skip | `0x40001c` | 1 | 4 |
| Zeta | `0x400020` | 1 | 16 |

虽然 `SORT_BY_NAME()` 并不是专门为减少填充设计的，但改变输入 Section 的顺序可能让对齐间隙得到更合理的利用。

这次排序使填充总量从：

```text
17 字节
```

减少到：

```text
13 字节
```

四个插件本身仍然只占 4 字节。

其余空间都是对齐填充。

这也说明，**不能只看源代码大小来判断最终 ELF 的布局成本。**

---

# 十、实验 43-6：使用 `SORT_BY_ALIGNMENT()`

接下来使用专门考虑对齐要求的排序方式。

创建 `linker-sort-align.ld`：

```ld
ENTRY(_start)

SECTIONS
{
    . = 0x00400000;

    .text :
    {
        *(.text.start)
        *(.text .text.*)
    }

    .plugins : ALIGN(16)
    {
        __plugins_start = .;

        SORT_BY_ALIGNMENT(.plugin.*)

        __plugins_end = .;
    }
}
```

核心表达式：

```ld
SORT_BY_ALIGNMENT(.plugin.*)
```

它会按照输入 Section 的对齐要求降序排列，也就是：

```text
对齐要求越大，越优先放置。
```

例如：

```text
16 字节
8 字节
4 字节
1 字节
```

官方手册说明，这样排列较大的对齐要求时，可能减少后续布局所需的填充。[Sourceware](https://sourceware.org/binutils/docs/ld.html?utm_source=chatgpt.com)

## 10.1 执行链接

```bash
ld \
    -T linker-sort-align.ld \
    -Map=sort-align.map \
    -o sort-align.elf \
    start.o \
    plugin_alpha.o \
    plugin_mu.o \
    plugin_zeta.o \
    plugin_skip.o
```

## 10.2 检查符号地址

执行：

```bash
nm -n sort-align.elf | \
grep -E 'plugin_(alpha|mu|zeta|skip)|__plugins'
```

本节验证环境中的输出：

```text
0000000000400010 R __plugins_start
0000000000400010 R plugin_zeta
0000000000400018 R plugin_mu
000000000040001c R plugin_skip
000000000040001d R plugin_alpha
000000000040001e R __plugins_end
```

新的顺序是：

```text
Zeta → Mu → Skip → Alpha
```

对应的对齐要求：

```text
16 → 8 → 4 → 1
```

完全符合预期。

## 10.3 计算最终空间

`.plugins` 起始地址：

```text
0x400010
```

Zeta：

```text
0x400010
```

占用 1 字节。

Mu 需要 8 字节对齐：

```text
ALIGN_UP(0x400011, 8) = 0x400018
```

Skip 需要 4 字节对齐：

```text
ALIGN_UP(0x400019, 4) = 0x40001c
```

Alpha 只要求 1 字节对齐：

```text
0x40001d
```

最后结束于：

```text
0x40001e
```

因此总大小：

```text
0x40001e - 0x400010 = 0x0e
```

即：

```text
14 字节
```

与默认排列的 21 字节相比：

```text
21 - 14 = 7 字节
```

本实验减少了 7 字节填充。

不过，这并不意味着 `SORT_BY_ALIGNMENT()` 对任何输入都一定能减少填充。实际效果取决于 Section 的大小、对齐要求和排列顺序。

**正确的工程做法是先提出排序策略，再通过 Map 文件验证是否真的节省空间。**

---

# 十一、实验 43-7：使用 `EXCLUDE_FILE()` 排除特定目标文件

前两个实验改变了输入 Section 的顺序。

现在我们增加一个新的需求：

> 所有插件都参与链接，但 `.plugins` 注册表只收录部分插件。

例如：

```text
.plugin.alpha    收录
.plugin.mu       收录
.plugin.zeta     收录
.plugin.skip     不收录
```

注意，我们这里不是让 `plugin_skip.o` 完全不参与链接，而是希望将它的 Section 放到另一个输出 Section 中。

这正是 `EXCLUDE_FILE()` 适合解决的问题。

## 11.1 编写链接脚本

创建 `linker-exclude.ld`：

```ld
ENTRY(_start)

SECTIONS
{
    . = 0x00400000;

    .text :
    {
        *(.text.start)
        *(.text .text.*)
    }

    /*
     * 正常插件注册表。
     *
     * 排除 plugin_skip.o 提供的输入 Section。
     */
    .plugins : ALIGN(16)
    {
        __plugins_start = .;

        *(SORT_BY_NAME(
            EXCLUDE_FILE (plugin_skip.o)
            .plugin.*
        ))

        __plugins_end = .;
    }

    /*
     * 被排除的 Section 单独放置。
     */
    .plugins_excluded : ALIGN(4)
    {
        __plugins_excluded_start = .;

        plugin_skip.o(.plugin.*)

        __plugins_excluded_end = .;
    }
}
```

这段脚本中最关键的语法是：

```ld
*(SORT_BY_NAME(
    EXCLUDE_FILE (plugin_skip.o)
    .plugin.*
))
```

它完成两件事：

1. 将 `plugin_skip.o` 从当前通配符匹配范围中排除。
2. 对剩余匹配项按照 Section 名称排序。

GNU ld 官方文档明确指出，`EXCLUDE_FILE` 可以放在排序命令内部，例如：

```ld
*(SORT_BY_NAME(EXCLUDE_FILE(foo) .text*))
```

而把排序命令反过来放在 `EXCLUDE_FILE` 内部则不符合该语法。[Sourceware](https://sourceware.org/binutils/docs/ld.html?utm_source=chatgpt.com)

## 11.2 为什么要额外定义 `.plugins_excluded`？

这是一个很重要的细节。

`EXCLUDE_FILE()` 的含义是：

**从当前输入 Section 匹配规则中排除指定文件，并不等于从 ELF 文件中彻底删除该 Section。**

如果没有其他规则接收它，未被匹配的 Section 仍可能作为孤儿 Section 被链接器安排到输出文件中。

因此，我们明确添加：

```ld
.plugins_excluded :
{
    plugin_skip.o(.plugin.*)
}
```

把被排除的内容放在另一个输出 Section 中。

这样才能明确验证它没有进入正常的 `.plugins` 注册表。

---

# 十二、实验 43-7：执行链接并验证结果

执行：

```bash
ld \
    -T linker-exclude.ld \
    -Map=exclude.map \
    -o exclude.elf \
    start.o \
    plugin_alpha.o \
    plugin_mu.o \
    plugin_zeta.o \
    plugin_skip.o
```

然后执行：

```bash
nm -n exclude.elf | \
grep -E 'plugin_(alpha|mu|zeta|skip)|__plugins'
```

本节验证环境中的输出：

```text
0000000000400010 R __plugins_start
0000000000400010 R plugin_alpha
0000000000400018 R plugin_mu
0000000000400020 R plugin_zeta
0000000000400021 R __plugins_end
0000000000400024 R __plugins_excluded_start
0000000000400024 R plugin_skip
0000000000400025 R __plugins_excluded_end
```

观察地址：

```text
__plugins_start          = 0x400010
__plugins_end            = 0x400021
__plugins_excluded_start = 0x400024
__plugins_excluded_end   = 0x400025
```

可以看出：

```text
.plugins
    alpha
    mu
    zeta

.plugins_excluded
    skip
```

`plugin_skip` 仍然存在于最终 ELF 中，但它没有被放入正常注册表。

这与 `/DISCARD/` 完全不同。

如果我们希望彻底丢弃匹配的输入 Section，可以使用 `/DISCARD/`，但那是另一种操作。

---

# 十三、实验 43-8：使用 `readelf` 验证 ELF

现在从 ELF 文件角度交叉验证。

## 13.1 检查输出 Section

执行：

```bash
readelf -SW base.elf
readelf -SW sort-name.elf
readelf -SW sort-align.elf
readelf -SW exclude.elf
```

重点关注：

```text
.plugins
.plugins_excluded
```

对照各输出 Section 的：

- 地址。
- 大小。
- 文件偏移。
- 对齐要求。

在验证环境中，`.plugins` 的大小分别为：

| 文件 | `.plugins` 大小 |
|---|---:|
| `base.elf` | `0x15` |
| `sort-name.elf` | `0x11` |
| `sort-align.elf` | `0x0e` |
| `exclude.elf` | `0x11` |

这里可以看到，排序改变了 Section 的内部布局和最终大小。

而 `EXCLUDE_FILE()` 则改变了哪些输入 Section 被放入 `.plugins`。

## 13.2 检查符号表

执行：

```bash
readelf -sW sort-align.elf | \
grep -E 'plugin_(alpha|mu|zeta|skip)|__plugins'
```

这一步可以确认各个插件符号的最终地址。

## 13.3 检查 Program Header

执行：

```bash
readelf -lW sort-align.elf
```

再执行：

```bash
readelf -lW exclude.elf
```

观察：

```text
LOAD
```

以及输出末尾的：

```text
Section to Segment mapping
```

这可以帮助你进一步判断 `.plugins` 和 `.plugins_excluded` 被安排到了哪些 Segment。

注意，Section 的排序并不等同于 Segment 的排序。一个输出 Section 的地址、大小和文件偏移，需要结合实际 Program Header 才能完整理解。

---

# 十四、实验 43-9：使用 `objdump` 验证实际内容

现在切换到 `objdump`。

## 14.1 查看 Section 大小和地址

执行：

```bash
objdump -h base.elf
objdump -h sort-name.elf
objdump -h sort-align.elf
objdump -h exclude.elf
```

重点字段：

```text
Size
VMA
LMA
File off
Algn
```

你会发现，虽然四个插件都只有一个字节，但 `.plugins` 仍然可能占据十几字节。

这是因为 Section 对齐可能导致填充。

## 14.2 查看 `.plugins` 的真实内容

执行：

```bash
objdump -s -j .plugins base.elf
```

再执行：

```bash
objdump -s -j .plugins sort-name.elf
```

以及：

```bash
objdump -s -j .plugins sort-align.elf
```

由于每个插件的内容分别是：

```text
Alpha = 0xA1
Mu    = 0xB2
Zeta  = 0xC3
Skip  = 0xD4
```

你可以从十六进制输出中识别它们的排列顺序。

在本节验证环境中，关键内容如下：

**默认顺序：**

```text
A1 ... B2 ... C3 ... D4
```

**按名称排序：**

```text
A1 ... B2 ... D4 ... C3
```

**按对齐要求排序：**

```text
C3 ... B2 ... D4 A1
```

省略号代表对齐产生的填充字节。

这里有个很实用的技巧：

如果你研究的是初始化表、插件表或设备注册表，可以在实验阶段给不同条目使用明显不同的标记值，再通过 `objdump -s` 检查实际顺序。

这往往比只看符号表更直观。

---

# 十五、实验 43-10：Map 文件分析

本节的重点不仅是会写排序语句，还要能够解释排序结果。

## 15.1 分析默认版本

执行：

```bash
grep -n -A15 -B3 \
-E '\.plugin\.(alpha|mu|zeta|skip)' \
base.map
```

你应该能看到类似的输入 Section 条目：

```text
.plugin.alpha  0x0000000000400010  0x1 plugin_alpha.o
.plugin.mu     0x0000000000400018  0x1 plugin_mu.o
.plugin.zeta   0x0000000000400020  0x1 plugin_zeta.o
.plugin.skip   0x0000000000400024  0x1 plugin_skip.o
```

注意，Map 文件中的地址与 `nm -n` 中的符号地址相对应。

因此，我们可以使用 Map 文件解释为什么每个对象落在那个位置。

## 15.2 分析名称排序

执行：

```bash
grep -n -A15 -B3 \
-E '\.plugin\.(alpha|mu|zeta|skip)' \
sort-name.map
```

预期的顺序是：

```text
.plugin.alpha
.plugin.mu
.plugin.skip
.plugin.zeta
```

再计算：

```text
__plugins_end - __plugins_start
```

可以验证输出 Section 的总大小。

## 15.3 分析对齐排序

执行：

```bash
grep -n -A15 -B3 \
-E '\.plugin\.(alpha|mu|zeta|skip)' \
sort-align.map
```

预期的顺序是：

```text
.plugin.zeta
.plugin.mu
.plugin.skip
.plugin.alpha
```

对应的对齐要求为：

```text
16 → 8 → 4 → 1
```

现在对照 Map 文件与 `readelf -SW` 的结果，可以确认：

- Section 的排列顺序发生了变化。
- 各输入 Section 的起始地址发生了变化。
- 填充量发生了变化。
- 输出 Section 的大小发生了变化。

## 15.4 分析排除规则

执行：

```bash
grep -n -A15 -B3 \
-E '\.plugin\.(alpha|mu|zeta|skip)' \
exclude.map
```

你应该看到：

```text
.plugins
    .plugin.alpha
    .plugin.mu
    .plugin.zeta

.plugins_excluded
    .plugin.skip
```

这就证明 `EXCLUDE_FILE()` 只改变了当前输出 Section 的匹配范围，而我们通过后续规则明确接收了被排除的 Section。

---

# 十六、把四种布局放在一起比较

经过前面的实验，我们得到以下结果。

| 版本 | 输入 Section 顺序 | `.plugins` 大小 | 主要效果 |
|---|---|---:|---|
| 默认版本 | Alpha → Mu → Zeta → Skip | `0x15` | 按输入顺序匹配 |
| `SORT_BY_NAME()` | Alpha → Mu → Skip → Zeta | `0x11` | 按名称升序 |
| `SORT_BY_ALIGNMENT()` | Zeta → Mu → Skip → Alpha | `0x0e` | 按对齐要求降序 |
| `EXCLUDE_FILE()` | Alpha → Mu → Zeta | `0x11` | 将 Skip 排除出注册表 |

本实验中：

```text
默认版本：21 字节
名称排序：17 字节
对齐排序：14 字节
```

与默认版本相比：

```text
名称排序节省 4 字节
对齐排序节省 7 字节
```

这些结果说明，输入 Section 的排序策略确实会影响最终布局。

不过，在实际项目中，排序的目的不一定只是节省空间。

例如：

- 插件注册表可能要求稳定的名称顺序。
- 驱动初始化表可能要求按优先级排列。
- 特定硬件描述符可能要求较大的对齐。
- 某些输入文件可能需要排除在某个注册表之外。

因此，**排序策略应由工程约束决定，再通过链接结果验证，而不是为了使用某个命令而使用它。**

---

# 十七、进阶：嵌套排序命令

GNU ld 还支持有限的嵌套排序。

例如：

```ld
SORT_BY_NAME(
    SORT_BY_ALIGNMENT(.plugin.*)
)
```

这种形式的含义是：

1. 首先按照 Section 名称排序。
2. 当 Section 名称相同时，再按照对齐要求排序。

另一种形式：

```ld
SORT_BY_ALIGNMENT(
    SORT_BY_NAME(.plugin.*)
)
```

则是：

1. 首先按照对齐要求排序。
2. 对齐要求相同时，再按照名称排序。

官方文档对这两种嵌套形式有明确规定，并限制了排序命令的嵌套层级。[Sourceware](https://sourceware.org/binutils/docs/ld.html?utm_source=chatgpt.com)

需要注意，只有在实际输入中存在名称相同但对齐要求不同，或者对齐要求相同但名称不同的情况时，这种次级排序才会体现出来。

本节四个插件的 Section 名称都不同，而且对齐要求也不同，因此单纯增加嵌套并不会让当前示例产生额外收益。

---

# 十八、进阶：通过命令行控制排序

GNU ld 还提供：

```bash
--sort-section=name
```

以及：

```bash
--sort-section=alignment
```

例如：

```bash
ld \
    --sort-section=alignment \
    -T linker-base.ld \
    -Map=cli-sort.map \
    -o cli-sort.elf \
    start.o \
    plugin_alpha.o \
    plugin_mu.o \
    plugin_zeta.o \
    plugin_skip.o
```

该选项可以对 linker script 中的通配符 Section 匹配应用相应的排序策略。

但要注意：如果 linker script 已经明确指定了排序命令，脚本中的排序规则具有优先权；命令行排序选项还会与脚本中的排序规则发生特定的组合关系。[Debian Sources](https://sources.debian.org/src/binutils/2.44-3/ld/ld.texi?utm_source=chatgpt.com)

因此，在正式工程中，如果某个输出 Section 的排序顺序是接口契约的一部分，建议直接在 linker script 中写明排序规则。

这样更容易审查，也更容易通过 Map 文件复现和验证。

---

# 十九、常见错误与排查方法

## 错误 1：认为 `SORT_BY_NAME()` 按变量名排序

错误理解：

```text
plugin_alpha
plugin_mu
plugin_zeta
```

所以链接器会按照变量名排序。

正确理解：

```ld
SORT_BY_NAME(.plugin.*)
```

排序依据是匹配到的输入 Section 名称。

因此，如果变量名是：

```text
plugin_alpha
```

但输入 Section 名称是：

```text
.plugin.zeta
```

排序时使用的是 `.plugin.zeta`。

## 错误 2：认为 `SORT_BY_ALIGNMENT()` 总能减少填充

它会按照对齐要求降序排列，但并不能保证任何输入布局都变得更紧凑。

实际填充量还受到：

- 各 Section 的大小。
- 各 Section 的对齐要求。
- 输出 Section 的起始地址。
- Section 的排列顺序。

等因素影响。

应使用：

```bash
objdump -h output.elf
```

以及 Map 文件进行验证。

## 错误 3：认为 `EXCLUDE_FILE()` 会删除 Section

例如：

```ld
.plugins :
{
    *(EXCLUDE_FILE (plugin_skip.o) .plugin.*)
}
```

这只表示当前匹配规则不接收 `plugin_skip.o` 中符合模式的 Section。

如果没有其他规则处理它，它仍可能作为孤儿 Section 出现在输出文件中。

如果你希望将它放入另一个输出 Section，就像本实验一样，明确写出：

```ld
.plugins_excluded :
{
    plugin_skip.o(.plugin.*)
}
```

如果希望彻底丢弃它，则需要考虑 `/DISCARD/` 等机制。

## 错误 4：只看 `objdump -h`，不看 Map 文件

`objdump -h` 可以告诉你输出 Section 的大小、地址和文件偏移。

但它通常不能单独解释每个输入 Section 为什么落在那个地址。

因此，本课程建议采用以下组合：

```bash
readelf -SW output.elf
objdump -h output.elf
nm -n output.elf
grep -n '\.plugin\.' output.map
```

这四种视角互相补充，可以更快地定位布局问题。

---

# 二十、本节综合练习：构建一个真正可检查的插件注册表

现在给自己一个开放式练习。

假设你正在开发一个嵌入式 IoT 数据处理引擎，包含：

```text
sensor
filter
storage
network
diagnostics
```

五个模块都需要向 `.plugin_registry` 注册。

请自行完成以下要求。

### 练习 1：统一 Section 命名

使用：

```text
.plugin.sensor
.plugin.filter
.plugin.storage
.plugin.network
.plugin.diagnostics
```

每个 Section 至少包含一个公开符号。

### 练习 2：比较两种排序策略

分别使用：

```ld
SORT_BY_NAME(.plugin.*)
```

和：

```ld
SORT_BY_ALIGNMENT(.plugin.*)
```

比较它们的排列顺序和最终 Section 大小。

### 练习 3：排除调试插件

让 `diagnostics.o` 不进入正常注册表，但仍然保留在最终 ELF 中。

建议采用：

```ld
EXCLUDE_FILE (diagnostics.o)
```

并将它单独放入：

```text
.plugins_excluded
```

### 练习 4：增加边界检查

增加：

```ld
ASSERT(
    SIZEOF(.plugins) <= 0x400,
    "plugin registry exceeds 1 KiB"
)
```

如果注册表超过 1 KiB，链接应该失败。

### 练习 5：提交验收结果

需要提供：

```text
1. 所有 C 源码
2. 完整 linker script
3. 编译命令
4. 链接命令
5. readelf -SW 输出
6. objdump -h 输出
7. nm -n 输出
8. Map 文件中的插件布局
9. 排序前后的空间比较
```

最终验收标准不是“脚本能够链接成功”，而是你能解释每个插件的最终地址，并说明排序规则为什么产生了相应的结果。

---

# 二十一、实验 43 最终知识地图

```text
                   GNU ld
                      │
                      ▼
              输入 Section 匹配
                      │
          ┌───────────┼────────────┐
          │           │            │
          ▼           ▼            ▼
      默认顺序    SORT_BY_NAME  SORT_BY_ALIGNMENT
          │           │            │
          │           ▼            ▼
          │        名称升序      对齐降序
          │           │            │
          └───────────┼────────────┘
                      │
                      ▼
              输出 Section 布局
                      │
            ┌─────────┴─────────┐
            │                   │
            ▼                   ▼
        地址对齐             填充空间
            │                   │
            └─────────┬─────────┘
                      │
                      ▼
                 最终 ELF
                      │
          ┌───────────┼───────────┐
          │           │           │
          ▼           ▼           ▼
       readelf     objdump       Map
```

`EXCLUDE_FILE()` 则在输入 Section 匹配阶段增加筛选条件：

```text
输入 Section
      │
      ▼
EXCLUDE_FILE()
      │
      ├── 匹配并保留在目标输出 Section
      │
      └── 被当前规则排除
                 │
                 ▼
        由其他规则处理，或成为孤儿 Section
```

本节最值得记住的三点：

1. **`SORT_BY_NAME()` 排序的是输入 Section 名称，而不是 C 变量名。**
2. **`SORT_BY_ALIGNMENT()` 按对齐要求降序排列，但空间优化效果必须实测。**
3. **`EXCLUDE_FILE()` 只改变当前匹配规则，不等于彻底删除输入 Section。**

官方参考：[GNU ld 输入 Section 通配符与排序规则](https://sourceware.org/binutils/docs/ld.html?utm_source=chatgpt.com)、[GNU ld 命令行选项](https://sources.debian.org/src/binutils/2.44-3/ld/ld.texi?utm_source=chatgpt.com)。

---

# 二十二、下一节：实验 44

## `SORT_BY_INIT_PRIORITY()` + `.init_array` + 构造函数初始化顺序

前面三节的重点分别是：

- 实验 41：通过 `OVERLAY`、`NOCROSSREFS` 和 `ASSERT()` 管理共享内存及模块依赖。
- 实验 42：通过 `EXTERN()`、`KEEP()` 和 `--gc-sections` 控制模块引入与 Section 回收。
- 实验 43：通过排序和筛选控制输入 Section 的布局。

下一节，我们将进入另一个很有工程价值的场景：

**当多个 C/C++ 模块需要在程序启动阶段执行初始化函数时，GNU ld 如何安排这些初始化条目？**

实验 44 将逐步研究：

1. GCC 构造函数如何生成 `.init_array.*` 输入 Section。
2. `SORT_BY_INIT_PRIORITY()` 如何按照初始化优先级排序。
3. `.init_array` 与普通 `.text`、`.data` 有什么不同。
4. 如何使用 `readelf -SW` 查看初始化 Section。
5. 如何使用 `readelf -x` 和 `objdump -s` 验证初始化表的实际内容。
6. 如何通过 Map 文件分析初始化条目的排列顺序。
7. 为什么链接顺序、构造函数优先级和实际运行顺序不能简单地画等号。

我们将继续使用同一套实验方法：**先编写源码，再编译成目标文件，然后控制链接规则，最后通过 ELF 和 Map 文件验证每一个结论。**

I've paused this task because updates haven't been viewed in a while. You can resume it in the Scheduled tab or by asking ChatGPT.
