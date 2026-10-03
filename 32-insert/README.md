# GNU ld 实战课程 · 实验 32

# `INSERT BEFORE / INSERT AFTER`：不重写默认 linker script，给系统链接脚本“打补丁”

上一节实验 31 我们完成了：

```text
OVERLAY
    ↓
VMA / LMA
    ↓
AT()
    ↓
LOADADDR()
    ↓
__load_start_xxx / __load_stop_xxx
    ↓
NOCROSSREFS
    ↓
Overlay Manager
```

这一节进入一个非常实用的能力：

> **在保留 GNU ld 默认 linker script 的情况下，只向默认布局中插入自己的 Section。**

这在真实工程里非常重要。

例如你可能只想增加：

```text
.firmware_header
.gcov_info
.my_metadata
.build_info
.version
.factory_config
```

而完全不想复制几百行默认 linker script。

GNU ld 当前文档明确说明，`INSERT BEFORE` / `INSERT AFTER` 可以把自定义脚本中的 Section 插入默认 `SECTIONS`，同时不会让 `-T` 完全覆盖默认 linker script。([Sourceware][1])

---

# 一、先理解一个非常重要的区别

以前我们一直这样：

```bash
ld -T linker.ld ...
```

如果 `linker.ld` 自己定义：

```ld
SECTIONS
{
    .text : ...
    .rodata : ...
    .data : ...
    .bss : ...
}
```

那么你实际上是在：

> **接管整个 Section 布局。**

而这一次我们希望：

```text
系统默认 linker script
        │
        ├── .interp
        ├── .text
        ├── .rodata
        ├── .eh_frame
        ├── .data
        ├── .bss
        └── ...
              ↑
              │
       我只插入一个
       .firmware_header
```

即：

```text
默认布局
+
我的 Section
```

而不是：

```text
我的 linker script
替代
默认 linker script
```

---

# 二、实验 32 的完整目标

最终我们希望：

```text
默认 linker script

.text
      ↓
.firmware_header
      ↓
.rodata
      ↓
.eh_frame
      ↓
.data
      ↓
.bss
```

或者：

```text
.text
      ↓
.rodata
      ↓
.firmware_header
      ↓
.eh_frame
```

只需要：

```ld
INSERT BEFORE .text;
```

或者：

```ld
INSERT AFTER .rodata;
```

---

# 三、为什么这节课非常重要？

因为真实项目通常不是：

```text
自己从零设计一个 ELF
```

而是：

```text
GCC
+
glibc
+
crt1.o
+
crti.o
+
crtn.o
+
libgcc
+
libc
+
默认 linker script
```

默认 linker script 可能非常复杂。

例如：

```bash
ld --verbose
```

通常能看到大量内容：

```text
ENTRY(...)
SEARCH_DIR(...)
SECTIONS
{
    PROVIDE (...)
    .interp : ...
    .note.gnu.build-id : ...
    .hash : ...
    .dynsym : ...
    ...
    .init : ...
    .plt : ...
    .text : ...
    .fini : ...
    .rodata : ...
    .eh_frame : ...
    ...
}
```

你不希望为了增加一个 Section：

```text
.firmware_header
```

就把这一大坨复制下来维护。

---

# 四、实验 32-1：获取默认 linker script

先执行：

```bash
ld --verbose
```

这是我们今天非常重要的第一条命令。

你会看到类似：

```text
GNU ld ...
...
==================================================
SECTIONS
{
    ...
}
```

注意：

```text
ld --verbose
```

除了默认 linker script，还会打印一些 ld 信息。

所以不要直接：

```bash
ld --verbose > default.ld
```

然后就拿这个文件去 `-T`。

应该提取真正的 script。

---

# 五、提取默认 linker script

GNU 工具链文档中也使用了这种思路来获得默认 linker script。([Sourceware Snapshots][2])

Linux/GNU 环境可以：

```bash
ld --verbose \
    | sed -n '/^==================================================/,$p' \
    | sed '1d' \
    > default.ld
```

