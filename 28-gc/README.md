# GNU ld 实战课程 · 实验 28

# `--gc-sections` + `KEEP()`：理解“链接器垃圾回收”

上一节我们已经把 Firmware 镜像推进到了：

```text
C / ASM
   ↓
Input Section
   ↓
Output Section
   ↓
VMA / LMA
   ↓
PT_LOAD
   ↓
ELF
   ↓
objcopy
   ↓
firmware.bin
```

这一节解决一个真实工程里非常常见的问题：

> **为什么我明明编译出了一个函数、一个变量、甚至一个 Firmware Header，链接以后却不见了？**

答案就是：

```text
--gc-sections
```

它会让 GNU ld 对 **Input Section** 做垃圾回收。

GNU ld 当前文档说明，`--gc-sections` 会根据符号和 relocation 建立“从根开始可达”的 Section 集合，并删除不可达的 Input Section；`--print-gc-sections` 可以把被删除的 Section 打印出来。([Sourceware][1])

而：

```ld
KEEP(...)
```

则可以明确告诉 linker：

> **这个 Section 即使看起来没人引用，也不能删。**

---

# 一、这一节最终要做什么？

我们故意制造：

```text
used_function()
unused_function()

used_data
unused_data

.firmware_header
.factory_data
```

然后分别进行：

```text
实验 A
没有 --gc-sections

实验 B
加入 --gc-sections

实验 C
加入 KEEP()

实验 D
加入 /DISCARD/

实验 E
使用 SORT_BY_NAME()

实验 F
使用 EXCLUDE_FILE()
```

最终得到：

```text
Input Sections
       │
       ▼
  GC Root Analysis
       │
   ┌───┴────┐
   │        │
reachable  unreachable
   │        │
   ▼        ▼
 KEEP      delete
   │
   ▼
Output ELF
```

---

# 二、实验 28-1：准备工程

目录：

```text
lab28/
├── start.S
├── main.c
├── functions.c
├── data.c
├── linker.ld
└── Makefile
```

---

# 三、`start.S`

继续使用上一节的启动代码：

```asm
.global _start

.extern main

.text

_start:
    call main

.hang:
    hlt
    jmp .hang
```

---

# 四、`main.c`

```c
extern int used_data;
extern int unused_data;

extern int used_function(void);
extern int unused_function(void);

int main(void)
{
    used_data++;

    return used_function();
}
```

注意：

```c
unused_data
unused_function()
```

**故意没有使用。**

---

# 五、`functions.c`

```c
int used_function(void)
{
    return 123;
}

int unused_function(void)
{
    return 456;
}
```

由于我们之前一直使用：

```bash
-fno-pie
```

这里继续保持简单。

但这一次必须额外使用：

```bash
-ffunction-sections
```

这样 GCC 会把函数分别放进：

```text
.text.used_function
.text.unused_function
```

之类的独立 Input Section。

GCC 文档明确说明，`-ffunction-sections` 和 `-fdata-sections` 会让每个函数/数据项进入独立 Section，这正是配合 linker garbage collection 的基础。([GCC][2])

---

# 六、`data.c`

```c
int used_data = 100;

int unused_data = 200;

__attribute__((section(".factory_data")))
const unsigned char factory_data[] =
{
    0x11,
    0x22,
    0x33,
    0x44,
    0x55,
    0x66,
    0x77,
    0x88
};

__attribute__((section(".firmware_header")))
const unsigned int firmware_magic = 0x46574D47;
```

这里制造四种情况：

```text
used_data
    ↓
被 main 引用

unused_data
    ↓
没有引用

.factory_data
    ↓
没有引用

.firmware_header
    ↓
没有引用
```

后面正好观察 linker 如何处理它们。

---

# 七、实验 28-2：编译

```bash
gcc \
    -ffreestanding \
    -fno-pie \
    -fno-stack-protector \
    -ffunction-sections \
    -fdata-sections \
    -c start.S \
    -o start.o
```

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

