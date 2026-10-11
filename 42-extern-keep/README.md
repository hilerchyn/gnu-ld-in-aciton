# GNU ld 实战课程 · 实验 42
## `EXTERN()` + `-u` + `KEEP()` + `--gc-sections`：控制符号引入与 Section 回收

上一节实验 41，我们已经完成了 `OVERLAY`、`NOCROSSREFS`、`NOCROSSREFS_TO()` 和 `ASSERT()` 的综合实验。

现在进入下一阶段：**研究 GNU ld 如何决定哪些代码和数据最终进入 ELF 文件。**

本节选择一个实际工程场景：嵌入式软件的插件注册表。

假设固件包含 100 个功能模块，但启动时只需要其中一部分。如果每个模块都必须被主程序直接调用，插件架构就失去了灵活性。

更麻烦的是，当我们启用：

```bash
--gc-sections
```

之后，即使某个插件已经编译成目标文件，它的注册信息也可能被链接器回收。

因此，我们需要解决三个不同的问题：

1. **如何让编译器生成注册信息？**
2. **如何让链接器保留注册信息？**
3. **如何让链接器从静态库中引入尚未被直接引用的插件？**

这三个问题分别对应：

```text
__attribute__((used))
          │
          ▼
        KEEP()
          │
          ▼
     EXTERN() / -u
```

不过，它们的职责并不相同。本节会通过一组可复现的实验，把这三种机制彻底区分开。