不过不同 binutils 版本的分隔符可能略有差异。

更稳妥的方法：

```bash
ld --verbose
```

然后把：

```text
==================================================
```

之后的：

```ld
SECTIONS
{
    ...
}
```

保存下来。

---

# 六、实验 32-2：先观察默认布局

我们先不要修改任何东西。

准备最简单的：

```text
main.c
```

```c
int global_data = 123;

const char message[] = "hello ld";

int main(void)
{
    return global_data + message[0];
}
```

---

# 七、编译

```bash
gcc \
    -ffunction-sections \
    -fdata-sections \
    -g \
    -c main.c \
    -o main.o
```

然后：

```bash
gcc \
    main.o \
    -Wl,-Map,default.map \
    -o default.elf
```

这里故意使用：

```bash
gcc
```

而不是直接：

```bash
ld
```

原因是这次我们想观察：

> **真实 GCC 默认链接流程。**

GCC 本身会负责调用编译、汇编和链接阶段；`-Wl,` 用于把参数传给 linker。([GCC][3])

---

# 八、实验 32-3：查看默认 Section

执行：

```bash
readelf -SW default.elf
```

重点观察：

```text
.text
.rodata
.eh_frame
.data
.bss
```

再：

```bash
objdump -h default.elf
```

你会看到：

```text
Idx Name          Size      VMA
...
.text
.rodata
.eh_frame
.data
.bss
```

---

# 九、查看默认 Map

```bash
less default.map
```

或者：

```bash
grep -E '^ \.(text|rodata|eh_frame|data|bss)' default.map
```

你现在需要建立一个意识：

> **Map 文件才是研究 linker 实际布局最直接的“施工图”。**

`readelf` 更适合验证最终 ELF。

`objdump` 更适合快速观察 Section。

Map 则告诉你：

```text
谁
→
被放到了哪里
→
占了多少空间
→
为什么在那里
```

---

# 十、实验 32-4：创建 `.firmware_header`

新建：

```text
header.c
```

内容：

```c
#include <stdint.h>

__attribute__((section(".firmware_header")))
const uint8_t firmware_header[] =
{
    0x46, 0x57, 0x48, 0x44,   /* FWHD */
    0x01, 0x00, 0x00, 0x00,   /* version */
    0x12, 0x34, 0x56, 0x78
};
```

这里我们人为创建：

```text
.firmware_header
```

---

# 十一、编译

```bash
gcc \
    -ffunction-sections \
    -fdata-sections \
    -g \
    -c header.c \
    -o header.o
```

先看：

```bash
objdump -h header.o
```

应该出现：

```text
.firmware_header
```

注意此时：

```text
.firmware_header
```

还是：

# Input Section

---

# 十二、实验 32-5：不写 linker script 会怎样？

先：

```bash
gcc \
    main.o \
    header.o \
    -Wl,-Map,orphan.map \
    -o orphan.elf
```

然后：

```bash
readelf -SW orphan.elf
```

搜索：

```bash
readelf -SW orphan.elf | grep firmware
```

你很可能会看到：

```text
.firmware_header
```

但它的位置并不是你主动指定的。

这叫：

# Orphan Section

即：

> linker script 没有明确处理的 Input Section。

GNU ld 会根据自己的 orphan section 规则把它放入输出文件。

---

# 十三、这正是我们不希望完全依赖的方式

我们当然可以：

```text
“让 ld 自己决定”
```

但 Firmware 中经常需要：

```text
.firmware_header
必须位于 .text 前面
```

或者：

```text
.firmware_header
必须紧跟 .rodata
```

甚至：

```text
Firmware Header
↓
Text
↓
Read Only Data
```

因此：

```text
Orphan
```

不够精确。

我们需要：

# `INSERT BEFORE`

---

# 十四、实验 32-6：第一个 INSERT

创建：

```text
insert-before.ld
```

内容：

```ld
SECTIONS
{
    .firmware_header :
    {
        KEEP(*(.firmware_header))
    }
}

INSERT BEFORE .text;
```

