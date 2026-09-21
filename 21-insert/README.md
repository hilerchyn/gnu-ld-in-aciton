# GNU ld 实战课程 · 实验 21

## `INSERT BEFORE / INSERT AFTER`：不重写默认 linker script，给现有布局“打补丁”

上一节我们刚刚解决了 **Orphan Sections**：

```text
Input Section
    ↓
linker script 没有匹配
    ↓
Orphan
    ↓
ld 自动放置
```

这一节进入一个非常实用的工程技巧：

> **我已经有一套成熟的默认 linker script，只想增加一个 Section，为什么还要把几百行默认脚本全部复制出来？**

答案就是：

```ld
INSERT BEFORE
INSERT AFTER
```

它们允许我们：

```text
系统默认 linker script
        │
        ├── .text
        ├── .rodata
        ├── .data
        ├── .bss
        └── ...
               ↑
          插入自己的 Section
```

而不是：

```text
复制 500+ 行默认脚本
        ↓
自己维护
        ↓
工具链升级
        ↓
默认脚本变化
        ↓
你的副本过期
```

---

# 一、今天的实验路线

```text
实验 21-1
查看系统默认 linker script

实验 21-2
只增加一个自定义 Section

实验 21-3
INSERT AFTER .text

实验 21-4
INSERT BEFORE .data

实验 21-5
比较 INSERT 与普通 linker script

实验 21-6
INSERT + KEEP + --gc-sections

实验 21-7
INSERT + PROVIDE

实验 21-8
INSERT + ASSERT

实验 21-9
Map 文件分析

实验 21-10
readelf / objdump / nm 全验证

实验 21-11
为什么生产工程不应该轻易复制默认 linker script
```

---

# 二、实验 21-1：先看看你的默认 linker script

先执行：

```bash
ld --verbose
```

你会看到类似：

```text
GNU ld ...
...
==================================================
OUTPUT_FORMAT(...)
OUTPUT_ARCH(...)
ENTRY(...)
SEARCH_DIR(...)
...
SECTIONS
{
    ...
}
```

注意：

```bash
ld --verbose
```

输出里包含两部分：

```text
GNU ld 的信息
        +
默认 linker script
```

---

# 三、只看默认脚本

可以：

```bash
ld --verbose \
    | sed -n '/^=========/,/^=========/p'
```

不同 binutils 版本输出边界可能略有区别，所以更可靠的方法是直接：

```bash
ld --verbose > default-ld.txt
```

然后：

```bash
less default-ld.txt
```

搜索：

```text
SECTIONS
```

你会发现默认脚本非常庞大。

通常会包含类似：

```ld
SECTIONS
{
    .interp : { *(.interp) }

    .note.gnu.build-id : { *(.note.gnu.build-id) }

    .hash : { *(.hash) }

    .gnu.hash : { *(.gnu.hash) }

    .dynsym : { *(.dynsym) }

    ...

    .init :
    {
        KEEP (*(SORT_NONE(.init)))
    }

    .plt :
    {
        *(.plt)
    }

    .text :
    {
        *(.text .stub .text.* .gnu.linkonce.t.*)
        ...
    }

    .fini :
    {
        KEEP (*(SORT_NONE(.fini)))
    }

    .rodata :
    {
        ...
    }

    .data :
    {
        ...
    }

    .bss :
    {
        ...
    }
}
```

这里第一次真正体会：

> **默认 linker script 其实是一整套复杂的 ELF 布局策略。**

所以一般不要为了增加一个 section 就复制它。

---

# 四、实验 21-2：我们只增加一个 `.my_metadata`

建立：

```text
lab21/
├── main.c
├── metadata.c
├── start.S
└── insert.ld
```

`metadata.c`：

```c
#include <stdint.h>

__attribute__((section(".my_metadata")))
const uint32_t metadata[] =
{
    0x12345678,
    0xAABBCCDD,
    0x55667788,
    0xDEADBEEF
};
```

这里：

```text
metadata.c
       ↓
metadata.o
       ↓
.my_metadata
```

---

# 五、编译

```bash
gcc \
    -ffreestanding \
    -fno-pie \
    -fno-stack-protector \
    -fdata-sections \
    -c metadata.c \
    -o metadata.o
```

检查：

```bash
objdump -h metadata.o
```

应该看到：

```text
.my_metadata
```

进一步：

```bash
objdump -s \
    --section=.my_metadata \
    metadata.o
```