官方参考资料：[GNU ld Linker Scripts 文档](https://www.sourceware.org/binutils/docs/ld/Scripts.html?utm_source=chatgpt.com)、[GNU ld Command-line Options 文档](https://sourceware.org/binutils/docs/ld/Options.html?utm_source=chatgpt.com)。

---

# 一、本节实验路线

我们从最简单的 Section 回收开始，逐步增加复杂度。

| 实验 | 主题 | 要验证的问题 |
|---|---|---|
| 42-1 | `-ffunction-sections`、`-fdata-sections` | 编译器如何拆分代码和数据 |
| 42-2 | `--gc-sections` | 未引用的函数为什么消失 |
| 42-3 | `KEEP()` | 如何保护插件注册表 |
| 42-4 | 静态库 `.a` | 为什么 `KEEP()` 不能自动引入归档成员 |
| 42-5 | `EXTERN()` | 如何强制引入静态库中的模块 |
| 42-6 | `-u symbol` | 命令行如何实现相同的符号引入效果 |
| 42-7 | 三种机制综合 | 如何构建可靠的插件注册表 |
| 42-8 | ELF 与 Map 分析 | 如何验证哪些 Section 被保留或回收 |

完成后，我们将得到一个小型的链接器控制实验环境。

---

# 二、先建立最重要的模型：三个不同阶段

很多人学习 `KEEP()` 和 `--gc-sections` 时，容易把静态库成员提取与 Section 回收混为一谈。

实际上，至少需要区分三个阶段。

```text
                源代码
                   │
                   ▼
          ① 编译器生成目标文件
                   │
                   ▼
          ② 链接器选择输入文件
             ┌─────┴─────┐
             │           │
          .o 文件      .a 静态库
             │           │
             │       按需提取成员
             │           │
             └─────┬─────┘
                   │
                   ▼
          ③ --gc-sections
                   │
           ┌───────┴────────┐
           │                │
       保留 Section      回收 Section
           │                │
       KEEP / 引用关系    无有效保留理由
           │
           ▼
        最终 ELF
```

其中：

- `__attribute__((used))` 主要影响编译阶段，要求编译器保留相应实体。
- `EXTERN()` 和 `-u symbol` 可以创建强制未定义符号，从而触发静态库成员提取。
- `KEEP()` 告诉链接器不要通过 Section 垃圾回收删除匹配的输入 Section。
- `--gc-sections` 根据入口、强制未定义符号以及重定位引用关系等判断哪些 Section 应该保留。

GNU ld 官方文档明确说明了 Section 垃圾回收的判断机制，也明确给出了使用 `KEEP()` 保护输入 Section 的方法。[Sourceware](https://sourceware.org/binutils/docs/ld.html)

**本节最重要的一句话：`KEEP()` 不负责从静态库中提取尚未被引入的成员。**

下面我们通过实际链接结果验证这一点。

---

# 三、实验目录

创建目录：

```bash
mkdir -p 42-gc-sections
cd 42-gc-sections
```

准备以下文件：

```text
42-gc-sections/
├── start.S
├── main.c
├── core.c
├── plugin_alpha.c
├── plugin_beta.c
├── linker42-gc.ld
├── linker42-keep.ld
└── linker42-extern.ld
```

我们构建两个插件：

- `plugin_alpha`：直接参与链接的目标文件。
- `plugin_beta`：放入静态库，默认不会自动提取。

这样就能分别观察 Section 回收和静态库成员提取。

本实验采用 Linux x86-64、GCC 和 GNU ld。不同架构的 ELF 地址、文件大小和部分 Section 名称可能不同，但核心机制一致。

---

# 四、实验 42-1：编写最小启动代码

创建 `start.S`：

```asm
.global _start

.section .text.start,"ax",@progbits

.type _start,@function

_start:
    call main

1:
    jmp 1b

.size _start, .-_start

.section .note.GNU-stack,"",@progbits
```

这里：

```asm
.section .text.start,"ax",@progbits
```

将入口代码放在：

```text
.text.start
```

而不是普通的 `.text`。

这样我们就可以在 linker script 中明确控制入口 Section。

同时：

```asm
.section .note.GNU-stack,"",@progbits
```

用于声明目标文件不需要可执行栈，避免常见的 GNU ld 可执行栈警告。

注意：这是一个用于研究链接行为的最小 ELF 程序，不是完整的 Linux C 运行时启动代码。我们不会直接执行生成的 ELF。

---

# 五、编写主程序

创建 `main.c`：

```c
extern void core_run(void);

int main(void)
{
    core_run();

    return 0;
}
```

主程序只调用：

```c
core_run()
```

它不会直接引用插件注册表，也不会调用插件函数。

这正是我们想要的实验条件。

如果主程序直接调用：

```c
plugin_alpha();
```

链接器就可以沿着重定位引用关系保留对应函数。

但在真实的插件系统中，插件往往是通过注册表发现的，并不需要主程序在源代码中直接引用每个插件。

因此，我们需要一种不依赖普通函数调用关系的保留机制。

---

# 六、编写核心功能模块

创建 `core.c`：

```c
volatile unsigned long core_state;

__attribute__((noinline))
static void helper_used(void)
{
    core_state = 0x12345678UL;
}

void core_run(void)
{
    helper_used();
}

__attribute__((noinline, used))
void core_unused(void)
{
    core_state = 0xDEADBEEFUL;
}
```

这里有两个函数。

第一个：

```c
core_run()
```

由 `main()` 调用，因此必须保留。

第二个：

```c
core_unused()
```

没有任何调用者。

虽然我们使用了：

```c
__attribute__((used))
```

要求编译器生成它，但这并不意味着 GNU ld 必须在启用 `--gc-sections` 时保留它。

这就是我们要验证的第一个知识点：

> 编译器保留某个函数，不等于链接器必须保留这个函数。

`used` 解决的是编译阶段的问题，而 `--gc-sections` 工作在链接阶段。

---

# 七、创建插件注册表

## 7.1 编写 `plugin_alpha.c`

```c
struct plugin_desc {
    const char *name;
    void (*run)(void);
};

static volatile unsigned long alpha_count;

__attribute__((noinline))
static void alpha_run(void)
{
    alpha_count++;
}

/*
 * 编译器必须生成这条注册信息。
 *
 * 但在 --gc-sections 下，
 * 它仍然可能被 GNU ld 回收。
 */
const struct plugin_desc plugin_alpha_desc
    __attribute__((section(".plugin_registry"), used)) = {
        "alpha",
        alpha_run
    };
```

这里最重要的是：

```c
__attribute__((section(".plugin_registry"), used))
```

它告诉 GCC 将注册信息放入：

```text
.plugin_registry
```

同时要求编译器保留这个对象。

但是，如果链接器启用了：

```bash
--gc-sections
```

而注册信息又没有任何引用者，那么它仍可能被回收。

## 7.2 这条注册信息包含什么？

在 x86-64 环境中：

```c
struct plugin_desc {
    const char *name;
    void (*run)(void);
};
```

通常由两个 8 字节指针组成。

因此，一个注册表条目通常占用：

```text
8 + 8 = 16 字节
```

即：

```text
0x10
```

但实际大小仍应通过：

```bash
readelf -SW plugin_alpha.o
```

确认，不要把某个平台的数据结构布局直接套用到其他架构。

## 7.3 为什么注册表能影响函数的保留？

因为：

```text
.plugin_registry
       │
       ├── 指向字符串 "alpha"
       │
       └── 指向 alpha_run()
```

注册表中的指针会产生重定位关系。

当 `.plugin_registry` 被保留时，GNU ld 可以沿着这些引用继续保留相关目标 Section。

反过来，如果 `.plugin_registry` 本身被回收，那么仅仅因为 `alpha_run()` 的地址曾经出现在这条注册信息中，并不足以让它继续存活。

---

# 八、编写静态库插件

创建 `plugin_beta.c`：

```c
struct plugin_desc {
    const char *name;
    void (*run)(void);
};

static volatile unsigned long beta_count;

__attribute__((noinline))
static void beta_run(void)
{
    beta_count++;
}

/*
 * 提供一个公开 API。
 *
 * EXTERN(plugin_beta_api) 或 -u plugin_beta_api
 * 可以通过这个符号触发静态库成员提取。
 */
__attribute__((noinline, used))
void plugin_beta_api(void)
{
    beta_run();
}

/*
 * 插件注册信息。
 */
const struct plugin_desc plugin_beta_desc
    __attribute__((section(".plugin_registry"), used)) = {
        "beta",
        beta_run
    };
```

这里有两个值得注意的实体：

```text
plugin_beta_api
plugin_beta_desc
```

它们的职责不同。

`plugin_beta_api` 是一个公开函数，可以作为强制引入静态库成员的目标符号。

`plugin_beta_desc` 是注册表条目。

我们会让链接器通过：

```text
plugin_beta_api
```

提取 `plugin_beta.o`，再观察：

```text
.plugin_registry
```

是否会被垃圾回收。

这样就能把静态库成员提取与 Section 保留两个过程分开验证。

---

# 九、实验 42-1：编译目标文件

设置编译参数：

```bash
CFLAGS="-O0 \
-ffreestanding \
-fno-pie \
-fno-pic \
-fno-stack-protector \
-fno-asynchronous-unwind-tables \
-fno-unwind-tables \
-ffunction-sections \
-fdata-sections"
```

编译启动代码：

```bash
gcc $CFLAGS -c start.S -o start.o
```

编译主程序：

```bash
gcc $CFLAGS -c main.c -o main.o
```

编译核心模块：

```bash
gcc $CFLAGS -c core.c -o core.o
```

编译插件：

```bash
gcc $CFLAGS -c plugin_alpha.c -o plugin_alpha.o
gcc $CFLAGS -c plugin_beta.c -o plugin_beta.o
```

这里最重要的两个编译参数是：

```bash
-ffunction-sections
-fdata-sections
```

它们分别让编译器尽可能将每个函数、每个数据对象放入独立的输入 Section。

例如，`core.c` 可能产生：

```text
.text.helper_used
.text.core_run
.text.core_unused

.bss.core_state
```

而 `plugin_alpha.c` 可能产生：

```text
.text.alpha_run
.bss.alpha_count
.plugin_registry
```

具体名称取决于编译器和源代码，但独立 Section 的基本思想不变。

现在检查：

```bash
readelf -SW core.o
```

然后：

```bash
objdump -h core.o
```

再检查插件：

```bash
readelf -SW plugin_alpha.o
```

```bash
objdump -h plugin_alpha.o
```

你应该能看到各个输入 Section 的大小、属性和对齐信息。

---

# 十、建立静态库 `libplugins.a`

执行：

```bash
ar rcs libplugins.a plugin_beta.o
```

检查静态库：

```bash
ar t libplugins.a
```

预期：

```text
plugin_beta.o
```

再执行：

```bash
nm -A libplugins.a
```

重点查找：

```text
plugin_beta_api
plugin_beta_desc
```

到这里，我们已经完成了三个不同层次的对象：

```text
plugin_alpha.o
    │
    └── 直接提供给链接器

libplugins.a
    │
    └── 内含 plugin_beta.o
            │
            ├── plugin_beta_api
            └── plugin_beta_desc
```

**静态库成员存在于 `.a` 文件中，并不代表它已经进入最终 ELF。**

这一点是下一组实验的关键。

---

# 十一、实验 42-2：编写基础 linker script

创建 `linker42-gc.ld`：

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

    .rodata :
    {
        *(.rodata .rodata.*)
    }

    /*
     * 基础版本：不使用 KEEP()
     */
    .plugin_registry :
    {
        __plugin_registry_start = .;

        *(.plugin_registry)

        __plugin_registry_end = .;
    }

    .data :
    {
        *(.data .data.*)
    }

    .bss (NOLOAD) :
    {
        *(.bss .bss.*)
        *(COMMON)
    }

    /DISCARD/ :
    {
        *(.comment)
        *(.eh_frame*)
    }
}
```

这里故意没有使用：

```ld
KEEP(*(.plugin_registry))
```

因为我们要先观察没有 `KEEP()` 时会发生什么。

同时定义：

```ld
__plugin_registry_start
__plugin_registry_end
```

用于后续分析注册表的地址范围。

如果注册表为空，这两个符号可能具有相同的地址。

因此，不能只看这两个符号是否存在，还要检查它们之间的差值。

---

# 十二、实验 42-2：启用 `--gc-sections`

现在链接：

```bash
ld \
    -T linker42-gc.ld \
    --gc-sections \
    --print-gc-sections \
    -Map=gc.map \
    -o gc.elf \
    start.o \
    main.o \
    core.o \
    plugin_alpha.o \
    2>gc-discard.log
```

这条命令有四个重点：

```text
-T linker42-gc.ld
    使用自定义链接脚本

--gc-sections
    启用输入 Section 垃圾回收

--print-gc-sections
    打印被回收的 Section

-Map=gc.map
    生成链接映射文件
```

GNU ld 的 `--print-gc-sections` 会将被回收 Section 的信息输出到标准错误，因此我们将其保存到了：

```text
gc-discard.log
```

官方文档明确说明，这个选项只有在启用 `--gc-sections` 时才会生效。[Sourceware](https://sourceware.org/binutils/docs/ld.html)

## 12.1 查看被回收的 Section

执行：

```bash
cat gc-discard.log
```

重点搜索：

```text
.plugin_registry
.text.alpha_run
.text.core_unused
```

在符合本实验编译条件的常见 GNU/Linux GNU ld 环境中，这些未被有效引用的 Section 会成为垃圾回收候选。

但不要机械地认为这三个名字一定全部出现在日志里。

实际结果取决于目标文件的具体 Section 布局、链接器版本，以及其他 Section 是否存在有效引用。

## 12.2 为什么 `core_run()` 不会被回收？

因为：

```text
_start
  │
  ▼
main
  │
  ▼
core_run
  │
  ▼
helper_used
```

入口符号 `_start` 所在的 Section 是重要的 GC 根。

随后，链接器沿着重定位引用关系保留被使用的 Section。

而：

```text
core_unused
```

没有被引用，即使编译器已经生成它，也可能被链接器回收。

## 12.3 为什么插件注册表可能被回收？

因为主程序没有引用：

```text
plugin_alpha_desc
```

注册表又没有使用 `KEEP()` 保护。

因此，它可能不属于链接器必须保留的 Section 集合。

当注册表被回收后：

```text
.plugin_registry
        │
        └── 对 alpha_run 的引用不再形成有效保留链
```

于是 `alpha_run` 及其独有的数据也可能被回收。

---

# 十三、使用 `readelf` 验证第一次链接

执行：

```bash
readelf -SW gc.elf
```

查找：

```text
.plugin_registry
```

再执行：

```bash
readelf -sW gc.elf
```

搜索：

```bash
readelf -sW gc.elf | \
grep -E 'plugin_alpha_desc|alpha_run|core_unused|core_run'
```

也可以使用：

```bash
nm -n gc.elf | \
grep -E 'plugin_alpha_desc|alpha_run|core_unused|core_run'
```

重点观察：

- `core_run` 是否存在。
- `core_unused` 是否被回收。
- `plugin_alpha_desc` 是否仍有有效的输出 Section。
- `.plugin_registry` 是否有实际内容。

这里有个细节：符号表中是否还显示某个已回收符号，可能受链接器版本和输出符号表处理方式影响。

所以，**判断 Section 是否真正保留，应优先检查 Section 表、符号所属 Section，以及 `--print-gc-sections` 的结果，而不是只根据 `nm` 中有没有字符串作结论。**

---

# 十四、实验 42-3：用 `KEEP()` 保护注册表

现在创建：

```text
linker42-keep.ld
```

内容与 `linker42-gc.ld` 相同，唯一关键变化是：

```ld
.plugin_registry :
{
    __plugin_registry_start = .;

    KEEP(*(.plugin_registry))

    __plugin_registry_end = .;
}
```

完整理解这条语句：

```ld
KEEP(*(.plugin_registry))
```

它表示：

> 将匹配 `.plugin_registry` 的输入 Section 放入该输出 Section，并且不要通过 Section 垃圾回收删除这些输入 Section。

这不是关闭整个程序的垃圾回收。

其他没有被引用、也没有被 `KEEP()` 保护的 Section，仍然可以被回收。

## 14.1 重新链接

执行：

```bash
ld \
    -T linker42-keep.ld \
    --gc-sections \
    --print-gc-sections \
    -Map=keep.map \
    -o keep.elf \
    start.o \
    main.o \
    core.o \
    plugin_alpha.o \
    2>keep-discard.log
```

## 14.2 检查注册表

执行：

```bash
readelf -SW keep.elf
```

搜索：

```text
.plugin_registry
```

然后：

```bash
nm -n keep.elf | \
grep -E 'plugin_alpha_desc|alpha_run|core_unused'
```

预期的关键变化是：

```text
plugin_alpha_desc
        │
        ▼
.plugin_registry 被 KEEP() 保留
        │
        ▼
alpha_run 的引用仍然有效
        │
        ▼
alpha_run 所在 Section 被保留
```

如果注册表引用的字符串和数据也没有其他回收原因，那么它们也会因为重定位引用关系被保留。

与此同时：

```text
core_unused
```

仍然可能被回收。

这说明：

**`KEEP()` 只保护匹配的 Section，不会让整个 ELF 的所有代码都免于垃圾回收。**

---

# 十五、实验 42-4：验证 `KEEP()` 与静态库提取无关

现在进入本节最重要的实验。

执行：

```bash
ld \
    -T linker42-keep.ld \
    --gc-sections \
    --print-gc-sections \
    -Map=archive-no-pull.map \
    -o archive-no-pull.elf \
    start.o \
    main.o \
    core.o \
    libplugins.a \
    2>archive-no-pull.log
```

注意，命令行里有：

```text
libplugins.a
```

而 linker script 里也有：

```ld
KEEP(*(.plugin_registry))
```

你可能会以为：

> 既然静态库里有 `.plugin_registry`，`KEEP()` 又要求保留这个 Section，那么插件应该进入 ELF。

**这通常是错误的。**

原因是静态库成员提取与 Section 垃圾回收是两个不同的阶段。

GNU ld 处理静态库时，通常只提取能够满足当前未解析符号需求的归档成员。

而我们的主程序没有引用：

```text
plugin_beta_api
```

也没有引用：

```text
plugin_beta_desc
```

所以 `plugin_beta.o` 通常不会从 `libplugins.a` 中提取。

此时，链接器根本没有得到该成员中的 `.plugin_registry` 输入 Section。

没有进入链接过程的 Section，自然无法被 `KEEP()` 保留。

## 15.1 如何证明？

执行：

```bash
nm -n archive-no-pull.elf | \
grep -E 'plugin_beta_api|plugin_beta_desc|beta_run'
```

再查看：

```bash
grep -n 'libplugins.a' archive-no-pull.map
```

你应该重点检查：

- `plugin_beta_api` 是否进入最终符号表。
- `plugin_beta_desc` 是否进入最终符号表。
- Map 文件是否显示 `libplugins.a(plugin_beta.o)` 被实际提取。

不要只因为 Map 文件里出现了字符串 `libplugins.a` 就判断成员已经提取。还要查看它所在的具体 Map 条目。

**本实验结论：`KEEP()` 不能代替静态库成员提取机制。**

---

# 十六、实验 42-5：使用 `EXTERN()` 强制引入静态库成员

现在创建：

```text
linker42-extern.ld
```

我们在基础脚本的顶层增加：

```ld
EXTERN(plugin_beta_api)
```

例如：

```ld
ENTRY(_start)

EXTERN(plugin_beta_api)

SECTIONS
{
    . = 0x00400000;

    .text :
    {
        *(.text.start)
        *(.text .text.*)
    }

    .rodata :
    {
        *(.rodata .rodata.*)
    }

    .plugin_registry :
    {
        __plugin_registry_start = .;

        KEEP(*(.plugin_registry))

        __plugin_registry_end = .;
    }

    .data :
    {
        *(.data .data.*)
    }

    .bss (NOLOAD) :
    {
        *(.bss .bss.*)
        *(COMMON)
    }

    /DISCARD/ :
    {
        *(.comment)
        *(.eh_frame*)
    }
}
```

这里：

```ld
EXTERN(plugin_beta_api)
```

相当于告诉链接器：

> 将 `plugin_beta_api` 作为需要解析的未定义符号。

当链接器扫描：

```text
libplugins.a
```

时，就可以提取包含该符号定义的：

```text
plugin_beta.o
```

GNU ld 官方文档说明，`EXTERN` 命令与命令行选项 `-u` 等价。[Sourceware](https://sourceware.org/binutils/docs/ld/Options.html)

## 16.1 重新链接

执行：

```bash
ld \
    -T linker42-extern.ld \
    --gc-sections \
    --print-gc-sections \
    -Map=extern.map \
    -o extern.elf \
    start.o \
    main.o \
    core.o \
    libplugins.a \
    2>extern-discard.log
```

## 16.2 检查静态库成员是否被提取

执行：

```bash
grep -n -A10 -B5 'libplugins.a' extern.map
```

再执行：

```bash
nm -n extern.elf | \
grep -E 'plugin_beta_api|plugin_beta_desc|beta_run'
```

预期的关键变化：

```text
EXTERN(plugin_beta_api)
          │
          ▼
plugin_beta_api 成为待解析符号
          │
          ▼
从 libplugins.a 提取 plugin_beta.o
          │
          ▼
plugin_beta_api 所在 Section 被保留
```

由于 `plugin_beta_api()` 调用了 `beta_run()`，后者以及它引用的数据也可能通过重定位关系被保留。

但是，这还不能说明插件注册表为什么被保留。

我们马上验证这一点。

---

# 十七、实验 42-6：把 `KEEP()` 与 `EXTERN()` 分开验证

这一节是本课程最值得反复做的部分。

我们分别构建两个版本：

1. 使用 `EXTERN()`，但不使用 `KEEP()`。
2. 同时使用 `EXTERN()` 和 `KEEP()`。

这样可以准确区分两者的作用。

## 17.1 版本 A：有 `EXTERN()`，没有 `KEEP()`

复制基础脚本：

```bash
cp linker42-gc.ld linker42-extern-nokeep.ld
```

在 `ENTRY(_start)` 后增加：

```ld
EXTERN(plugin_beta_api)
```

保持注册表区域不变：

```ld
.plugin_registry :
{
    __plugin_registry_start = .;

    *(.plugin_registry)

    __plugin_registry_end = .;
}
```

链接：

```bash
ld \
    -T linker42-extern-nokeep.ld \
    --gc-sections \
    --print-gc-sections \
    -Map=extern-nokeep.map \
    -o extern-nokeep.elf \
    start.o \
    main.o \
    core.o \
    libplugins.a \
    2>extern-nokeep.log
```

在这个版本中：

- `EXTERN(plugin_beta_api)` 促使链接器提取 `plugin_beta.o`。
- `plugin_beta_api` 所在 Section 因为强制符号需求而被保留。
- `beta_run` 因为被引用而被保留。
- `plugin_beta_desc` 所在的 `.plugin_registry` 仍然可能被垃圾回收。

因此，检查：

```bash
readelf -SW extern-nokeep.elf
```

以及：

```bash
nm -n extern-nokeep.elf | \
grep -E 'plugin_beta_api|plugin_beta_desc|beta_run'
```

重点看注册表是否真正有内容。

如果 `.plugin_registry` 被回收，那么 `plugin_beta_desc` 就不会作为有效的注册表条目进入最终 ELF。

## 17.2 版本 B：同时使用 `EXTERN()` 和 `KEEP()`

现在使用：

```ld
EXTERN(plugin_beta_api)
```

并将注册表区域改成：

```ld
.plugin_registry :
{
    __plugin_registry_start = .;

    KEEP(*(.plugin_registry))

    __plugin_registry_end = .;
}
```

然后链接：

```bash
ld \
    -T linker42-extern.ld \
    --gc-sections \
    --print-gc-sections \
    -Map=extern-keep.map \
    -o extern-keep.elf \
    start.o \
    main.o \
    core.o \
    libplugins.a \
    2>extern-keep.log
```

此时：

```text
EXTERN(plugin_beta_api)
          │
          ▼
提取 plugin_beta.o
          │
          ▼
plugin_beta_api 被保留
          │
          ▼
KEEP(*(.plugin_registry))
          │
          ▼
plugin_beta_desc 被保留
```

这就是两个机制组合后的效果。

## 17.3 一个必须理解的细节

本实验使用 `EXTERN(plugin_beta_api)` 提取归档成员，而不是直接强制引入 `plugin_beta_desc`。

因此，我们可以观察到：

- `EXTERN()` 解决归档成员的引入问题。
- `KEEP()` 解决已进入链接过程的注册表 Section 的保留问题。

如果改成：

```ld
EXTERN(plugin_beta_desc)
```

那么包含该符号的输入 Section 本身也会成为保留根。

在这种情况下，即使没有 `KEEP()`，对应注册信息也可能因为强制符号需求而保留。

因此，不能简单认为每次都必须同时使用 `EXTERN()` 和 `KEEP()`。

**实际工程中，是否需要同时使用它们，取决于你要强制引入哪个符号，以及注册表 Section 是否还需要独立于该符号被保留。**

---

# 十八、实验 42-7：使用 `-u symbol` 实现相同效果

现在把 linker script 中的：

```ld
EXTERN(plugin_beta_api)
```

移除。

保留：

```ld
KEEP(*(.plugin_registry))
```

然后通过命令行指定：

```bash
-u plugin_beta_api
```

完整命令：

```bash
ld \
    -T linker42-keep.ld \
    -u plugin_beta_api \
    --gc-sections \
    --print-gc-sections \
    -Map=undefined-symbol.map \
    -o undefined-symbol.elf \
    start.o \
    main.o \
    core.o \
    libplugins.a \
    2>undefined-symbol.log
```

再检查：

```bash
nm -n undefined-symbol.elf | \
grep -E 'plugin_beta_api|plugin_beta_desc|beta_run'
```

以及：

```bash
grep -n -A10 -B5 'libplugins.a' undefined-symbol.map
```

你应该观察到与使用：

```ld
EXTERN(plugin_beta_api)
```

相同的核心行为。

GNU ld 官方文档明确说明：

```bash
-u symbol
```

与 linker script 中的：

```ld
EXTERN(symbol)
```

等价。[Sourceware](https://sourceware.org/binutils/docs/ld/Options.html)

## 18.1 两种写法如何选择？

| 方式 | 示例 | 适用场景 |
|---|---|---|
| `EXTERN()` | `EXTERN(plugin_beta_api)` | 依赖规则由 linker script 管理 |
| `-u` | `ld -u plugin_beta_api` | 构建命令临时控制符号引入 |
| `KEEP()` | `KEEP(*(.plugin_registry))` | 保护已经参与链接的注册表 Section |
| `--gc-sections` | `ld --gc-sections` | 自动回收未使用的输入 Section |

如果某个固件必须始终引入指定插件，可以考虑把 `EXTERN()` 写入受版本控制的 linker script。

如果只是临时测试，也可以直接使用 `-u`。

---

# 十九、实验 42-8：通过 `readelf` 验证最终 ELF

现在我们拥有几个不同的结果：

```text
gc.elf
keep.elf
archive-no-pull.elf
extern-nokeep.elf
extern.elf
undefined-symbol.elf
```

接下来统一进行 ELF 检查。

## 19.1 检查 Section 表

执行：

```bash
readelf -SW gc.elf
```

然后：

```bash
readelf -SW keep.elf
```

再：

```bash
readelf -SW extern-nokeep.elf
```

最后：

```bash
readelf -SW extern.elf
```

重点观察：

```text
.plugin_registry
.text
.rodata
.data
.bss
```

需要回答：

- `.plugin_registry` 是否存在实际内容？
- `plugin_alpha_desc` 是否进入最终 ELF？
- `plugin_beta_desc` 是否进入最终 ELF？
- `alpha_run`、`beta_run` 是否保留？

对于 Section 是否被回收，建议结合 `readelf -sW` 和垃圾回收日志判断，不要只看 Section 名称。

## 19.2 检查符号表

执行：

```bash
readelf -sW extern.elf | \
grep -E 'plugin_alpha_desc|plugin_beta_desc|plugin_beta_api|alpha_run|beta_run'
```

你应该能看到被保留的相关符号。

注意，静态函数：

```c
static void beta_run(void)
```

是局部符号。

因此，在 `nm` 输出中它通常会以小写的 `t` 等类型标记出现，而公开函数 `plugin_beta_api` 通常显示为全局符号。

符号类型的具体显示仍应以当前目标平台的工具输出为准。

## 19.3 检查重定位关系

执行：

```bash
objdump -dr plugin_alpha.o
```

以及：

```bash
readelf -rW plugin_alpha.o
```

重点查看 `.plugin_registry` 相关的重定位信息。

这有助于理解：

```text
.plugin_registry
        │
        └── 引用 alpha_run
```

为什么在注册表被保留时，`alpha_run` 也会继续保留。

---

# 二十、实验 42-9：使用 `objdump` 检查 Section 大小

执行：

```bash
objdump -h gc.elf
objdump -h keep.elf
objdump -h extern-nokeep.elf
objdump -h extern.elf
```

重点记录：

```text
Size
VMA
LMA
Algn
```

这里我们主要关注 `Size`。

例如，在典型 x86-64 环境中，一个注册表条目通常占用 `0x10` 字节。

如果：

```text
.plugin_registry
```

包含一个注册表条目，大小可能是：

```text
0x10
```

如果没有任何条目，则可能变成空 Section，或者该输出 Section 不出现在最终文件中。

具体结果取决于 linker script、GNU ld 版本及最终链接内容。

## 20.1 为什么不能只看 ELF 文件总大小？

假设：

```text
gc.elf
```

和：

```text
keep.elf
```

的文件大小只相差几十字节。

这并不意味着 `KEEP()` 没有起作用。

因为 `KEEP()` 影响的是输入 Section 是否被保留，而 ELF 文件总大小还受到：

- Program Header。
- Section 对齐。
- 其他输入 Section。
- 符号表。
- 文件偏移布局。

等因素影响。

因此，验证时应优先检查：

```bash
readelf -SW
```

以及：

```bash
nm -n
```

而不是仅比较：

```bash
ls -lh
```

---

# 二十一、实验 42-10：Map 文件分析

这一部分非常重要。

GNU ld 的 Map 文件可以告诉我们输入 Section 如何映射到输出 Section，以及链接器是否报告了被丢弃的输入 Section。

官方手册也建议，当不清楚输入 Section 被放到了哪里时，使用 Map 文件检查映射结果。[Sourceware](https://sourceware.org/binutils/docs/ld.html?utm_source=chatgpt.com)

## 21.1 检查未使用 Section

执行：

```bash
grep -n -A30 \
'Discarded input sections' \
gc.map
```

如果当前版本的 Map 文件包含该区域，你可能看到类似：

```text
Discarded input sections

.text.core_unused
.text.alpha_run
.plugin_registry
```

这只是结构示意，实际名称和顺序应以你自己的输出为准。

## 21.2 检查注册表

执行：

```bash
grep -n -A15 -B5 \
'\.plugin_registry' \
keep.map
```

然后：

```bash
grep -n -A15 -B5 \
'\.plugin_registry' \
extern.map
```

重点记录：

```text
输出 Section 起始地址
输入 Section 名称
输入对象文件名
Section 大小
```

## 21.3 检查静态库成员提取

执行：

```bash
grep -n -A15 -B5 \
'plugin_beta.o' \
extern.map
```

如果 `plugin_beta.o` 已经被提取并参与链接，Map 文件通常会出现相关的输入文件和 Section 条目。

再与：

```bash
grep -n -A15 -B5 \
'plugin_beta.o' \
archive-no-pull.map
```

比较。

这两份 Map 文件能帮助你验证：

```text
KEEP()
    │
    └── 不能单独让静态库成员被提取

EXTERN(plugin_beta_api)
    │
    └── 促使链接器引入包含该符号的归档成员
```

## 21.4 检查注册表边界

执行：

```bash
nm -n extern.elf | \
grep '__plugin_registry_'
```

重点关注：

```text
__plugin_registry_start
__plugin_registry_end
```

然后计算：

```text
registry_size =
    __plugin_registry_end
    -
    __plugin_registry_start
```

在 Linux x86-64 环境中，可以用 shell 的十六进制算术计算：

```bash
start=$(
    nm -n extern.elf |
    awk '$3=="__plugin_registry_start" {print "0x"$1}'
)

end=$(
    nm -n extern.elf |
    awk '$3=="__plugin_registry_end" {print "0x"$1}'
)

if [ -n "$start" ] && [ -n "$end" ]; then
    printf 'registry size = 0x%x\n' \
        "$((end - start))"
fi
```

如果注册表中只有一个 16 字节条目，通常可以观察到：

```text
registry size = 0x10
```

但这只是当前示例的典型结果，不是所有架构都固定如此。

---

# 二十二、三个最容易混淆的概念

现在把本节的关键机制放在一起比较。

| 机制 | 主要作用 | 能否阻止 Section GC | 能否触发静态库成员提取 |
|---|---|---|---|
| `__attribute__((used))` | 要求编译器生成相应实体 | 不保证 | 否 |
| `KEEP()` | 保护匹配的输入 Section | 能 | 否 |
| `EXTERN(symbol)` | 强制引入未定义符号 | 符号所在 Section 会成为重要的保留根 | 能 |
| `-u symbol` | 与 `EXTERN()` 等价 | 符号所在 Section 会成为重要的保留根 | 能 |
| `--gc-sections` | 回收未使用的输入 Section | 本身就是回收机制 | 不负责提取归档成员 |

这里最容易犯的错误是：

```c
__attribute__((used))
```

之后，就以为注册表一定会进入最终 ELF。

事实上，编译器与链接器是两个不同的阶段。

同样：

```ld
KEEP(*(.plugin_registry))
```

也不意味着所有静态库中的插件注册表都会自动出现。

因为链接器必须先获得相应的输入 Section，才能决定是否回收它。

---

# 二十三、实际工程中应该如何使用？

假设我们正在设计一个嵌入式插件系统。

我们希望：

1. 所有参与链接的插件注册表都能被保留。
2. 没有被引入的静态库成员不必自动进入固件。
3. 某些关键插件可以被强制引入。
4. 不再使用的普通函数和数据可以被回收。

那么一种常见的设计是：

```ld
.plugin_registry :
{
    __plugin_registry_start = .;

    KEEP(*(SORT_BY_NAME(.plugin_registry.*)))
    KEEP(*(.plugin_registry))

    __plugin_registry_end = .;
}
```

这段脚本既支持：

```text
.plugin_registry
```

也支持：

```text
.plugin_registry.audio
.plugin_registry.storage
.plugin_registry.network
```

这样的命名约定。

但请注意，`SORT_BY_NAME()` 只控制匹配 Section 的排序，并不自动保证运行时插件初始化顺序符合业务依赖。

如果某些插件必须强制引入，可以在 linker script 中使用：

```ld
EXTERN(plugin_audio_init)
EXTERN(plugin_storage_init)
```

或者在链接命令中使用：

```bash
-u plugin_audio_init
-u plugin_storage_init
```

这样可以明确指定需要进入链接过程的符号。

对于使用静态库的插件系统，这一点尤其重要。

**最终设计原则是：先解决模块引入，再解决 Section 保留，最后验证 ELF 结果。**

---

# 二十四、本节综合实验验收

建议按下面的顺序重新做一遍。

### 第一步：检查输入目标文件

```bash
readelf -SW plugin_alpha.o
objdump -h plugin_alpha.o
readelf -rW plugin_alpha.o
```

确认：

```text
.plugin_registry
.text.alpha_run
```

等 Section 存在。

### 第二步：启用 Section GC

```bash
ld \
    -T linker42-gc.ld \
    --gc-sections \
    --print-gc-sections \
    -Map=gc.map \
    -o gc.elf \
    start.o main.o core.o plugin_alpha.o \
    2>gc-discard.log
```

确认未使用 Section 被回收。

### 第三步：添加 `KEEP()`

```bash
ld \
    -T linker42-keep.ld \
    --gc-sections \
    --print-gc-sections \
    -Map=keep.map \
    -o keep.elf \
    start.o main.o core.o plugin_alpha.o \
    2>keep-discard.log
```

确认注册表被保留，且不相关的函数仍可被回收。

### 第四步：验证静态库不会被 `KEEP()` 自动提取

```bash
ld \
    -T linker42-keep.ld \
    --gc-sections \
    -Map=archive-no-pull.map \
    -o archive-no-pull.elf \
    start.o main.o core.o libplugins.a
```

确认没有有效引用时，静态库成员通常不会被引入。

### 第五步：添加 `EXTERN()`

```bash
ld \
    -T linker42-extern.ld \
    --gc-sections \
    -Map=extern.map \
    -o extern.elf \
    start.o main.o core.o libplugins.a
```

确认：

```text
plugin_beta.o
```

被提取。

### 第六步：使用 `-u`

```bash
ld \
    -T linker42-keep.ld \
    -u plugin_beta_api \
    --gc-sections \
    -Map=undefined-symbol.map \
    -o undefined-symbol.elf \
    start.o main.o core.o libplugins.a
```

确认它与 `EXTERN(plugin_beta_api)` 的核心效果一致。

### 第七步：完成最终验证

```bash
readelf -SW extern.elf
readelf -sW extern.elf
readelf -lW extern.elf

objdump -h extern.elf
objdump -t extern.elf

nm -n extern.elf

grep -n -A20 -B5 \
'plugin_beta.o' \
extern.map
```

完成这一步，你就可以根据 ELF 文件与 Map 文件解释每个插件的去留，而不需要依赖猜测。

---

# 二十五、实验 42 的最终知识地图

```text
                   GNU ld
                      │
                      ▼
              输入目标文件与静态库
                      │
          ┌───────────┴───────────┐
          │                       │
          ▼                       ▼
      直接 .o 文件             .a 静态库
          │                       │
          │                 符号解析与提取
          │                       │
          │                  EXTERN() / -u
          │                       │
          └───────────┬───────────┘
                      │
                      ▼
                输入 Section 集合
                      │
                      ▼
                --gc-sections
                      │
          ┌───────────┴───────────┐
          │                       │
          ▼                       ▼
      有效引用链              无保留理由
          │                       │
          ▼                       ▼
       保留 Section           回收 Section
          ▲
          │
          └── KEEP()
                      │
                      ▼
                   最终 ELF
                      │
          ┌───────────┼───────────┐
          │           │           │
          ▼           ▼           ▼
      readelf      objdump       Map
```

这一节最重要的三个结论：

**第一，`used` 不等于 `KEEP()`。**

编译器生成了某个对象，不代表链接器必须保留它。

**第二，`KEEP()` 不等于 `EXTERN()`。**

前者保护输入 Section，后者强制引入符号，并可能触发静态库成员提取。

**第三，`EXTERN()` 不等于无条件保留所有注册表。**

它主要围绕指定符号起作用。其他已经引入的注册表 Section 是否需要额外保护，仍然取决于引用关系和 `KEEP()` 等规则。

官方参考：[GNU ld `KEEP()` 与 Section Garbage Collection 文档](https://sourceware.org/binutils/docs/ld.html?utm_source=chatgpt.com)、[GNU ld `-u` / `EXTERN()` 选项文档](https://sourceware.org/binutils/docs/ld/Options.html?utm_source=chatgpt.com)。

---

# 二十六、下一节：实验 43

下一节继续沿着这条路线，进入：

## 实验 43 —— `SORT_BY_NAME()` + `SORT_BY_ALIGNMENT()` + `EXCLUDE_FILE()`：输入 Section 的排序、筛选与布局优化

实验 42 已经解决了：

```text
哪些 Section 应该被保留？
哪些 Section 可以被回收？
如何强制引入静态库模块？
```

实验 43 将进一步解决：

> 当多个目标文件向同一个输出 Section 提供内容时，GNU ld 如何决定它们的排列顺序？

我们会使用一组独立的输入 Section，研究：

1. `SORT_BY_NAME()` 如何按名称排序。
2. `SORT_BY_ALIGNMENT()` 如何按对齐需求排序。
3. `EXCLUDE_FILE()` 如何排除特定目标文件。
4. 输入 Section 的顺序如何影响填充和最终布局。
5. 如何通过 `readelf -SW`、`objdump -h` 和 Map 文件验证排序结果。
6. 如何把这些机制用于固件初始化表、插件注册表和特定内存区域的布局。

下一节仍然采用递进式实验：先观察默认顺序，再加入一个控制机制，最后将排序、筛选与 `--gc-sections` 组合起来，分析它们如何共同影响最终 ELF 文件。