注意这个 linker script **没有重新定义 `.text`**。

只有：

```ld
.firmware_header
```

然后：

```ld
INSERT BEFORE .text;
```

---

# 十五、最重要的一点

执行：

```bash
gcc \
    main.o \
    header.o \
    -Wl,-T,insert-before.ld \
    -Wl,-Map,insert-before.map \
    -o insert-before.elf
```

这里：

```text
-T insert-before.ld
```

并没有简单地表示：

```text
“完全替换默认 linker script”
```

因为：

```ld
INSERT BEFORE .text;
```

告诉 GNU ld：

> 把前面定义的 `.firmware_header` 插入默认 `.text` 前面。

GNU ld 文档明确规定，使用 `INSERT` 时，`-T` 脚本可以扩充默认 `SECTIONS`，而不是覆盖默认 script。([Sourceware][1])

---

# 十六、验证 Section 顺序

执行：

```bash
readelf -SW insert-before.elf
```

观察：

```text
.firmware_header
.text
```

它们应该相邻或处于预期的默认布局位置。

然后：

```bash
objdump -h insert-before.elf
```

重点看：

```text
.firmware_header
.text
```

---

# 十七、实验 32-7：Map 文件验证

```bash
grep -n -A10 -B5 '\.firmware_header' insert-before.map
```

你会看到类似：

```text
.firmware_header
                0x000000000040....
                0x000000000000000c
                header.o
                .firmware_header
```

然后紧接着：

```text
.text
```

---

# 十八、这里开始建立一个非常重要的排查方法

当你怀疑 linker script 没有生效：

不要首先猜。

执行：

```bash
readelf -SW xxx.elf
```

看：

```text
最终 Section
```

然后：

```bash
objdump -h xxx.elf
```

看：

```text
VMA / LMA / Size
```

最后：

```bash
grep -A... -B... xxx.map
```

看：

```text
ld 到底怎么放的
```

这三个工具分别承担不同角色：

```text
readelf
    ↓
ELF 结构验证

objdump
    ↓
Section / 指令 / LMA 快速观察

Map
    ↓
链接过程审计
```

---

# 十九、实验 32-8：为什么必须使用 `KEEP()`？

现在把：

```ld
KEEP(*(.firmware_header))
```

改成：

```ld
*(.firmware_header)
```

即：

```ld
SECTIONS
{
    .firmware_header :
    {
        *(.firmware_header)
    }
}

INSERT BEFORE .text;
```

重新编译：

```bash
gcc \
    main.o \
    header.o \
    -Wl,-T,insert-before.ld \
    -Wl,--gc-sections \
    -Wl,-Map,gc.map \
    -o gc.elf
```

---

# 二十、为什么可能消失？

因为：

```text
--gc-sections
```

告诉 linker：

> 删除没有被引用的 Section。

我们的：

```text
firmware_header
```

没有任何 C 代码引用它。

因此：

```text
.firmware_header
        ↓
没有引用
        ↓
GC
        ↓
可能被删除
```

---

# 二十一、加回 `KEEP`

改成：

```ld
SECTIONS
{
    .firmware_header :
    {
        KEEP(*(.firmware_header))
    }
}

INSERT BEFORE .text;
```

重新：

```bash
gcc \
    main.o \
    header.o \
    -Wl,-T,insert-before.ld \
    -Wl,--gc-sections \
    -Wl,-Map,keep.map \
    -o keep.elf
```

验证：

```bash
readelf -SW keep.elf | grep firmware
```

应该还能看到：

```text
.firmware_header
```

所以这里形成一个非常重要的组合：

```text
INSERT
    +
KEEP
```

即：

> **把 Section 放到指定位置，并且保证它不会因为 `--gc-sections` 被回收。**

---

# 二十二、实验 32-9：`INSERT AFTER`

现在改成：

```ld
SECTIONS
{
    .firmware_header :
    {
        KEEP(*(.firmware_header))
    }
}

INSERT AFTER .rodata;
```