应该能看到：

```text
78 56 34 12
dd cc bb aa
...
```

因为 x86 通常是小端。

---

# 六、实验 21-3：最简单的 `INSERT AFTER`

现在 `insert.ld` 只写：

```ld
SECTIONS
{
    .my_metadata :
    {
        KEEP(*(.my_metadata))
    }
}
INSERT AFTER .text;
```

注意：

> 这里并没有重新定义 `.text`。

只定义：

```text
.my_metadata
```

然后告诉 ld：

```text
把这个 Output Section
插入到默认 .text 后面。
```

这就是：

# `INSERT AFTER .text`

---

# 七、准备最小程序

`main.c`：

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

`start.S`：

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

# 八、链接

这里有一个重要变化：

以前：

```bash
ld -T linker.ld ...
```

现在：

```bash
ld \
    -T insert.ld \
    start.o \
    main.o \
    metadata.o \
    -o insert01.elf \
    -Map=insert01.map
```

ld 会：

```text
默认 linker script
        +
insert.ld
        ↓
最终布局
```

而不是：

```text
insert.ld
 ↓
完全替代默认脚本
```

---

# 九、验证 Section

```bash
readelf -S insert01.elf
```

搜索：

```bash
readelf -S insert01.elf | grep -E '\.text|\.my_metadata|\.rodata'
```

你应该看到类似：

```text
.text
.my_metadata
.rodata
```

具体顺序会受到当前 binutils 默认脚本影响，但关键是：

```text
.my_metadata
```

已经被插入到了：

```text
.text
```

之后。

---

# 十、Map 文件才是这里的核心

打开：

```bash
less insert01.map
```

找到：

```text
.my_metadata
```

应该能看到类似：

```text
.my_metadata    0x000000000040....
                0x000000000040.... metadata.o
```

再找到：

```text
.text
```

比较两者地址：

```text
.text
    ↓
.my_metadata
    ↓
.rodata
```

这就是：

```text
INSERT AFTER .text
```

真正发生的结果。

---

# 十一、实验 21-4：改成 `INSERT BEFORE .data`

现在把：

```ld
INSERT AFTER .text;
```

改成：

```ld
INSERT BEFORE .data;
```

完整：

```ld
SECTIONS
{
    .my_metadata :
    {
        KEEP(*(.my_metadata))
    }
}
INSERT BEFORE .data;
```

重新：

```bash
ld \
    -T insert.ld \
    start.o \
    main.o \
    metadata.o \
    -o insert02.elf \
    -Map=insert02.map
```

检查：

```bash
readelf -S insert02.elf
```

然后：

```bash
grep -A 10 -B 10 "\.my_metadata" insert02.map
```

你应该看到：

```text
...
.rodata
.my_metadata
.data
...
```

也就是说：

```text
INSERT BEFORE .data
```

让：

```text
.my_metadata
```

成为：

```text
.rodata
        ↓
.my_metadata
        ↓
.data
```

之间的 Section。

---

# 十二、为什么这比复制默认 linker script 好？

假设默认 linker script 有：

```text
.text
.fini
.rodata
.eh_frame
...
.data
...
.bss
...
```

你只需要：

```ld
SECTIONS
{
    .my_metadata :
    {
        KEEP(*(.my_metadata))
    }
}
INSERT BEFORE .data;
```

而不需要：

```text
复制几百行默认脚本
```

所以：

```text
系统默认规则
      +
你的局部修改
      =
最终 linker script
```

这是 `INSERT` 最大的工程价值。

---

# 十三、实验 21-5：理解 `INSERT` 与普通 `-T` 的区别

这里特别容易混淆。

## 普通 linker script

例如：

```ld
SECTIONS
{
    .text :
    {
        *(.text)
    }

    .data :
    {
        *(.data)
    }
}
```

然后：

```bash
ld -T linker.ld ...
```

意思基本是：

> **用这个脚本作为主要布局规则。**

---

## `INSERT`

```ld
SECTIONS
{
    .my_metadata :
    {
        *(.my_metadata)
    }
}

INSERT AFTER .text;
```

意思：

> **在默认脚本基础上增加一个 Output Section，并把它插到指定位置。**

这两个思维模型必须分开。

---

# 十四、实验 21-6：`INSERT + KEEP + --gc-sections`

现在让实验更真实。

我们的：

```text
.my_metadata
```

没有被任何 C 代码引用。

如果打开：