```bash
gcc \
    -ffreestanding \
    -fno-pie \
    -fno-stack-protector \
    -ffunction-sections \
    -fdata-sections \
    -c functions.c \
    -o functions.o
```

```bash
gcc \
    -ffreestanding \
    -fno-pie \
    -fno-stack-protector \
    -ffunction-sections \
    -fdata-sections \
    -c data.c \
    -o data.o
```

---

# 八、实验 28-3：先看 Input Section

执行：

```bash
objdump -h functions.o
```

重点应该看到类似：

```text
.text
.text.used_function
.text.unused_function
```

然后：

```bash
objdump -h data.o
```

观察：

```text
.data.used_data
.data.unused_data
.factory_data
.firmware_header
```

这一步非常重要。

现在我们真正拥有：

```text
一个函数
      ↓
一个 Input Section

另一个函数
      ↓
另一个 Input Section
```

因此 linker 才有机会：

```text
保留 A
删除 B
```

---

# 九、实验 28-4：没有垃圾回收

先使用：

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

    .rodata :
    {
        *(.rodata)
        *(.rodata.*)
    } > ROM

    .factory_data :
    {
        *(.factory_data)
    } > ROM

    .firmware_header :
    {
        *(.firmware_header)
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

链接：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    functions.o \
    data.o \
    -o no-gc.elf \
    -Map=no-gc.map
```

---

# 十、观察 Section

```bash
readelf -SW no-gc.elf
```

应该能够看到：

```text
.text
.factory_data
.firmware_header
.data
```

以及：

```bash
nm -n no-gc.elf
```

搜索：

```bash
nm -n no-gc.elf | grep -E 'used|unused|factory|firmware'
```

应该可以看到：

```text
used_function
unused_function
used_data
unused_data
firmware_magic
```

因为目前：

```text
--gc-sections
```

还没有启用。

---

# 十一、实验 28-5：第一次开启 Garbage Collection

现在链接命令改成：

```bash
ld \
    --gc-sections \
    --print-gc-sections \
    -T linker.ld \
    start.o \
    main.o \
    functions.o \
    data.o \
    -o gc.elf \
    -Map=gc.map
```

这里有两个重要参数：

```text
--gc-sections
```

开启垃圾回收。

以及：

```text
--print-gc-sections
```

打印被回收的 Section。

GNU ld 文档明确说明，后者只有在 `--gc-sections` 开启时才有效。([Sourceware][1])

---

# 十二、现在你应该看到什么？

stderr 中可能出现类似：

```text
removing unused section ' .text.unused_function'
removing unused section ' .data.unused_data'
removing unused section ' .factory_data'
removing unused section ' .firmware_header'
```

具体 Section 名称会根据 GCC/binutils 版本有所不同。

这就是：

# Linker Garbage Collection

真正开始工作。

---

# 十三、实验 28-6：为什么 `used_function()` 没被删除？

因为：

```text
_start
   ↓
main
   ↓
used_function
```

形成了一条引用链。

可以画成：

```text
_start
  │
  ▼
main
  │
  ▼
used_function
```

所以：

```text
.text._start
.text.main
.text.used_function
```

都是：

```text
reachable
```

---

# 十四、而 `unused_function()` 呢？

它是：

```text
unused_function
     ↑
     │
没有任何引用
```

因此：

```text
unreachable
```

于是：

```text
--gc-sections
```

将它删除。

---

# 十五、这其实是一个“图算法”

把每个 Input Section 看成：

```text
Node
```

把 relocation/reference 看成：

```text
Edge
```

例如：

```text
.text._start
       │
       │ relocation
       ▼
.text.main
       │
       │ relocation
       ▼
.text.used_function
```

于是：

```text
Root
 ↓
_start
 ↓
main
 ↓
used_function
```

全部保留。

但是：

```text
.text.unused_function
```

没有路径：

```text
Root → unused_function
```

所以：

```text
Garbage
```

被删除。

这就是 `--gc-sections` 最核心的思想。

---

# 十六、实验 28-7：谁是 GC Root？

GNU ld 会从若干 Root 开始进行可达性分析。

当前实验最重要的 Root 是：

```text
ENTRY(_start)
```

所以：

```ld
ENTRY(_start)
```

不仅决定：

```text
ELF Entry Point
```

还会影响：

```text
GC Root
```

GNU ld 文档明确指出，在 `--gc-sections` 下，包含 entry symbol 的 Section 会被保留。([Sourceware][1])

---

# 十七、实验 28-8：如果没有 `ENTRY(_start)` 会怎样？

暂时修改 linker：

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

去掉：

```ld
ENTRY(_start)
```

然后：

```bash
ld \
    --gc-sections \
    --print-gc-sections \
    -T linker-no-entry.ld \
    start.o \
    main.o \
    functions.o \
    data.o \
    -o no-entry.elf
```

观察结果。

你会发现：

```text
GC Root
```

的建立方式发生变化。

这也是为什么裸机 linker script 中：

```ld
ENTRY(_start)
```

不是装饰品。

---

# 十八、实验 28-9：`.firmware_header` 为什么被删除？

我们的：

```c
__attribute__((section(".firmware_header")))
const unsigned int firmware_magic = ...
```

没有被：

```text
main
```

引用。

所以：

```text
.firmware_header
```

是：

```text
unreachable
```

因此：

```text
--gc-sections
```

会把它删除。

这对于 Firmware 是一个非常危险的问题。

因为 Firmware Header 通常就是：

```text
Bootloader
    ↓
主动查找
```

而不是：

```text
C function
    ↓
引用
```

因此：

# Firmware Metadata 经常天然需要 `KEEP()`。

---

# 十九、实验 28-10：第一次使用 `KEEP()`

修改：

```ld
.firmware_header :
{
    KEEP(*(.firmware_header))
} > ROM
```

完整：

```ld
.firmware_header :
{
    __firmware_header_start = .;

    KEEP(*(.firmware_header))

    __firmware_header_end = .;
} > ROM
```

重新链接：

```bash
ld \
    --gc-sections \
    --print-gc-sections \
    -T linker.ld \
    start.o \
    main.o \
    functions.o \
    data.o \
    -o keep.elf \
    -Map=keep.map
```

---

# 二十、观察变化

现在：

```bash
nm -n keep.elf | grep firmware
```

应该还能看到：

```text
firmware_magic
```

同时：

```bash
readelf -SW keep.elf
```

还能看到：

```text
.firmware_header
```

而：

```text
.text.unused_function
```

仍然被删除。

这就是：

```text
KEEP()
```

真正的作用：

```text
GC:
    删除不可达 Section

KEEP:
    这个 Input Section 不允许被 GC 删除
```

---

# 二十一、`KEEP()` 不是“强制所有情况下存在”

这里要非常严谨。

`KEEP()` 的核心用途是：

> **在 `--gc-sections` 的垃圾回收阶段保护匹配的 Input Section。**

它不是：

```text
“无论任何情况下都必须出现在最终 ELF”
```

例如：

```ld
/DISCARD/ :
{
    *(.firmware_header)
}
```

优先把它丢掉时，`KEEP()` 并不能把它“复活”。

GNU ld 文档明确说明 `/DISCARD/` 可以丢弃 Input Section，而且 discarded sections 的处理具有优先性。([Sourceware][3])

---

# 二十二、实验 28-11：`KEEP()` 与 `/DISCARD/`

故意写：

```ld
.firmware_header :
{
    KEEP(*(.firmware_header))
} > ROM

/DISCARD/ :
{
    *(.firmware_header)
}
```

重新链接：

```bash
ld \
    --gc-sections \
    -T linker.ld \
    start.o \
    main.o \
    functions.o \
    data.o \
    -o discard.elf
```

然后：

```bash
readelf -SW discard.elf
```

你会发现：

```text
.firmware_header
```

仍然可能消失。

这说明：

```text
KEEP
```

和：

```text
/DISCARD/
```

不是：

```text
KEEP > DISCARD
```

而是：

```text
/DISCARD/
```

本身就是明确的丢弃规则。

---

# 二十三、实验 28-12：真正的 Firmware Data Section

把：

```text
.factory_data
```

也保护起来。

```ld
.factory_data :
{
    __factory_data_start = .;

    KEEP(*(.factory_data))

    __factory_data_end = .;
} > ROM
```

然后：

```bash
ld \
    --gc-sections \
    --print-gc-sections \
    -T linker.ld \
    start.o \
    main.o \
    functions.o \
    data.o \
    -o factory.elf \
    -Map=factory.map
```

验证：

```bash
readelf -SW factory.elf
```

和：

```bash
objdump -s -j .factory_data factory.elf
```

---

# 二十四、现在我们得到一个真实 Firmware 模型

```text
ROM
│
├── .text
│
├── .rodata
│
├── .firmware_header
│      ↑
│      KEEP
│
├── .factory_data
│      ↑
│      KEEP
│
└── .data image
```

其中：

```text
.text
```

靠：

```text
ENTRY
+
relocation graph
```

被保留。

而：

```text
.firmware_header
.factory_data
```

靠：

```text
KEEP()
```

被保留。

---

# 二十五、实验 28-13：观察 Map 文件中的 GC 结果

执行：

```bash
less gc.map
```

或者：

```bash
grep -n "unused_function" gc.map
```

再：

```bash
grep -n "factory_data" factory.map
```

再：

```bash
grep -n "firmware_header" keep.map
```

这里有一个非常重要的经验：

> **Map 文件不是只用来看“最后留下什么”，也要用来看“为什么没留下”。**

结合：

```bash
--print-gc-sections
```

你就可以：

```text
stderr
    ↓
为什么被删除

map
    ↓
最后留下什么

readelf
    ↓
最终 ELF 是否真的存在
```

形成三层验证。

---

# 二十六、实验 28-14：比较 ELF 大小

执行：

```bash
ls -lh no-gc.elf gc.elf keep.elf factory.elf
```

你应该看到：

```text
no-gc.elf
    最大

gc.elf
    更小

keep.elf
    比 gc.elf 稍大

factory.elf
    又保留了更多内容
```

这就是：

```text
Section GC
```

带来的真实效果。

---

# 二十七、实验 28-15：比较函数地址

```bash
nm -n no-gc.elf | grep function
```

与：

```bash
nm -n gc.elf | grep function
```

你会发现：

```text
unused_function
```

在：

```text
gc.elf
```

中不存在。

---

# 二十八、实验 28-16：观察 Binary 大小变化

生成：

```bash
objcopy -O binary no-gc.elf no-gc.bin

objcopy -O binary gc.elf gc.bin

objcopy -O binary keep.elf keep.bin
```

然后：

```bash
ls -lh *.bin
```

你会看到：

```text
no-gc.bin
gc.bin
keep.bin
```

大小可能不同。

这里就把：

```text
Input Section GC
```

直接连接到了：

```text
Firmware Flash Size
```

这就是嵌入式工程为什么非常重视：

```text
--gc-sections
```

的原因。

---

# 二十九、实验 28-17：`--print-gc-sections` 是非常重要的调试工具

推荐以后固定使用：

```bash
ld \
    --gc-sections \
    --print-gc-sections \
    ...
```

尤其是在 linker script 修改之后。

如果突然发现：

```text
某个驱动没了
某个命令表没了
某个注册表没了
某个 Firmware Header 没了
```

第一反应：

```text
--print-gc-sections
```

而不是：

```text
“是不是编译器坏了？”
```

---

# 三十、实验 28-18：自定义 Registry

现在模拟一个真实场景：

```text
driver_a
driver_b
driver_c
```

每个 Driver 都有一个：

```text
.driver_table
```

Section。

`data.c`：

```c
struct driver
{
    const char *name;
    int id;
};

__attribute__((section(".driver_table")))
const struct driver driver_a =
{
    "driver_a",
    1
};

__attribute__((section(".driver_table")))
const struct driver driver_b =
{
    "driver_b",
    2
};

__attribute__((section(".driver_table")))
const struct driver driver_c =
{
    "driver_c",
    3
};
```

这些对象可能完全没有普通 C 引用。

---

# 三十一、如果不使用 `KEEP()`

linker：

```ld
.driver_table :
{
    *(.driver_table)
} > ROM
```

然后：

```bash
ld \
    --gc-sections \
    --print-gc-sections \
    ...
```

这些：

```text
driver_a
driver_b
driver_c
```

可能全部被认为是：

```text
unreachable
```

然后删除。

---

# 三十二、使用 `KEEP()`

```ld
.driver_table :
{
    __driver_table_start = .;

    KEEP(*(.driver_table))

    __driver_table_end = .;
} > ROM
```

现在：

```text
driver_a
driver_b
driver_c
```

全部保留。

---

# 三十三、这就是很多嵌入式框架的核心技巧

你以后会经常看到：

```text
.init_array
.device_table
.driver_table
.command_table
.shell_command
.isr_vector
.firmware_header
.factory_data
```

这些 Section 经常具有：

```text
“程序逻辑没有普通 C 引用，但运行时需要通过遍历表来发现它们”
```

的特点。

所以：

```text
KEEP()
```

是 linker script 中非常重要的工程机制。

---

# 三十四、实验 28-19：为什么“运行时遍历”也可以成为 GC Root？

假设我们有：

```c
extern const struct driver __driver_table_start[];
extern const struct driver __driver_table_end[];

void init_drivers(void)
{
    for (const struct driver *p = __driver_table_start;
         p < __driver_table_end;
         p++)
    {
        /* use driver */
    }
}
```

这里：

```text
C 代码
```

确实引用：

```text
__driver_table_start
__driver_table_end
```

但是：

> **是否足以让所有 `.driver_table` Input Section 被 GC 保留，要看具体 linker/ELF 规则和构造方式。**

现代 GNU ld 对 `__start_SECNAME` / `__stop_SECNAME` 有专门的 GC 行为；官方文档也说明，引用合成的 `__start_SECNAME` / `__stop_SECNAME` 可以使对应 Section 被保留，但这依赖特定命名与条件。([Sourceware][4])

工程上为了让 linker script 的意图最明确：

```ld
KEEP(*(.driver_table))
```

仍然是非常稳妥的写法。

---

# 三十五、实验 28-20：`SORT_BY_NAME()`

现在假设：

```text
driver_a
driver_b
driver_c
```

分别来自：

```text
a.o
b.o
c.o
```

linker：

```ld
.driver_table :
{
    KEEP(*(.driver_table))
} > ROM
```

默认顺序主要受到：

```text
输入文件顺序
```

等因素影响。

如果我们想明确按照 Section 名称排序，可以：

```ld
.driver_table :
{
    KEEP(*(SORT_BY_NAME(.driver_table)))
} > ROM
```

GNU ld 文档支持 `SORT_BY_NAME` 等输入 Section 排序机制。([Sourceware][3])

---

# 三十六、实验 28-21：人为制造不同 Section 名称

创建：

```c
__attribute__((section(".driver_table.30")))
const int driver_30 = 30;

__attribute__((section(".driver_table.10")))
const int driver_10 = 10;

__attribute__((section(".driver_table.20")))
const int driver_20 = 20;
```

然后 linker：

```ld
.driver_table :
{
    KEEP(*(SORT_BY_NAME(.driver_table.*)))
} > ROM
```

---

# 三十七、验证排序

```bash
objdump -s -j .driver_table driver.elf
```

以及：

```bash
less driver.map
```

观察：

```text
.driver_table.10
.driver_table.20
.driver_table.30
```

顺序。

这对于：

```text
初始化优先级
驱动编号
命令编号
构造函数
```

非常有用。

GNU ld 官方文档也专门说明了 C++ 构造函数 Section 的排序场景。([Sourceware][3])

---

# 三十八、实验 28-22：`/DISCARD/`

现在学习一个非常强力的命令：

```ld
/DISCARD/ :
{
    *(.debug_*)
}
```

它表示：

> 匹配到的 Input Section 不进入最终输出文件。

GNU ld 官方文档明确把 `/DISCARD/` 定义为特殊 Output Section 名称，用于丢弃 Input Section。([Sourceware][3])

---

# 三十九、模拟丢弃测试 Section

C：

```c
__attribute__((section(".test_data")))
const int test_data = 123;
```

linker：

```ld
/DISCARD/ :
{
    *(.test_data)
}
```

然后：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    functions.o \
    data.o \
    -o discard.elf \
    -Map=discard.map
```

验证：

```bash
readelf -SW discard.elf
```

应该找不到：

```text
.test_data
```

---

# 四十、实验 28-23：`/DISCARD/` 与 `KEEP()` 的优先级

再次强调：

```ld
KEEP(*(.test_data))
```

不能用来对抗：

```ld
/DISCARD/ :
{
    *(.test_data)
}
```

因为：

```text
KEEP
=
防止 GC 删除

/DISCARD/
=
明确告诉 linker 不要输出
```

所以：

```text
KEEP
```

解决的是：

```text
GC
```

而：

```text
/DISCARD/
```

解决的是：

```text
Explicit exclusion
```

两个层次完全不同。

---

# 四十一、实验 28-24：`EXCLUDE_FILE()`

现在我们进入一个很实用的场景。

假设：

```text
common.o
```

里有：

```text
.text
```

我们希望：

```text
common.o
```

的某些 Section 不进入某个 Output Section。

可以使用：

```ld
*(EXCLUDE_FILE(common.o) .text)
```

概念上：

```text
所有 .text
    │
    ├── common.o → 排除
    │
    └── 其他 .o → 保留
```

这在复杂的：

```text
startup
bootloader
特殊模块
```

布局里很有用。

---

# 四十二、实验 28-25：完整 Firmware linker 版本

现在把这一节的关键知识组合起来：

```ld
ENTRY(_start)

MEMORY
{
    ROM (rx) : ORIGIN = 0x00400000, LENGTH = 64K
    RAM (rw) : ORIGIN = 0x00600000, LENGTH = 64K
}

PHDRS
{
    text PT_LOAD
         FILEHDR
         PHDRS
         FLAGS(5);

    data PT_LOAD
         FLAGS(6);
}

SECTIONS
{
    . = SIZEOF_HEADERS;

    .text :
    {
        _stext = .;

        *(.text)
        *(.text.*)

        _etext = .;
    } > ROM :text

    .rodata :
    {
        _srodata = .;

        *(.rodata)
        *(.rodata.*)

        _erodata = .;
    } > ROM :text

    .firmware_header :
    {
        __firmware_header_start = .;

        KEEP(*(.firmware_header))

        __firmware_header_end = .;
    } > ROM :text

    .factory_data :
    {
        __factory_data_start = .;

        KEEP(*(.factory_data))

        __factory_data_end = .;
    } > ROM :text

    .driver_table :
    {
        __driver_table_start = .;

        KEEP(*(SORT_BY_NAME(.driver_table.*)))
        KEEP(*(.driver_table))

        __driver_table_end = .;
    } > ROM :text

    .data :
    {
        __data_start = .;

        *(.data)
        *(.data.*)

        __data_end = .;
    } > RAM AT > ROM :data

    __data_load_start = LOADADDR(.data);
    __data_size = SIZEOF(.data);

    .bss :
    {
        __bss_start = .;

        *(.bss)
        *(.bss.*)
        *(COMMON)

        __bss_end = .;
    } > RAM :data

    __bss_size = SIZEOF(.bss);

    __image_start = LOADADDR(.text);

    __image_end =
        LOADADDR(.data) + SIZEOF(.data);

    __rom_start = ORIGIN(ROM);
    __rom_end = ORIGIN(ROM) + LENGTH(ROM);

    __ram_start = ORIGIN(RAM);
    __ram_end = ORIGIN(RAM) + LENGTH(RAM);

    . = ALIGN(16);

    __heap_start = .;
    __stack_top = __ram_end;

    ASSERT(
        __bss_end <= __ram_end,
        "ERROR: RAM overflow"
    );

    ASSERT(
        __image_end <= __rom_end,
        "ERROR: ROM overflow"
    );

    ASSERT(
        __heap_start < __stack_top,
        "ERROR: RAM exhausted"
    );
}
```

---

# 四十三、实验 28-26：使用完整链接命令

```bash
ld \
    --gc-sections \
    --print-gc-sections \
    -T linker.ld \
    start.o \
    main.o \
    functions.o \
    data.o \
    -o firmware.elf \
    -Map=firmware.map
```

然后：

```bash
objcopy \
    -O binary \
    --gap-fill 0xFF \
    firmware.elf \
    firmware.bin
```

---

# 四十四、验证流程

## 1. ELF Header

```bash
readelf -h firmware.elf
```

确认：

```text
Entry point
Program Header
```

---

## 2. Section

```bash
readelf -SW firmware.elf
```

确认：

```text
.text
.rodata
.firmware_header
.factory_data
.driver_table
.data
.bss
```

---

## 3. Segment

```bash
readelf -lW firmware.elf
```

确认：

```text
LOAD R E
LOAD R W
```

---

## 4. Section → Segment

看：

```text
Section to Segment mapping
```

确认：

```text
.text
.rodata
.firmware_header
.factory_data
.driver_table
```

进入：

```text
RX PT_LOAD
```

而：

```text
.data
.bss
```

进入：

```text
RW PT_LOAD
```

---

# 四十五、实验 28-27：验证 GC

执行：

```bash
nm -n firmware.elf | grep unused
```

理想情况下：

```text
没有输出
```

而：

```bash
nm -n firmware.elf | grep used
```

应该还有：

```text
used_function
used_data
```

再：

```bash
nm -n firmware.elf | grep firmware_magic
```

应该存在。

---

# 四十六、验证 Factory Data

```bash
objdump -s -j .factory_data firmware.elf
```

应该看到：

```text
11 22 33 44 55 66 77 88
```

说明：

```text
KEEP()
```

成功保护了：

```text
.factory_data
```

---

# 四十七、验证 Driver Table

```bash
objdump -s -j .driver_table firmware.elf
```

再：

```bash
grep -A30 -B5 "\.driver_table" firmware.map
```

你可以同时确认：

```text
Section 顺序
+
地址
+
大小
```

---

# 四十八、Map 文件的三种问题定位方法

以后遇到：

```text
“为什么这个东西没了？”
```

按这个顺序：

### 第一：

```bash
objdump -h xxx.o
```

确认：

> Input Section 原本存在吗？

### 第二：

```bash
ld --gc-sections --print-gc-sections ...
```

确认：

> 是否被 GC 删除？

### 第三：

```bash
readelf -SW firmware.elf
```

确认：

> 最终 Output ELF 里到底有没有？

如果：

```text
Input 有
GC 被删除
```

问题：

```text
KEEP / GC root
```

如果：

```text
Input 有
GC 没删除
Output 没有
```

检查：

```text
/DISCARD/
Section placement
```

---

# 四十九、这一节的核心模型

现在把 `--gc-sections` 看成一张图：

```text
                 ENTRY(_start)
                       │
                       ▼
                  .text._start
                       │
                       ▼
                   .text.main
                       │
             ┌─────────┴─────────┐
             ▼                   ▼
     .text.used_function    .data.used_data
             │
             ▼
         reachable
```

而：

```text
.text.unused_function
.data.unused_data
```

没有进入这张可达图：

```text
unreachable
     │
     ▼
 garbage collection
     │
     ▼
   DELETE
```

但是：

```text
.firmware_header
.factory_data
.driver_table
```

虽然：

```text
unreachable
```

却被：

```ld
KEEP(...)
```

保护：

```text
unreachable
      │
      ▼
    KEEP
      │
      ▼
    RETAIN
```

---

# 五十、这一节还有一个非常值得记住的区别

```text
--gc-sections
```

处理的是：

# Input Section Garbage Collection

而不是简单：

```text
“删除没用的函数”
```

所以它实际上操作的是：

```text
Input Section
```

例如：

```text
.text.foo
.data.foo
.rodata.foo
.driver_table.foo
```

这也是为什么：

```bash
-ffunction-sections
-fdata-sections
```

非常重要。

它们把大块：

```text
.text
.data
```

拆成更细的：

```text
.text.foo
.text.bar
.data.foo
.data.bar
```

让 linker 能够做到：

```text
保留 foo
删除 bar
```

GCC 官方文档也明确说明，`-ffunction-sections` / `-fdata-sections` 与 linker 的 `--gc-sections` 配合，可以减少最终静态链接程序大小。([GCC][2])

---

# 五十一、实验 28 的最终知识图

```text
              *.o
               │
               ▼
        Input Sections
               │
      ┌────────┴─────────┐
      │                  │
   referenced        unreferenced
      │                  │
      ▼                  ▼
   reachable          candidate
      │                  │
      │             ┌────┴────┐
      │             │         │
      │           KEEP      no KEEP
      │             │         │
      │             ▼         ▼
      │           KEEP      DELETE
      │             │
      └──────┬──────┘
             ▼
      Output Sections
             │
             ▼
          Segments
             │
             ▼
            ELF
             │
             ▼
       firmware.bin
```

---

# 五十二、到这里，GNU ld 的“Section 管理”已经完整了一大块

目前已经掌握：

```text
实验 01～24
    基础 ELF / Section / Symbol / Memory

实验 25
    PHDRS / PT_LOAD / FILEHDR / PHDRS

实验 26
    ROM → RAM / LMA / Binary Image

实验 27
    ALIGN / FILL / AT / Firmware Padding

实验 28
    GC / KEEP / SORT / DISCARD
```

下一阶段就可以进入真正的：

# Firmware Linker Script 高级工程设计

---

# 五十三、下一节：实验 29

下一节继续：

# `PROVIDE()` + `PROVIDE_HIDDEN()` + `HIDDEN()` + `ABSOLUTE()`：Linker Symbol 的完整体系

这一节会专门解决你之前遇到过的那个问题：

```text
为什么我写了：

PROVIDE(__ram_start = ORIGIN(RAM));
PROVIDE(__ram_end = ORIGIN(RAM) + LENGTH(RAM));
PROVIDE(__stack_top = ORIGIN(RAM) + LENGTH(RAM));

但是：

nm -n memory-symbols.elf

却看不到 __ram_end？
```

我们会通过连续实验把下面几种符号逐个拆开：

```ld
foo = .;
PROVIDE(foo = .);
PROVIDE_HIDDEN(foo = .);
HIDDEN(foo = .);
ABSOLUTE(.);
ABSOLUTE(foo);
```

并使用：

```bash
nm
readelf -sW
objdump -t
readelf -SW
```

逐项验证：

```text
符号是否存在
符号是否 Local
符号是否 Global
符号是否 Hidden
符号是否 Absolute
符号是否因为未引用而没有被 PROVIDE 创建
```

最后再把这些符号组合成真正的：

```text
__rom_start
__rom_end
__ram_start
__ram_end
__stack_top
__heap_start
__image_start
__image_end
__data_load_start
__data_start
__data_end
__bss_start
__bss_end
```

**Firmware Linker Symbol API**。

这会把我们之前遇到的 `PROVIDE()` / `nm` 问题彻底讲透。 ([Sourceware][3])

[1]: https://sourceware.org/binutils/docs-2.45/ld.pdf?utm_source=chatgpt.com "The GNU linker"
[2]: https://gcc.sourceware.org/onlinedocs/gcc/Optimize-Options.html?utm_source=chatgpt.com "Optimize Options (Using the GNU Compiler Collection (GCC))"
[3]: https://sourceware.org/binutils/docs/ld.pdf?utm_source=chatgpt.com "The GNU linker"
[4]: https://sourceware.org/binutils/docs-2.37/ld.pdf?utm_source=chatgpt.com "The GNU linker"