编译：

```bash
gcc \
    main.o \
    header.o \
    -Wl,-T,insert-after.ld \
    -Wl,--gc-sections \
    -Wl,-Map,after.map \
    -o after.elf
```

验证：

```bash
readelf -SW after.elf
```

现在重点观察：

```text
.rodata
.firmware_header
.eh_frame
```

也就是说：

```text
INSERT AFTER .rodata
```

不是：

```text
“Section 地址 + 某个偏移”
```

而是：

> **把整个 Output Section 插入默认 Output Section 序列。**

---

# 二十三、实验 32-10：`INSERT BEFORE` 与 `INSERT AFTER`

可以把它理解成：

```text
默认：

.text
.rodata
.eh_frame
.data
.bss
```

执行：

```ld
INSERT BEFORE .text;
```

得到：

```text
.firmware_header
.text
.rodata
.eh_frame
.data
.bss
```

而：

```ld
INSERT AFTER .rodata;
```

得到：

```text
.text
.rodata
.firmware_header
.eh_frame
.data
.bss
```

---

# 二十四、一个非常重要的细节：你没有控制 `.text` 本身

注意：

```ld
SECTIONS
{
    .firmware_header :
    {
        KEEP(*(.firmware_header))
    }
}

INSERT BEFORE .text;
```

这里没有：

```ld
.text :
{
    *(.text)
}
```

所以：

```text
.text
```

仍然来自：

# GNU ld 默认 linker script。

这是这节课最核心的思想。

---

# 二十五、实验 32-11：验证默认 `.text` 仍然存在

执行：

```bash
ld --verbose
```

找到：

```ld
.text :
{
    ...
}
```

然后：

```bash
readelf -SW insert-before.elf
```

比较：

```text
默认 ELF
```

与：

```text
insert-before ELF
```

你会发现：

```text
.text
.rodata
.data
.bss
```

这些默认 Section 仍然存在。

只是多了：

```text
.firmware_header
```

---

# 二十六、实验 32-12：做一个 Firmware Header

现在我们让实验更接近真正的 Firmware。

定义：

```c
#include <stdint.h>

struct firmware_header
{
    uint32_t magic;
    uint32_t version;
    uint32_t image_size;
    uint32_t entry;
};

__attribute__((section(".firmware_header")))
const struct firmware_header header =
{
    .magic     = 0x46574844,
    .version   = 1,
    .image_size = 0,
    .entry      = 0
};
```

编译：

```bash
gcc \
    -ffreestanding \
    -fno-pie \
    -ffunction-sections \
    -fdata-sections \
    -c header.c \
    -o header.o
```

---

# 二十七、我们希望最终 ELF：

```text
0x00400000
┌──────────────────────────┐
│ .firmware_header         │
├──────────────────────────┤
│ .text                    │
├──────────────────────────┤
│ .rodata                  │
├──────────────────────────┤
│ .eh_frame                │
├──────────────────────────┤
│ .data                    │
├──────────────────────────┤
│ .bss                     │
└──────────────────────────┘
```

那么：

```ld
INSERT BEFORE .text;
```

就是非常漂亮的解决方案。

---

# 二十八、实验 32-13：给 Header 定义 linker symbol

进一步：

```ld
SECTIONS
{
    .firmware_header :
    {
        __firmware_header_start = .;

        KEEP(*(.firmware_header))

        __firmware_header_end = .;
    }
}

INSERT BEFORE .text;
```

现在 linker 自动生成：

```text
__firmware_header_start
__firmware_header_end
```

---

# 二十九、验证 Symbol

```bash
nm -n header.elf | grep firmware_header
```

或者：

```bash
readelf -sW header.elf |
grep firmware_header
```

应该看到：

```text
__firmware_header_start
__firmware_header_end
```

然后：

```bash
objdump -h header.elf
```

比较：

```text
.firmware_header
```

的：

```text
VMA
Size
```

与：

```text
__firmware_header_start
__firmware_header_end
```

之间的关系：