```bash
--gc-sections
```

它可能被删除。

所以：

```ld
.my_metadata :
{
    KEEP(*(.my_metadata))
}
INSERT AFTER .text;
```

非常合适。

链接：

```bash
ld \
    --gc-sections \
    -T insert.ld \
    start.o \
    main.o \
    metadata.o \
    -o insert-gc.elf \
    -Map=insert-gc.map
```

然后：

```bash
readelf -S insert-gc.elf | grep my_metadata
```

应该仍然存在。

---

# 十五、去掉 `KEEP()` 再试一次

把：

```ld
.my_metadata :
{
    KEEP(*(.my_metadata))
}
```

改成：

```ld
.my_metadata :
{
    *(.my_metadata)
}
```

重新：

```bash
ld \
    --gc-sections \
    -T insert.ld \
    start.o \
    main.o \
    metadata.o \
    -o insert-gc-no-keep.elf \
    -Map=insert-gc-no-keep.map
```

然后：

```bash
readelf -S insert-gc-no-keep.elf | grep my_metadata
```

如果它消失了，再看：

```bash
grep -n "Discarded input sections" insert-gc-no-keep.map
```

你会看到 `.my_metadata` 相关输入 section 被回收。

于是完整关系就是：

```text
INSERT
    ↓
决定放哪里

KEEP
    ↓
决定 GC 时是否允许删除
```

两者完全不同。

---

# 十六、实验 21-7：让程序引用 metadata

修改 `main.c`：

```c
extern const unsigned int metadata[];

int main(void)
{
    return metadata[0] != 0x12345678;
}
```

编译：

```bash
gcc \
    -ffreestanding \
    -fno-pie \
    -fno-stack-protector \
    -ffunction-sections \
    -fdata-sections \
    -c main.c \
    -o main.o
```

现在即使：

```ld
*(".my_metadata")
```

没有 `KEEP()`：

```text
main
 ↓
metadata
 ↓
relocation
 ↓
.my_metadata
```

形成了引用链。

所以：

```text
GC
 ↓
发现被引用
 ↓
保留
```

这是一个非常重要的对比实验：

```text
KEEP 保留
```

与：

```text
引用链保留
```

是两种不同机制。

---

# 十七、实验 21-8：`INSERT` + `PROVIDE`

上一节我们学习：

```ld
PROVIDE()
```

现在组合起来。

修改：

```ld
SECTIONS
{
    .my_metadata :
    {
        __metadata_start = .;

        KEEP(*(.my_metadata))

        __metadata_end = .;
    }
}

INSERT AFTER .text;

PROVIDE(__metadata_size =
    __metadata_end - __metadata_start);
```

现在：

```text
.my_metadata
    │
    ├── __metadata_start
    │
    ├── data
    │
    └── __metadata_end
```

然后：

```text
__metadata_size
=
end - start
```

---

# 十八、链接

```bash
ld \
    -T insert.ld \
    start.o \
    main.o \
    metadata.o \
    -o insert-symbol.elf \
    -Map=insert-symbol.map
```

查看：

```bash
nm -n insert-symbol.elf | grep metadata
```

可能看到：

```text
__metadata_start
__metadata_end
__metadata_size
metadata
```

注意：

如果你把：

```ld
PROVIDE(__metadata_size = ...)
```

写成 `PROVIDE()`，而没有任何地方引用：

```text
__metadata_size
```

它可能不会像普通符号那样出现在最终符号表。

这正好复习了上一节的实验。

---

# 十九、实验 21-9：用 `ASSERT()` 检查 metadata

假设我们规定：

```text
metadata 最大 4 KB
```

那么：

```ld
ASSERT(
    (__metadata_end - __metadata_start) <= 4K,
    "ERROR: metadata too large"
);
```

完整：

```ld
SECTIONS
{
    .my_metadata :
    {
        __metadata_start = .;

        KEEP(*(.my_metadata))

        __metadata_end = .;
    }
}

INSERT AFTER .text;

ASSERT(
    (__metadata_end - __metadata_start) <= 4K,
    "ERROR: metadata too large"
);
```

现在：

```text
编译期
    ↓
linker
    ↓
计算 Section Size
    ↓
ASSERT
    ↓
超过 4K？
    ↓
ERROR
```

这就是我们前面学习的：

```text
PROVIDE
+
ASSERT
+
INSERT
```

第一次真正组合起来。

---

