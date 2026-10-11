# GNU ld 实战课程：实验 40
## `DATA_SEGMENT_ALIGN()` + `DATA_SEGMENT_RELRO_END()` + `DATA_SEGMENT_END()` 深入剖析

上一节实验 39，我们研究了：

- 多个 `PT_LOAD` Segment 的布局。
- `p_align` 与 Section Alignment 的区别。
- `MAXPAGESIZE` 和 `COMMONPAGESIZE`。
- `-z max-page-size` 对 ELF 布局的影响。
- 如何通过 `readelf`、`objdump` 和 Map 文件定位 Segment 间的空洞。

本节继续推进，但我们换一个角度：**研究 GNU ld 默认链接脚本如何安排数据段，以及它如何通过 RELRO 机制保护程序运行时的数据。**

这一次不仅要理解语法，还要把 GNU ld 的内部布局策略与最终 ELF 文件对应起来。

我们将使用真正的 ELF 可执行程序进行实验，而不是只写几个孤立的 linker script 片段。

官方参考资料：[GNU ld Built-in Functions 文档](https://sourceware.org/binutils/docs/ld/Builtin-Functions.html?utm_source=chatgpt.com)。

---

# 一、本节的学习目标

完成实验 40 后，你应该能够回答以下问题。

| 问题 | 对应知识点 |
|---|---|
| GNU ld 如何安排数据段的起始位置？ | `DATA_SEGMENT_ALIGN()` |
| 为什么数据段有时会多占一些文件空间？ | 页面大小与布局优化 |
| `PT_GNU_RELRO` 是什么？ | RELRO |
| `DATA_SEGMENT_RELRO_END()` 在做什么？ | 确定 RELRO 区域边界 |
| `DATA_SEGMENT_END()` 有什么作用？ | 数据段布局计算 |
| `-z relro` 与 `-z now` 有什么区别？ | 部分 RELRO 与完整 RELRO |
| 为什么默认 linker script 中有这些复杂表达式？ | GNU ld 默认布局策略 |
| 如何证明某个 Section 属于 RELRO？ | `readelf -lW` |
| Map 文件能否直接展示 RELRO 的全部信息？ | Section 与 Segment 的交叉验证 |

本节有一个重要原则：

**不要先假定链接器应该生成什么布局，再强行让输出符合预期。先观察目标平台的默认脚本，再通过 ELF 文件验证实际行为。**

这是我们后续分析 Linux 可执行文件、共享库和自定义 linker script 的基础。

---

# 二、先建立 RELRO 的基本模型

RELRO 是 `Relocation Read-Only` 的缩写，可以理解为：**在动态重定位完成后，将特定内存区域设置为只读。**

为什么需要它？

动态链接程序启动时，动态链接器需要修正一些地址，例如：

- 全局变量的地址。
- 函数指针。
- GOT（Global Offset Table）中的地址。
- 其他需要动态重定位的数据。

重定位完成后，其中一部分数据就不再需要修改。

如果这些数据仍然保持可写，攻击者在程序发生其他安全漏洞时，可能利用这些可写区域篡改控制流。

RELRO 的目的就是缩小这类可写区域。

## 2.1 普通数据与 RELRO 数据

可以先建立下面的概念模型：

```text
ELF 可执行文件
│
├── .text
│     └── 程序指令
│
├── .rodata
│     └── 常量数据
│
├── .data
│     └── 普通可写数据
│
├── .data.rel.ro
│     └── 需要重定位、之后可只读的数据
│
├── .got
│     └── 全局偏移表
│
└── .got.plt
      └── 与 PLT 动态函数绑定有关的数据
```

注意，这只是常见的 Section 示例，并不是所有 ELF 文件都一定包含这些 Section。

更重要的是：

**Section 的名称并不直接决定最终内存权限。最终还需要结合 Program Header、链接选项和动态链接器的行为判断。**

---

# 三、实验环境检查

本节针对 GNU/Linux ELF 环境设计。

先执行：

```bash
gcc --version
ld --version
readelf --version
objdump --version
```

重点确认：

```text
GNU ld
GNU readelf
GNU objdump
```

如果当前环境是 macOS 自带的 Apple linker，那么它不是 GNU ld，部分选项和脚本语法可能不同。建议使用 Linux 虚拟机、Linux 容器或安装了 GNU Binutils 的 Linux 环境完成本节实验。

再确认当前链接器的目标平台：

```bash
ld -V
```

检查支持的链接目标和 emulation。

接着查看默认 linker script：

```bash
ld --verbose > ld-default-output.txt
```

搜索本节涉及的函数：

```bash
grep -nE \
'DATA_SEGMENT_ALIGN|DATA_SEGMENT_RELRO_END|DATA_SEGMENT_END' \
ld-default-output.txt
```

在常见的 GNU/Linux 动态可执行文件链接脚本中，你通常会找到这些表达式。

具体位置和参数会随目标平台、Binutils 版本及默认脚本而变化。

**先把输出保存下来，后续实验都以你的实际输出为准。**

---

# 四、实验目录

建立：

```text
40-relro/
├── relro_demo.c
├── relro_demo.o
├── partial-relro
├── full-relro
├── no-relro
├── partial-relro.map
├── full-relro.map
├── no-relro.map
└── ld-default-output.txt
```

其中，前三个可执行文件分别用于观察：

1. 启用 RELRO，但允许延迟绑定。
2. 启用 RELRO，并要求立即绑定。
3. 禁用 RELRO。

---

# 五、实验 40-1：编写一个最小动态链接程序

创建 `relro_demo.c`：

```c
#include <stdio.h>

static int mutable_value = 7;

/*
 * 指针本身是 const，
 * 但它指向的整数仍然可以修改。
 *
 * 在常见 ELF/PIC 构建中，
 * 这个需要地址重定位的只读指针
 * 通常会进入 .data.rel.ro 相关 Section。
 */
static int * const fixed_ptr = &mutable_value;

static const char message[] = "GNU ld RELRO";

int main(void)
{
    printf("%s: %d\n", message, *fixed_ptr);

    mutable_value++;

    printf("updated: %d\n", *fixed_ptr);

    return 0;
}
```

这里故意设置了三个不同的数据对象：

| 对象 | 特征 |
|---|---|
| `mutable_value` | 普通可写整数 |
| `fixed_ptr` | 指针本身只读，但需要保存一个地址 |
| `message` | 只读字符数组 |

最值得关注的是：

```c
static int * const fixed_ptr = &mutable_value;
```

这里的 `const` 修饰的是指针本身，而不是它指向的整数。

因此：

```c
mutable_value++;
```

仍然合法。

但是：

```c
fixed_ptr = NULL;
```

不合法。

在常见的 PIE 构建中，`fixed_ptr` 需要根据最终装载地址完成重定位，因此可以用它观察 `.data.rel.ro` 一类的 Section。

需要注意，编译器可能根据目标平台和优化策略改变具体 Section 的名称或布局。

---

# 六、编译目标文件

执行：

```bash
gcc \
    -O0 \
    -fPIE \
    -c relro_demo.c \
    -o relro_demo.o
```

这里：

- `-O0`：关闭常规优化，方便观察生成结果。
- `-fPIE`：生成适合位置无关可执行文件的代码。
- `-c`：只编译，不链接。

接着检查 Section：

```bash
readelf -SW relro_demo.o
```

搜索：

```bash
readelf -SW relro_demo.o | \
grep -E '\.data|\.rodata|\.text|\.rela'
```

也可以执行：

```bash
objdump -h relro_demo.o
```

观察目标文件中的：

```text
.text
.data
.data.rel.ro
.rodata
.rela.*
```

其中 `.rela.*` 是 ELF64 中常见的重定位 Section。

如果 `fixed_ptr` 所在 Section 名称与你预期不同，不要立即认定实验失败。先查看符号：

```bash
readelf -sW relro_demo.o
```

再查看重定位：

```bash
readelf -rW relro_demo.o
```

这一阶段要回答的是：

> 编译器生成了哪些 Section？哪些位置需要链接器处理重定位？

现在还没有最终的 `PT_GNU_RELRO`，因为它是最终链接结果中的 Program Header。

---

# 七、实验 40-2：构建三个不同的 ELF 文件

这次暂时不手写 `PHDRS`。

为什么？

因为我们要研究的是 GNU ld 默认脚本中的：

```ld
DATA_SEGMENT_ALIGN(...)
DATA_SEGMENT_RELRO_END(...)
DATA_SEGMENT_END(...)
```

如果此时又手动定义所有 Program Header，就会引入另一层变量，反而不容易看清默认布局策略。

本节先让 GNU ld 使用目标平台的默认 linker script。

## 7.1 构建部分 RELRO 版本

```bash
gcc \
    -fPIE \
    -pie \
    relro_demo.o \
    -Wl,-z,relro \
    -Wl,-Map=partial-relro.map \
    -o partial-relro
```

这里：

```bash
-Wl,-z,relro
```

让 GCC 将相应参数传给链接器。

`-z relro` 用于生成供动态链接器使用的 `PT_GNU_RELRO` 区域。

## 7.2 构建完整 RELRO 版本

```bash
gcc \
    -fPIE \
    -pie \
    relro_demo.o \
    -Wl,-z,relro,-z,now \
    -Wl,-Map=full-relro.map \
    -o full-relro
```

这里有两个选项：

```text
-z relro
-z now
```

分别负责不同的事情：

- `-z relro`：启用 RELRO 区域。
- `-z now`：要求在启动阶段立即完成动态符号绑定，而不是依赖传统的延迟绑定。

## 7.3 构建禁用 RELRO 的版本

```bash
gcc \
    -fPIE \
    -pie \
    relro_demo.o \
    -Wl,-z,norelro \
    -Wl,-Map=no-relro.map \
    -o no-relro
```

三个版本的差别如下：

| 文件 | 链接选项 | 目的 |
|---|---|---|
| `no-relro` | `-z norelro` | 观察没有 RELRO 时的布局 |
| `partial-relro` | `-z relro` | 观察启用 RELRO 的布局 |
| `full-relro` | `-z relro -z now` | 观察立即绑定与 RELRO 的组合 |

如果链接器提示不支持某个选项，先查看：

```bash
ld --help | grep -E 'relro|norelro|now'
```

确认当前链接器支持的参数。

---

# 八、实验 40-3：使用 `readelf -lW` 检查 RELRO

这是本节最重要的验证步骤。

执行：

```bash
readelf -lW no-relro
readelf -lW partial-relro
readelf -lW full-relro
```

分别寻找：

```text
GNU_RELRO
```

在通常的 GNU/Linux GNU ld 环境中，预期结果是：

| ELF 文件 | `PT_GNU_RELRO` |
|---|---|
| `no-relro` | 不存在 |
| `partial-relro` | 存在 |
| `full-relro` | 存在 |

`PT_GNU_RELRO` 是一种特殊的 Program Header，用于向动态链接器指出重定位完成后可以保护为只读的内存范围。

它不是普通的 `PT_LOAD`，但通常描述的是某个可加载内存区域的一部分。

可以把它理解成：

```text
PT_LOAD：RW
│
├── .data.rel.ro
├── .dynamic
├── .got
├── 其他相关数据
│
└── PT_GNU_RELRO 覆盖其中一部分
        │
        ▼
    重定位完成后
    将相应内存页保护为只读
```

实际包含哪些 Section，取决于目标平台、默认脚本和链接选项。

### 重点观察

在 `readelf -lW` 输出中，记录：

```text
Type
Offset
VirtAddr
PhysAddr
FileSiz
MemSiz
Flg
Align
```

其中 `GNU_RELRO` 一般会显示自己的起始地址和范围。

随后查看输出末尾的：

```text
Section to Segment mapping
```

这一步可以把 RELRO 的地址范围与具体 Section 对应起来。

官方 GNU ld 文档对 `DATA_SEGMENT_RELRO_END()` 的用途有明确说明：它参与确定启用 `-z relro` 时 `PT_GNU_RELRO` 的边界。[Sourceware](https://sourceware.org/binutils/docs/ld/Builtin-Functions.html?utm_source=chatgpt.com)

---

# 九、实验 40-4：理解 `DATA_SEGMENT_ALIGN()`

现在进入第一个核心函数。

在默认 linker script 中，你可能看到类似：

```ld
. = DATA_SEGMENT_ALIGN(
    CONSTANT (MAXPAGESIZE),
    CONSTANT (COMMONPAGESIZE)
);
```

这里的两个参数分别是：

```ld
CONSTANT (MAXPAGESIZE)
```

以及：

```ld
CONSTANT (COMMONPAGESIZE)
```

它们来自当前链接目标的配置。

## 9.1 它解决什么问题？

如果只是简单地写：

```ld
. = ALIGN(0x1000);
```

你是在要求当前位置按照 4 KiB 对齐。

但 GNU ld 的默认数据段布局还要考虑：

1. ELF Segment 的对齐约束。
2. 数据段在文件中的位置。
3. 数据段在运行时内存中的位置。
4. 页面大小不同的系统。
5. 页面填充对文件空间和运行时内存的影响。

`DATA_SEGMENT_ALIGN()` 是为这类布局问题设计的特殊函数。

GNU ld 文档指出，该函数会在两种布局策略之间进行选择：

- 一种偏向较大的对齐方式。
- 另一种利用常见页面大小调整地址，在适当情况下减少数据段需要占用的运行时页面，但可能增加文件中的填充。

因此，它并不等同于简单的：

```ld
. = ALIGN(CONSTANT (MAXPAGESIZE));
```

官方文档还特别说明，第二个参数 `commonpagesize` 应小于或等于第一个参数 `maxpagesize`。[Sourceware](https://sourceware.org/binutils/docs/ld.html?utm_source=chatgpt.com)

## 9.2 如何查看本机参数？

执行：

```bash
ld --verbose | grep -E \
'MAXPAGESIZE|COMMONPAGESIZE|DATA_SEGMENT_ALIGN'
```

你可能看到类似：

```ld
DATA_SEGMENT_ALIGN(
    CONSTANT (MAXPAGESIZE),
    CONSTANT (COMMONPAGESIZE)
)
```

注意，这里只展示表达式的形式，不代表你的目标平台一定采用相同的数值。

不要把某个平台的 `0x200000` 或 `0x1000` 直接当作所有 GNU ld 的固定值。

## 9.3 本实验要验证什么？

记录三个 ELF 文件中各个 `PT_LOAD` 的：

```text
Offset
VirtAddr
FileSiz
MemSiz
Align
```

然后比较：

```bash
objdump -h no-relro
objdump -h partial-relro
objdump -h full-relro
```

你要判断的是：

- Section 的地址是否发生变化？
- Section 的文件偏移是否发生变化？
- Segment 的对齐值是否发生变化？
- 文件大小是否发生变化？

**不要预设三个文件一定会出现明显的地址差异。** 小程序在不同链接配置下可能得到非常接近的布局。我们关注的是函数的设计目的，以及最终布局能否满足相应的对齐约束。

---

# 十、实验 40-5：理解 `DATA_SEGMENT_RELRO_END()`

接下来研究：

```ld
DATA_SEGMENT_RELRO_END(offset, exp)
```

默认 linker script 中可能出现类似：

```ld
. = DATA_SEGMENT_RELRO_END(24, .);
```

这里的 `24` 只是一个示例，实际参数应以当前目标的默认脚本为准。

函数的两个参数：

| 参数 | 含义 |
|---|---|
| `offset` | 参与计算 RELRO 边界的偏移量 |
| `exp` | 当前地址表达式，通常写成 `.` |

在启用 `-z relro` 时，该函数会根据 `DATA_SEGMENT_ALIGN()` 使用的常见页面大小调整 RELRO 区域末尾的位置，以便满足相应的页面边界要求。

没有启用 `-z relro` 时，这个函数不会执行相同的 RELRO 边界调整。

此外，它在 linker script 中的位置有严格要求：

**如果使用 `DATA_SEGMENT_RELRO_END()`，它必须位于 `DATA_SEGMENT_ALIGN()` 与 `DATA_SEGMENT_END()` 之间。**

这不是可以随便放在任意 Section 内的普通表达式。[Sourceware](https://sourceware.org/binutils/docs/ld/Builtin-Functions.html?utm_source=chatgpt.com)

## 10.1 观察默认脚本中的位置

先保存完整脚本：

```bash
ld --verbose > ld-default-output.txt
```

再搜索：

```bash
grep -n -A8 -B8 \
'DATA_SEGMENT_RELRO_END' \
ld-default-output.txt
```

接着查看它附近的 Section：

```bash
grep -nE \
'\.data\.rel\.ro|\.dynamic|\.got|\.got\.plt|DATA_SEGMENT' \
ld-default-output.txt
```

你要研究的是：

```text
数据段起始位置
       │
       ▼
DATA_SEGMENT_ALIGN()
       │
       ▼
相关数据 Section
       │
       ▼
DATA_SEGMENT_RELRO_END()
       │
       ▼
普通可写数据
       │
       ▼
DATA_SEGMENT_END()
```

这张图表示布局逻辑，不保证所有目标平台都以完全相同的 Section 顺序排列。

---

# 十一、实验 40-6：`DATA_SEGMENT_END()` 到底是什么？

这个函数通常以如下形式出现在 linker script 中：

```ld
. = DATA_SEGMENT_END(.);
```

它的主要作用是：

> 标记数据段的结束位置，供 `DATA_SEGMENT_ALIGN()` 的布局计算使用。

它并不是简单地：

```ld
. = .;
```

虽然从表面上看，参数是当前位置，返回值也与当前地址有关，但它还承担了 GNU ld 内部数据段布局计算的作用。

官方文档明确给出了：

```ld
. = DATA_SEGMENT_END(.);
```

这种用法。[Sourceware](https://sourceware.org/binutils/docs/ld.html?utm_source=chatgpt.com)

## 11.1 为什么不能随意删除？

考虑：

```ld
. = DATA_SEGMENT_ALIGN(
    CONSTANT (MAXPAGESIZE),
    CONSTANT (COMMONPAGESIZE)
);

/* 数据段中的若干 Section */

. = DATA_SEGMENT_RELRO_END(0, .);

/* 普通可写数据 */

. = DATA_SEGMENT_END(.);
```

这里三个函数形成了一个布局计算过程：

```text
DATA_SEGMENT_ALIGN
        │
        ▼
数据段布局
        │
        ▼
DATA_SEGMENT_RELRO_END
        │
        ▼
数据段剩余部分
        │
        ▼
DATA_SEGMENT_END
```

删除或移动这些表达式，可能改变链接器计算布局的方式。

不过，不要把它理解为“删除任何一个函数，链接器就一定报错”。实际后果取决于脚本结构和链接目标。

---

# 十二、实验 40-7：直接分析默认 linker script

现在做一个很值得反复练习的实验。

## 12.1 提取当前链接器的默认脚本

`ld --verbose` 输出中，通常包含当前 emulation 的默认 linker script。

在常见 GNU ld 输出格式下，可以尝试：

```bash
awk '
/^=+$/ {
    n++
    next
}
n == 1 {
    print
}
' ld-default-output.txt > default-linker.ld
```

检查文件：

```bash
head -n 30 default-linker.ld
```

然后：

```bash
grep -nE \
'DATA_SEGMENT_ALIGN|DATA_SEGMENT_RELRO_END|DATA_SEGMENT_END' \
default-linker.ld
```

如果提取结果为空，或者开头不是 linker script 内容，说明当前版本的 `ld --verbose` 输出格式可能不同。直接从 `ld-default-output.txt` 中定位两个分隔线之间的脚本即可。

**注意：此处提取的是目标平台的默认脚本，不是通用脚本。**

## 12.2 记录关键位置

执行：

```bash
grep -n -A10 -B10 \
'DATA_SEGMENT_ALIGN' \
default-linker.ld
```

再执行：

```bash
grep -n -A10 -B10 \
'DATA_SEGMENT_RELRO_END' \
default-linker.ld
```

最后：

```bash
grep -n -A10 -B10 \
'DATA_SEGMENT_END' \
default-linker.ld
```

把这三个位置对照起来，你就能看到 GNU ld 默认脚本如何组织数据段布局。

---

# 十三、实验 40-8：比较部分 RELRO 与完整 RELRO

前面我们已经生成了：

```text
no-relro
partial-relro
full-relro
```

现在从动态链接信息中观察它们的区别。

## 13.1 检查动态 Section

执行：

```bash
readelf -SW partial-relro
```

以及：

```bash
readelf -SW full-relro
```

重点搜索：

```text
.data.rel.ro
.dynamic
.got
.got.plt
.data
.bss
```

可以使用：

```bash
readelf -SW full-relro | \
grep -E '\.data\.rel\.ro|\.dynamic|\.got|\.data|\.bss'
```

这些 Section 是否存在，以及它们如何分组，都可能因平台和链接器版本而异。

## 13.2 检查动态绑定标志

执行：

```bash
readelf -dW partial-relro
```

以及：

```bash
readelf -dW full-relro
```

搜索：

```bash
readelf -dW full-relro | \
grep -E 'BIND_NOW|FLAGS.*NOW|FLAGS_1.*NOW'
```

在常见的 GNU/Linux 环境中，完整 RELRO 版本通常会显示与立即绑定相关的动态标志。

部分 RELRO 版本则通常仍然允许延迟绑定。

## 13.3 建立区别

| 特性 | 部分 RELRO | 完整 RELRO |
|---|---|---|
| `PT_GNU_RELRO` | 通常存在 | 通常存在 |
| 启用 RELRO | 是 | 是 |
| `-z now` | 未显式启用 | 启用 |
| 动态符号绑定 | 可以延迟 | 启动时完成 |
| 传统 PLT GOT 延迟绑定所需的可写区域 | 可能保留 | 通常可以进一步保护 |

这里的“部分 RELRO”和“完整 RELRO”是常见 GNU/Linux 安全分析术语。

不要只凭文件名判断。应以 `readelf -lW`、`readelf -dW` 的实际输出为准。

---

# 十四、实验 40-9：使用 `objdump` 验证

前面主要使用 `readelf`，现在切换到 `objdump`。

## 14.1 检查 Section

```bash
objdump -h partial-relro
objdump -h full-relro
objdump -h no-relro
```

重点观察：

```text
Size
VMA
LMA
File off
Algn
```

这一组字段可以帮助你分析 Section 的地址、大小与文件位置。

## 14.2 检查 Program Header

```bash
objdump -p partial-relro
objdump -p full-relro
objdump -p no-relro
```

查找：

```text
LOAD
GNU_RELRO
```

不同版本的 `objdump` 对输出格式的展示可能略有区别。

如果你需要精确查看 ELF Program Header 的 `p_offset`、`p_vaddr`、`p_filesz`、`p_memsz` 和 `p_align`，仍然建议以：

```bash
readelf -lW full-relro
```

为主。

---

# 十五、实验 40-10：Map 文件分析

这次我们有三个 Map 文件：

```text
partial-relro.map
full-relro.map
no-relro.map
```

首先搜索与数据段有关的 Section：

```bash
grep -nE \
'\.data\.rel\.ro|\.dynamic|\.got|\.got\.plt|\.data|\.bss' \
full-relro.map
```

再查看完整上下文：

```bash
grep -n -A20 -B10 \
'\.data.rel.ro' \
full-relro.map
```

如果没有找到 `.data.rel.ro`，先不要急着认定失败。某些目标平台可能采用不同的 Section 名称，也可能将对应内容合并到其他 Section 中。

## 15.1 Map 文件能证明什么？

Map 文件可以帮助你分析：

- Section 的起始地址。
- Section 的大小。
- 输入目标文件对输出 Section 的贡献。
- 部分符号的最终地址。
- 链接器如何排列各个输出 Section。

但它不能代替 Program Header 检查。

例如，Map 中出现：

```text
.data.rel.ro
```

并不能单独证明它一定会被动态链接器设置成只读。

要证明它是否落入 `PT_GNU_RELRO` 的范围，还需要检查：

```bash
readelf -lW full-relro
```

然后将 `GNU_RELRO` 的地址范围与对应 Section 的地址范围进行比较。

**这就是本节的关键方法：Map 负责解释 Section 布局，`readelf -lW` 负责验证 Segment 边界。**

---

# 十六、实验 40-11：把三个实验结果自动整理出来

可以使用下面这组命令生成对照报告：

```bash
for f in no-relro partial-relro full-relro
do
    echo
    echo "========== $f =========="

    echo "--- ELF Type ---"
    readelf -hW "$f" | grep -E 'Class:|Type:|Machine:'

    echo "--- RELRO Program Header ---"
    readelf -lW "$f" | grep -E 'GNU_RELRO|LOAD'

    echo "--- Dynamic Binding ---"
    readelf -dW "$f" 2>/dev/null | \
        grep -E 'BIND_NOW|FLAGS.*NOW|FLAGS_1.*NOW' || true

    echo "--- Relevant Sections ---"
    readelf -SW "$f" | \
        grep -E '\.data\.rel\.ro|\.dynamic|\.got|\.got\.plt|\.data|\.bss' || true
done
```

这段脚本不会修改 ELF 文件，只是将三个版本的关键字段集中输出，方便比较。

执行完之后，你应该能够直接回答：

1. 哪个版本存在 `PT_GNU_RELRO`？
2. 哪个版本启用了立即绑定？
3. `.data.rel.ro` 是否存在？
4. 相关 Section 是否位于 RELRO 覆盖的地址范围内？
5. 三个版本的 Segment 地址和大小是否相同？

---

# 十七、实验 40-12：进一步观察默认脚本的页面大小策略

回到实验 39。

当时我们研究了：

```ld
ALIGN(CONSTANT (MAXPAGESIZE))
```

以及：

```bash
-z max-page-size=0x1000
```

本节要把它们与 `DATA_SEGMENT_ALIGN()` 联系起来。

在当前默认脚本中查找：

```bash
grep -nE \
'MAXPAGESIZE|COMMONPAGESIZE|DATA_SEGMENT_ALIGN' \
default-linker.ld
```

你应该重点理解下面这组关系：

```text
MAXPAGESIZE
      │
      ├── 最大页面大小相关约束
      │
COMMONPAGESIZE
      │
      └── 常见页面大小相关约束
                 │
                 ▼
       DATA_SEGMENT_ALIGN()
                 │
                 ▼
       数据段起始位置的计算
                 │
                 ▼
       文件空间与运行时页面的布局权衡
```

`DATA_SEGMENT_ALIGN()` 并不是简单地将当前位置向上取整到某个固定地址。GNU ld 文档说明，它会根据两个页面大小参数选择布局表达式，以权衡运行时内存占用和文件填充。[Sourceware](https://sourceware.org/binutils/docs/ld.html?utm_source=chatgpt.com)

因此，不应该预先断言：

```text
指定 -z max-page-size=0x1000
```

就一定让所有 Segment 的 `p_align` 变成 `0x1000`，或者一定让 ELF 文件缩小到某个固定值。

正确做法仍然是：

```bash
readelf -lW full-relro
objdump -h full-relro
```

再根据实际输出判断。

---

# 十八、一个重要的工程边界：不要把主机默认脚本直接搬到裸机固件

这里需要特别提醒。

本节研究的：

```ld
DATA_SEGMENT_ALIGN()
DATA_SEGMENT_RELRO_END()
DATA_SEGMENT_END()
```

主要针对 GNU ld 在常见主机 ELF 数据段布局中的使用场景。

而你前面实验 38、39 使用的：

```ld
MEMORY
{
    FLASH (rx) : ORIGIN = 0x00400000, LENGTH = 64K
    SRAM  (rw) : ORIGIN = 0x00600000, LENGTH = 64K
}
```

属于另一类布局模型。

裸机固件更关心：

```text
FLASH
├── .text
├── .rodata
└── .data 初始化镜像

SRAM
├── .data 运行区
├── .bss
└── stack
```

通常使用：

```ld
.data > SRAM AT > FLASH
```

再配合：

```ld
LOADADDR(.data)
ADDR(.data)
SIZEOF(.data)
```

生成启动代码所需的地址与大小。

而主机动态链接程序的 RELRO 机制，还涉及：

- 动态重定位。
- 动态链接器。
- GOT/PLT。
- `PT_GNU_RELRO`。
- 运行时内存权限调整。

两种场景都属于 GNU ld，但解决的问题不同。

**不要因为默认主机脚本中出现了 `DATA_SEGMENT_ALIGN()`，就把它直接塞进前面那个自定义 FLASH/SRAM 固件脚本。**

先明确程序类型，再选择对应的布局机制。

---

# 十九、实验 40 的最终知识地图

现在把本节涉及的内容串起来：

```text
                     GNU ld
                       │
                       ▼
                默认 linker script
                       │
          ┌────────────┼─────────────┐
          │            │             │
          ▼            ▼             ▼
 DATA_SEGMENT_ALIGN  RELRO 布局  DATA_SEGMENT_END
          │            │             │
          │            ▼             │
          │       DATA_SEGMENT_       │
          │       RELRO_END           │
          │            │             │
          └────────────┼─────────────┘
                       ▼
                  ELF Section
                       │
                       ▼
                 PT_LOAD Segment
                       │
              ┌────────┴────────┐
              │                 │
              ▼                 ▼
          PT_GNU_RELRO       普通可写区域
              │                 │
              ▼                 ▼
         重定位后保护       保持可写
```

注意：图中展示的是概念关系，不意味着所有平台的默认脚本都具有完全相同的 Section 顺序。

---

# 二十、实验 40 的验收清单

完成本节时，请确保自己能够独立完成下面这些操作。

### 源码与编译

- [ ] 编写 `relro_demo.c`。
- [ ] 使用 `gcc -fPIE -c` 生成目标文件。
- [ ] 用 `readelf -SW` 检查输入 Section。
- [ ] 用 `readelf -rW` 查看输入重定位。

### 链接

- [ ] 构建 `no-relro`。
- [ ] 构建 `partial-relro`。
- [ ] 构建 `full-relro`。
- [ ] 为三个版本生成独立 Map 文件。

### ELF 验证

- [ ] 使用 `readelf -hW` 检查 ELF 类型。
- [ ] 使用 `readelf -SW` 检查 Section。
- [ ] 使用 `readelf -lW` 检查 `PT_GNU_RELRO`。
- [ ] 使用 `readelf -dW` 检查立即绑定标志。
- [ ] 使用 `objdump -h` 检查 Section 地址和文件偏移。
- [ ] 使用 `objdump -p` 交叉验证 Program Header。

### 默认脚本分析

- [ ] 通过 `ld --verbose` 找到默认 linker script。
- [ ] 找到 `DATA_SEGMENT_ALIGN()`。
- [ ] 找到 `DATA_SEGMENT_RELRO_END()`。
- [ ] 找到 `DATA_SEGMENT_END()`。
- [ ] 理解三个表达式之间的位置约束。

### Map 文件分析

- [ ] 定位 `.data.rel.ro` 或目标平台对应的 Section。
- [ ] 记录它的地址与大小。
- [ ] 将它与 `PT_GNU_RELRO` 的范围进行比较。
- [ ] 解释为什么 Map 文件本身不足以证明运行时只读保护已经生效。

---

# 二十一、下一节：实验 41

下一节继续沿着这条路线，进入：

## 实验 41 —— `OVERLAY` + `NOCROSSREFS` + `NOCROSSREFS_TO()` + `ASSERT()` 综合约束

前面已经学过：

- `ASSERT()`。
- `NOCROSSREFS()`。
- `NOCROSSREFS_TO()`。
- Section 布局与 Segment 布局。
- VMA/LMA。
- `PHDRS`。
- Map 文件分析。

下一节将把这些知识放进一个更接近实际工程的场景：

**多个功能模块共享同一块 RAM，通过 `OVERLAY` 复用运行时内存，同时使用链接期约束阻止模块之间产生不允许的符号引用。**

我们会逐步完成：

1. 设计多个输入 Section。
2. 使用 `OVERLAY` 安排共享内存。
3. 使用 `AT()` 或其他适当的加载地址布局方式。
4. 使用 `NOCROSSREFS()` 检查模块之间的引用。
5. 使用 `NOCROSSREFS_TO()` 精确限制引用方向。
6. 使用 `ASSERT()` 检查 Overlay 的大小和内存边界。
7. 使用 `readelf -SW`、`objdump -h`、`nm -n` 和 Map 文件验证最终布局。

这将是一次真正的综合实验：不只是让链接成功，而是让链接器替我们检查内存规划和模块依赖规则。

I noticed you haven’t viewed this scheduled task in a while. Would you like me to keep it running?