```text
end - start
=
Section Size
```

---

# 三十、实验 32-14：在 C 中使用 linker symbol

增加：

```c
extern const unsigned char __firmware_header_start[];
extern const unsigned char __firmware_header_end[];
```

计算：

```c
size_t header_size =
    __firmware_header_end -
    __firmware_header_start;
```

这就是我们之前在 Overlay 实验中反复使用的 linker symbol 思维。

现在你应该开始形成统一认识：

```text
Linker Script
        ↓
定义地址
        ↓
定义符号
        ↓
C / Assembly 使用符号
```

---

# 三十一、实验 32-15：`INSERT` + `PROVIDE`

可以改成：

```ld
SECTIONS
{
    .firmware_header :
    {
        PROVIDE(__firmware_header_start = .);

        KEEP(*(.firmware_header))

        PROVIDE(__firmware_header_end = .);
    }
}

INSERT BEFORE .text;
```

这和直接：

```ld
__firmware_header_start = .;
```

的一个重要区别是：

`PROVIDE` 只有在该符号没有被其他地方定义时才提供。

这在大型工程里很有用。

---

# 三十二、实验 32-16：`INSERT` + `ALIGN`

这一节尤其要注意你之前纠正过的那个问题：

> **不要把 Output Section 的 `ALIGN()` 写成错误的 `.text ALIGN(16) :` 形式。**

这里我们使用：

```ld
SECTIONS
{
    .firmware_header :
        ALIGN(16)
    {
        KEEP(*(.firmware_header))
    }
}

INSERT BEFORE .text;
```

也就是说：

```ld
.firmware_header :
    ALIGN(16)
{
    ...
}
```

而不是：

```ld
.firmware_header ALIGN(16) :
{
    ...
}
```

这个实验继续沿用你之前发现的 GNU ld 语法要点。

---

# 三十三、验证 ALIGN

```bash
readelf -SW header.elf
```

查看：

```text
.firmware_header
```

Address。

然后：

```bash
printf '%x\n' $((ADDRESS % 16))
```

应该：

```text
0
```

即：

```text
ADDRESS % 16 == 0
```

---

# 三十四、实验 32-17：Header 后面放 Padding

现在：

```ld
SECTIONS
{
    .firmware_header :
        ALIGN(16)
    {
        __firmware_header_start = .;

        KEEP(*(.firmware_header))

        __firmware_header_end = .;

        . = ALIGN(16);
    }
}

INSERT BEFORE .text;
```

注意：

```ld
. = ALIGN(16);
```

是修改：

# Location Counter

而：

```ld
ALIGN(16)
```

作为 Output Section 的属性，作用于 Section 起始位置。

这两个概念不要混。

---

# 三十五、实验 32-18：为什么 `INSERT` 对默认 Section 特别有价值？

考虑一个真实项目。

默认 linker script 有：

```text
.text
.rodata
.eh_frame
.preinit_array
.init_array
.fini_array
.data
.bss
```

你如果自己复制整个：

```text
ld --verbose
```

结果，就等于：

```text
把 binutils 当前版本的实现细节
复制到自己的项目
```

未来升级：

```text
binutils
GCC
Linux toolchain
```

可能导致：

```text
默认 script 改变
```

然后你的：

```text
复制版 linker.ld
```

就可能落后。

而：

```ld
INSERT AFTER .rodata;
```

只表达：

> “我要把我的 Section 放在 `.rodata` 后面。”

默认 linker script 其他内容仍由工具链维护。

这是大型项目中非常有价值的维护策略。

---

# 三十六、实验 32-19：观察 `INSERT` 的真正处理顺序

官方文档有一个非常值得注意的细节：

> `INSERT` 的插入发生在 linker 已经把 Input Section 映射到 Output Section 之后。([Sourceware][1])

可以把过程抽象成：

```text
Input ELF
   │
   ▼
Input Sections
   │
   ▼
匹配 linker script
   │
   ▼
Output Section
   │
   ▼
INSERT 定位
   │
   ▼
最终布局
```