# 二十、实验 21-10：故意让 metadata 超过 4 KB

修改：

```c
const uint8_t metadata[8192]
    __attribute__((section(".my_metadata")));
```

例如：

```c
#include <stdint.h>

__attribute__((section(".my_metadata")))
const uint8_t metadata[8192] = { 0 };
```

重新编译：

```bash
gcc \
    -ffreestanding \
    -fno-pie \
    -fno-stack-protector \
    -fdata-sections \
    -c metadata.c \
    -o metadata.o
```

重新链接：

```bash
ld \
    -T insert.ld \
    start.o \
    main.o \
    metadata.o \
    -o insert-assert.elf \
    -Map=insert-assert.map
```

应该得到：

```text
ld: ERROR: metadata too large
```

这里特别值得注意：

> 这个错误不是 GCC 报的，而是 linker script 主动制造的。

所以现在 linker script 已经具备：

```text
布局
+
配置
+
验证
```

三种能力。

---

# 二十一、实验 21-11：Map 文件分析

打开：

```bash
less insert-symbol.map
```

你需要重点观察三个位置。

### 第一处：`.text`

```text
.text
...
```

### 第二处：`.my_metadata`

```text
.my_metadata
...
```

### 第三处：`.rodata`

```text
.rodata
...
```

确认：

```text
.text
    ↓
.my_metadata
    ↓
.rodata
```

或者如果使用：

```ld
INSERT BEFORE .data;
```

则：

```text
.rodata
    ↓
.my_metadata
    ↓
.data
```

---

# 二十二、不要只看 Section 名称

Map 文件中最好进一步找到：

```text
__metadata_start
__metadata_end
```

例如：

```text
.my_metadata
    0x00401200
    __metadata_start = .

    metadata.o(.my_metadata)

    0x00401210
    __metadata_end = .
```

于是：

```text
size
=
0x00401210
-
0x00401200
=
0x10
```

然后用：

```bash
nm -n insert-symbol.elf
```

再次验证。

---

# 二十三、`readelf -S` 验证最终 Section

```bash
readelf -S insert-symbol.elf
```

关注：

```text
.my_metadata
```

检查：

```text
Address
Offset
Size
Flags
Link
Info
Align
```

尤其是：

```text
Address
Size
Flags
Align
```

---

# 二十四、`objdump -h` 验证布局

```bash
objdump -h insert-symbol.elf
```

重点比较：

```text
.text
.my_metadata
.rodata
```

的：

```text
VMA
LMA
Size
Align
```

---

# 二十五、`objdump -s` 验证实际内容

```bash
objdump \
    -s \
    --section=.my_metadata \
    insert-symbol.elf
```

应该看到：

```text
78 56 34 12
dd cc bb aa
...
```

这样就完成了：

```text
C
 ↓
Input Section
 ↓
ld
 ↓
Output Section
 ↓
ELF
 ↓
实际字节
```

完整闭环。

---

# 二十六、`readelf -l`：不要忘记 Segment

执行：

```bash
readelf -l insert-symbol.elf
```

检查：

```text
.my_metadata
```

进入哪个：

```text
PT_LOAD
```

特别注意：

```text
Section to Segment mapping
```

找到：

```text
.my_metadata
```

看它属于：

```text
R E
```

还是：

```text
RW
```

这一步非常重要。

因为：

```text
INSERT AFTER .text
```

不仅决定 Section 在 Section Header Table 中的位置。

它还可能影响：

```text
Segment
File Offset
Virtual Address
Memory permissions
```

---

# 二十七、一个非常值得做的实验

把：

```ld
INSERT AFTER .text;
```

改成：

```ld
INSERT BEFORE .data;
```

然后比较：

```bash
readelf -l insert-after.elf
readelf -l insert-before.elf
```

同时：

```bash
objdump -h insert-after.elf
objdump -h insert-before.elf
```

你会发现：

> **Section 位置变化可能进一步影响 Segment 布局。**

这正是：

```text
Section
    ↓
Segment
```

关系的实际体现。

---

# 二十八、实验 21-12：为什么不应该直接复制 `ld --verbose`

假设你运行：

```bash
ld --verbose > default.ld
```

然后把其中：

```text
SECTIONS
{
    ...
}
```

复制出来修改。

短期看：

```text
可以工作
```

长期可能出现：

```text
Binutils 版本升级
       ↓
默认 linker script 改变
       ↓
你的 default.ld 不会自动改变
       ↓
布局差异
       ↓
ELF 差异
       ↓
潜在运行时问题
```

而使用：

```ld
INSERT AFTER
INSERT BEFORE
```

则：

```text
系统默认 linker script
        +
你的增量规则
```

天然跟随默认脚本的其它变化。

---

# 二十九、一个很典型的真实场景

假设系统默认 linker script 中有：

```text
.text
.fini
.rodata
.eh_frame
.sdata
.data
.bss
```

你需要增加：

```text
.firmware_info
```

并且要求：

```text
.firmware_info
```

位于：

```text
.text
```

之后。

你完全不需要复制默认脚本。

只需要：

```ld
SECTIONS
{
    .firmware_info :
    {
        __firmware_info_start = .;

        KEEP(*(.firmware_info))

        __firmware_info_end = .;
    }
}

INSERT AFTER .text;
```

这就是非常典型的：

# 增量式 linker script。

---

# 三十、实验 21-13：制作真正的 Firmware Metadata

我们把刚才的实验进一步工程化。

`metadata.c`：

```c
#include <stdint.h>

struct firmware_info
{
    uint32_t magic;
    uint32_t version;
    uint32_t build_id;
    uint32_t image_size;
};

__attribute__((section(".firmware_info")))
const struct firmware_info firmware_info =
{
    .magic = 0x46574D47,
    .version = 0x00010000,
    .build_id = 0x20260920,
    .image_size = 0
};
```

这里：

```text
0x46574D47
```

可以理解成：

```text
"FWMG"
```

---

# 三十一、linker script

```ld
SECTIONS
{
    .firmware_info :
    {
        __firmware_info_start = .;

        KEEP(*(.firmware_info))

        __firmware_info_end = .;
    }
}

INSERT AFTER .text;

ASSERT(
    SIZEOF(.firmware_info) == 16,
    "ERROR: invalid firmware info size"
);
```

现在 linker 负责保证：

```text
firmware_info
必须是 16 字节。
```

---

# 三十二、编译与链接

```bash
gcc \
    -ffreestanding \
    -fno-pie \
    -fno-stack-protector \
    -fdata-sections \
    -c metadata.c \
    -o metadata.o
```

然后：

```bash
ld \
    -T insert.ld \
    start.o \
    main.o \
    metadata.o \
    -o firmware.elf \
    -Map=firmware.map
```

---

# 三十三、验证 Metadata

```bash
readelf -S firmware.elf
```

找到：

```text
.firmware_info
```

然后：

```bash
objdump \
    -s \
    --section=.firmware_info \
    firmware.elf
```

应该看到：

```text
47 4D 57 46
00 00 01 00
...
```

注意小端序。

---

# 三十四、用 `nm` 验证边界

```bash
nm -n firmware.elf | grep firmware_info
```

你应该能看到：

```text
__firmware_info_start
firmware_info
__firmware_info_end
```

然后：

```text
end - start
=
16
```

与：

```ld
ASSERT(
    SIZEOF(.firmware_info) == 16,
    ...
);
```

完全对应。

---

# 三十五、这一刻其实已经出现一个很完整的固件设计模式

```text
metadata.c
    ↓
.firmware_info
    ↓
INSERT AFTER .text
    ↓
KEEP()
    ↓
__firmware_info_start
    ↓
firmware_info
    ↓
__firmware_info_end
    ↓
SIZEOF()
    ↓
ASSERT()
```

也就是说：

# C 定义内容，ld 定义位置和边界。

这是非常重要的职责划分。

---

# 三十六、实验 21-14：让启动代码读取 Metadata

`start.S`：

```asm
.global _start

.extern __firmware_info_start
.extern __firmware_info_end

.text

_start:
    lea __firmware_info_start(%rip), %rax
    lea __firmware_info_end(%rip), %rbx

    call main

    hlt
```

这样：

```text
_start
 ↓
linker symbol
 ↓
.firmware_info
```

建立了明确的链接关系。

然后：

```bash
objdump -d firmware.elf
```

观察：

```text
lea ...
```

使用的地址。

---

# 三十七、实验 21-15：用 Map 反向推导整个 Firmware

现在打开：

```bash
less firmware.map
```

按照下面顺序分析：

### ① `.text`

```text
.text
```

### ② `.firmware_info`

```text
.firmware_info
```

### ③ `.rodata`

```text
.rodata
```

### ④ `.data`

```text
.data
```