所以：

```ld
.firmware_header
{
    KEEP(*(.firmware_header))
}
```

首先创建：

```text
Output Section
```

然后：

```ld
INSERT BEFORE .text;
```

决定它最终插到默认 `.text` 哪里。

---

# 三十七、实验 32-20：比较三种方式

这是今天非常值得做的对照实验。

## 方式 A：完全依赖 Orphan

```bash
gcc main.o header.o -o orphan.elf
```

```text
ld 自己决定 .firmware_header 放哪里
```

---

## 方式 B：完整自定义 linker script

```bash
gcc main.o header.o \
    -Wl,-T,full.ld \
    -o full.elf
```

```text
你接管整个布局
```

---

## 方式 C：INSERT

```bash
gcc main.o header.o \
    -Wl,-T,insert.ld \
    -o insert.elf
```

```text
默认布局
+
你的局部修改
```

所以：

```text
Orphan
    ↓
最少控制

INSERT
    ↓
局部控制

完整 -T
    ↓
最大控制
```

这是非常重要的 linker script 设计选择。

---

# 三十八、实验 32-21：Map 文件三路比较

分别生成：

```text
orphan.map
full.map
insert.map
```

然后：

```bash
grep -n -A8 -B4 '\.firmware_header' orphan.map
```

```bash
grep -n -A8 -B4 '\.firmware_header' full.map
```

```bash
grep -n -A8 -B4 '\.firmware_header' insert.map
```

重点不是看“有没有”。

而是比较：

```text
Address
Size
Input Object
Input Section
前后 Section
```

---

# 三十九、实验 32-22：`INSERT` + `--gc-sections`

这是一个真实工程非常常见的组合：

```bash
gcc \
    main.o \
    header.o \
    -Wl,-T,insert.ld \
    -Wl,--gc-sections \
    -Wl,-Map,firmware.map \
    -o firmware.elf
```

linker script：

```ld
SECTIONS
{
    .firmware_header :
    {
        KEEP(*(.firmware_header))
    }
}

INSERT BEFORE .text;
```

形成：

```text
INSERT
   ↓
决定位置

KEEP
   ↓
防止 GC

--gc-sections
   ↓
回收其他无用 Section
```

这个组合非常适合 Firmware。

---

# 四十、实验 32-23：进一步做一个 `.build_info`

增加：

```c
__attribute__((section(".build_info")))
const char build_info[] =
    "BUILD=2026-10-01";
```

linker：

```ld
SECTIONS
{
    .build_info :
    {
        __build_info_start = .;

        KEEP(*(.build_info))

        __build_info_end = .;
    }
}

INSERT AFTER .rodata;
```

于是：

```text
.text
.rodata
.build_info
.eh_frame
```

---

# 四十一、实验 32-24：多个 Section 一次 INSERT

可以：

```ld
SECTIONS
{
    .firmware_header :
    {
        KEEP(*(.firmware_header))
    }

    .build_info :
    {
        KEEP(*(.build_info))
    }

    .factory_config :
    {
        KEEP(*(.factory_config))
    }
}

INSERT BEFORE .text;
```

最终：

```text
.firmware_header
.build_info
.factory_config
.text
```

也就是说：

> `INSERT` 插入的是整个前面定义的 linker script statements。

GNU ld 文档明确说明，`INSERT` 会把此前 linker script statements 插入到指定 Output Section 的前/后。([Sourceware][1])

---

# 四十二、实验 32-25：`INSERT AFTER` + 多个 Section

```ld
SECTIONS
{
    .build_info :
    {
        KEEP(*(.build_info))
    }

    .firmware_metadata :
    {
        KEEP(*(.firmware_metadata))
    }
}

INSERT AFTER .rodata;
```

结果：

```text
.rodata
.build_info
.firmware_metadata
.eh_frame
```

---

# 四十三、一个非常容易踩的坑

不要把：

```ld
INSERT AFTER .rodata;
```

理解成：

```text
“紧跟 .rodata 的最后一个 Input Section”
```

它针对的是：

# Output Section

也就是说：

```text
.rodata
```

是默认 linker script 中的：

```text
Output Section
```

不是：

```text
Input Section
```

这一点和我们前面学习：

```text
NOCROSSREFS(.foo .bar)
```

时一样。

`NOCROSSREFS` 操作的是：

```text
Output Section
```

GNU ld 文档也特别指出 `NOCROSSREFS` 使用的是 Output Section 名称。([Sourceware][1])

---

# 四十四、实验 32-26：如果目标 Section 不存在呢？

尝试：

```ld
INSERT AFTER .does_not_exist;
```

然后：

```bash
gcc \
    main.o \
    header.o \
    -Wl,-T,test.ld \
    -o test.elf
```

观察 linker 的错误。

这个实验的目的不是记住具体错误文本，而是建立：

```text
INSERT
    ↓
必须找到合法的插入目标
```

因此在大型工程中：

```text
INSERT AFTER .rodata
```

通常比：

```text
INSERT AFTER 某个自定义 Section
```

更稳妥。

---

# 四十五、实验 32-27：查看默认 linker script 中的 `.text`

执行：

```bash
ld --verbose > ld.verbose
```

然后：

```bash
grep -n '^\.text' ld.verbose
```

也可以：

```bash
grep -n '\.text :' ld.verbose
```

找到：

```ld
.text :
{
    ...
}
```

然后：

```bash
sed -n 'START,ENDp' ld.verbose
```

观察 GNU 默认脚本究竟对 `.text` 做了什么。

这个动作非常重要：

> **不要只学习 linker script 的语法，要学会阅读 GNU 自己写的 linker script。**

---

# 四十六、实验 32-28：研究 `.rodata` 为什么不是一个简单 Section

执行：

```bash
grep -n '\.rodata' ld.verbose
```

你通常会发现默认 linker script 里面存在各种：

```text
.rodata
.rodata1
.rodata.*
```

以及：

```text
.eh_frame
.sframe
.gnu.build.attributes
```

之类的处理。

这就是为什么：

```text
“自己复制一个简化 linker.ld”
```

在真实工程中往往危险。

---

# 四十七、实验 32-29：一个完整的 Firmware 插件式 linker script

现在做一个比较实用的最终版本：

```ld
SECTIONS
{
    .firmware_header :
        ALIGN(16)
    {
        __firmware_header_start = .;

        KEEP(*(.firmware_header))

        __firmware_header_end = .;
    }

    .build_info :
    {
        __build_info_start = .;

        KEEP(*(.build_info))

        __build_info_end = .;
    }

    .factory_config :
        ALIGN(16)
    {
        __factory_config_start = .;

        KEEP(*(.factory_config))

        __factory_config_end = .;
    }
}

INSERT BEFORE .text;
```

然后：

```bash
gcc \
    main.o \
    header.o \
    build_info.o \
    factory_config.o \
    -Wl,-T,firmware-insert.ld \
    -Wl,--gc-sections \
    -Wl,-Map,firmware.map \
    -o firmware.elf
```

---

# 四十八、最终验证

## Section

```bash
readelf -SW firmware.elf
```

---

## 地址

```bash
objdump -h firmware.elf
```

---

## Symbol

```bash
nm -n firmware.elf
```

---

## 特定 Symbol

```bash
nm -n firmware.elf |
grep -E 'firmware_header|build_info|factory_config'
```

---

## Map

```bash
grep -n -A12 -B4 \
    -E '\.firmware_header|\.build_info|\.factory_config' \
    firmware.map
```

---

# 四十九、最终形成这样的结构