### ⑤ `.bss`

```text
.bss
```

然后建立：

```text
ROM
│
├── .text
│
├── .firmware_info
│
├── .rodata
│
└── ...
```

这时候你已经可以从 Map 文件**重建 ELF 的主要布局**。

---

# 三十八、实验 21-16：最终验证矩阵

这一节建议固定执行以下命令。

## ① 看 Input Section

```bash
objdump -h metadata.o
```

---

## ② 看最终 Section

```bash
readelf -S firmware.elf
```

---

## ③ 看 Section 地址和大小

```bash
objdump -h firmware.elf
```

---

## ④ 看 Section 内容

```bash
objdump -s \
    --section=.firmware_info \
    firmware.elf
```

---

## ⑤ 看符号

```bash
nm -n firmware.elf
```

---

## ⑥ 看 Segment

```bash
readelf -l firmware.elf
```

---

## ⑦ 看最终布局原因

```bash
less firmware.map
```

这七步形成：

```text
Input
 ↓
Section
 ↓
Symbol
 ↓
Segment
 ↓
实际数据
 ↓
Map
```

---

# 三十九、今天三个关键字的职责

现在把：

```text
INSERT
KEEP
ASSERT
```

放在一起。

### `INSERT`

解决：

> **放在哪里？**

```ld
INSERT AFTER .text;
```

---

### `KEEP`

解决：

> **GC 时能不能删？**

```ld
KEEP(*(.firmware_info))
```

---

### `ASSERT`

解决：

> **最终布局是否合法？**

```ld
ASSERT(
    SIZEOF(.firmware_info) == 16,
    "ERROR"
);
```

所以：

```text
        Section
           │
      ┌────┼────┐
      │    │    │
   INSERT KEEP ASSERT
      │    │    │
      ▼    ▼    ▼
     位置  保留  校验
```

---

# 四十、今天还有一个特别重要的认识

我们现在可以把 linker script 分成两种：

## 第一种：完整布局型

```text
-T linker.ld
```

你自己控制：

```text
.text
.rodata
.data
.bss
...
```

适合：

```text
MCU
Bare Metal
Bootloader
固定内存布局
```

---

## 第二种：增量修改型

```text
默认 linker script
        +
INSERT
```

适合：

```text
Linux 用户程序
共享库
GCC 默认 ELF 布局
只需要增加少量自定义 Section
```

这两种方式没有谁绝对更好。

关键是：

> **你的工程到底需要控制整个内存布局，还是只需要修改默认布局的一小部分。**

---

# 四十一、实验 21 最终知识图

```text
                    GCC
                     │
                     ▼
                metadata.o
                     │
                     ▼
              .firmware_info
                     │
                     ▼
              ┌──────────────┐
              │ linker script│
              │              │
              │  INSERT      │
              │  KEEP        │
              │  PROVIDE     │
              │  ASSERT      │
              └──────┬───────┘
                     │
                     ▼
             Default ld script
                     │
                     ▼
                    ELF
          ┌──────────┼──────────┐
          ▼          ▼          ▼
      readelf     objdump      nm
          │          │          │
          └──────────┼──────────┘
                     ▼
                   MAP
```

---

# 四十二、现在 GNU ld 主线推进到这里

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
Orphan Sections
        ↓
实验 21
INSERT BEFORE / AFTER
```

下一步进入：

# 实验 22：`SUBALIGN()` / `ALIGN_WITH_INPUT()` / `ALIGN()` —— 真正搞懂 Section 对齐、padding，以及“为什么地址突然多出一大块空洞”

这一节会重点解决我们之前实验里经常碰到的一个问题：

```text
.text
0x400000
size = 0x2d

下一段为什么不是：
0x40002d

而是：
0x401000？
```

我们会制造：

```text
.text.foo      align=1
.text.bar      align=16
.text.vector   align=4096
```

然后分别实验：

```ld
ALIGN()
SUBALIGN()
ALIGN_WITH_INPUT()
```

再用：

```bash
readelf -S
objdump -h
objdump -s
readelf -l
```

以及 Map 文件中的：

```text
*fill*
```

把 linker 为了满足 alignment 插入的 padding **一字节一字节找出来**。

这会把你之前碰到的：

```text
ALIGN() 写法
.text ALIGN(16) :
```

与正确的：

```ld
.text : ALIGN(16)
```

以及：

```ld
. = ALIGN(16);
```

彻底区分开。