```text
默认 GNU linker script
             │
             ▼
       ┌─────────────┐
       │ .firmware   │ ← 我们插入
       │   _header   │
       ├─────────────┤
       │ .build_info │ ← 我们插入
       ├─────────────┤
       │ .factory_   │ ← 我们插入
       │   config    │
       ├─────────────┤
       │ .text       │ ← GNU 默认
       ├─────────────┤
       │ .rodata     │ ← GNU 默认
       ├─────────────┤
       │ .eh_frame   │ ← GNU 默认
       ├─────────────┤
       │ .data       │ ← GNU 默认
       ├─────────────┤
       │ .bss        │ ← GNU 默认
       └─────────────┘
```

这就是：

# “默认 linker script + 增量式定制”

---

# 五十、这一节真正要掌握的不是 `INSERT` 语法

真正应该掌握的是下面这个决策模型：

```text
我需要修改 ELF Section 布局
             │
             ▼
      需要完全控制吗？
        /          \
      是            否
      │              │
      ▼              ▼
完整 linker.ld    INSERT
      │              │
      │        ┌─────┴─────┐
      │        │           │
      │      BEFORE       AFTER
      │        │           │
      ▼        ▼           ▼
完全接管     .text       .rodata
```

---

# 五十一、把实验 31 和实验 32 连起来

现在课程开始出现一个非常清晰的层次：

```text
实验 30
ASSERT
NOCROSSREFS
NOCROSSREFS_TO
        │
        ▼
架构约束
```

```text
实验 31
OVERLAY
AT
LOADADDR
        │
        ▼
VMA / LMA / Overlay
```

```text
实验 32
INSERT BEFORE
INSERT AFTER
        │
        ▼
增量修改默认 linker script
```

也就是说：

```text
30 = 检查
31 = 内存布局
32 = 默认脚本扩展
```

---

# 五十二、下一节：实验 33 —— `SORT` 系列

接下来我们进入一个看似简单、实际非常重要的主题：

# `SORT() / SORT_BY_NAME() / SORT_BY_ALIGNMENT()`

这一节会解决一个非常实际的问题：

假设有：

```text
a.o
b.o
c.o
```

每个对象都有：

```text
.my_init
```

Input Section。

linker 最终应该按照：

```text
a
b
c
```

还是：

```text
c
a
b
```

还是：

```text
alignment
```

排序？

下一节会依次做：

```text
实验 33-1
多个 .foo Input Section

实验 33-2
观察默认排列顺序

实验 33-3
SORT()

实验 33-4
SORT_BY_NAME()

实验 33-5
SORT_BY_ALIGNMENT()

实验 33-6
SORT_BY_INIT_PRIORITY()

实验 33-7
SORT + KEEP

实验 33-8
嵌套 SORT

实验 33-9
Map 文件验证排序结果

实验 33-10
.init_array / C++ constructor 排序

实验 33-11
构造函数 priority 与 linker 排序

实验 33-12
利用排序构造 Firmware Plugin Registry
```

最后会把它进一步连接到：

```text
.init_array
    ↓
C++ constructor
    ↓
__attribute__((constructor))
    ↓
INIT_PRIORITY
    ↓
SORT_BY_INIT_PRIORITY
```

这一部分会开始真正进入 **C/C++ Runtime + GNU ld** 的交界处。

而且这里会出现一个很有意思的真实工程模式：

```text
各个 .o
   │
   ├── 注册 Driver
   ├── 注册 Command
   ├── 注册 Protocol
   ├── 注册 Plugin
   └── 注册 Device
          │
          ▼
      linker 收集
          │
          ▼
      SORT / KEEP
          │
          ▼
      自动形成 Registry
```

这正是 GNU ld 从“链接器”变成“编译期元数据构建器”的一个非常漂亮的应用。

[1]: https://sourceware.org/binutils/docs/ld.pdf?utm_source=chatgpt.com "The GNU linker"
[2]: https://snapshots.sourceware.org/gcc/docs/latest/gcc/Freestanding-Environments.html?utm_source=chatgpt.com "Freestanding Environments (Using the GNU Compiler Collection (GCC))"
[3]: https://gcc.sourceware.org/onlinedocs/gcc/Invoking-GCC.html?utm_source=chatgpt.com "Invoking GCC (Using the GNU Compiler Collection (GCC))"

