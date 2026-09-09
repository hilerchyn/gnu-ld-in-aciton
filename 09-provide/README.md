# GNU ld 实战课程 · 实验 09

## `PROVIDE()`、`PROVIDE_HIDDEN()`：让 linker script 主动“造”符号

上一节我们解决了：

```text
--gc-sections
        ↓
删除无用 Input Section
        ↓
KEEP()
        ↓
强制保留
```

现在进入 linker script 的另一个核心能力：

> **linker script 不仅能决定 Section 放在哪里，还能直接创建 ELF Symbol。**

这一节我们专门研究：

```ld
foo = .;
PROVIDE(foo = .);
PROVIDE_HIDDEN(foo = .);
```

以及：

```ld
ORIGIN(RAM)
LENGTH(RAM)
```

最终我们会让 linker 自动产生：

```text
__image_start
__image_end
__stack_top
__stack_limit
```

这些符号以后会直接用于：

```text
startup.S
bootloader
链接检查
栈初始化
.data/.bss 初始化
固件边界计算
```

GNU ld 当前手册仍明确区分 `PROVIDE` 与 `PROVIDE_HIDDEN`：`PROVIDE` 只在符号没有其他定义/引用条件满足时提供定义，而 ELF 目标下 `PROVIDE_HIDDEN` 提供的符号会被标记为 hidden。([Sourceware][1])

---

# 一、先建立一个非常重要的概念

以前我们写过：

```ld
_sdata = .;
```

这实际上是在 linker script 中创建一个 symbol：

```text
linker script
     │
     ▼
_sdata = .
     │
     ▼
ELF Symbol Table
```

所以：

```bash
nm custom.elf
```

能够看到：

```text
_sdata
```

这意味着 linker script 本身就是一个：

> **符号生成器。**

---

# 二、三种写法到底有什么区别？

先看：

```ld
foo = .;
```

这是：

> **无条件定义 `foo`。**

如果其他 `.o` 也定义了 `foo`，可能产生符号冲突。

---

然后：

```ld
PROVIDE(foo = .);
```

它的意思更接近：

> **如果程序没有自己提供 `foo`，那么 linker script 提供一个默认定义。**

这特别适合：

```text
默认符号
可被用户代码覆盖
兼容旧程序
链接脚本提供 fallback
```

---

最后：

```ld
PROVIDE_HIDDEN(foo = .);
```

除了 `PROVIDE` 的“默认定义”语义之外：

> **对于 ELF，生成的 symbol 不作为普通全局可见符号导出。**

这在内部 linker 辅助符号中非常有用。([Sourceware][2])

---

# 三、实验目录

继续：

```text
ld-lab/
├── main.c
├── start.S
└── linker.ld
```

---

# 四、main.c

这次故意让 C 程序访问 linker 创建的符号。

```c
extern char image_start[];
extern char image_end[];

int main(void)
{
    long size = image_end - image_start;

    return size == 0;
}
```

这里有个重要认识：

```c
extern char image_start[];
```

并不是说 linker symbol 是一个真正的 C 数组。

它只是让编译器知道：

> 有一个外部 symbol 叫 `image_start`。

最终地址由 linker 决定。

GNU ld 文档也特别提醒：**linker script symbol 并不等价于高级语言变量**；它本质上是 ELF 中的 symbol/address。([Sourceware][2])

---

# 五、start.S

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

# 六、第一版 linker.ld

先从最简单的开始：

```ld
ENTRY(_start)

MEMORY
{
    ROM (rx) : ORIGIN = 0x00400000, LENGTH = 64K
    RAM (rw) : ORIGIN = 0x00600000, LENGTH = 64K
}

PHDRS
{
    text PT_LOAD FLAGS(5);
    data PT_LOAD FLAGS(6);
}

SECTIONS
{
    .text :
    {
        image_start = .;

        *(.text)
        *(.text.*)

        image_end = .;
    } > ROM :text
}
```

这里：

```ld
image_start = .;
```

会产生：

```text
image_start
```

而：

```ld
image_end = .;
```

会产生：

```text
image_end
```

---

# 七、编译

```bash
rm -f *.o *.elf *.map

gcc -c main.c -o main.o
gcc -c start.S -o start.o
```

链接：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    -o custom.elf \
    -Map=custom.map
```

---

# 八、观察 linker 创建的 symbol

```bash
nm -n custom.elf
```

寻找：

```text
image_start
image_end
```

也可以：

```bash
readelf -s custom.elf | grep image_
```

你应该看到：

```text
image_start
image_end
```

---

# 九、计算 `.text` 大小

因为：

```ld
image_start = .;
*(.text)
image_end = .;
```

所以：

```text
image_end - image_start
```

就是：

```text
.text Output Section
```

在这个实验中的大小。

也就是说 linker script 已经完成了：

```text
地址计算
    ↓
生成 symbol
    ↓
C 程序读取
```

---

# 十、用 map 文件验证

执行：

```bash
grep -A 15 -B 5 "\.text" custom.map
```

应该能看到类似：

```text
.text           0x0000000000400000       ...
                0x0000000000400000                image_start = .
 *(.text)
 .text          ...
 ...
                0x00000000004000xx                image_end = .
```

现在：

```text
map
 │
 ├── section 起始
 ├── section 内容
 └── linker symbol
```

三者完全对应。

---

# 十一、实验 09-2：`PROVIDE()`

现在把：

```ld
image_start = .;
```

改成：

```ld
PROVIDE(image_start = .);
```

完整：

```ld
.text :
{
    PROVIDE(image_start = .);

    *(.text)
    *(.text.*)

    PROVIDE(image_end = .);
} > ROM :text
```

重新链接：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    -o provide.elf \
    -Map=provide.map
```

查看：

```bash
nm -n provide.elf | grep image_
```

正常情况下：

```text
image_start
image_end
```

仍然存在。

---

# 十二、为什么 `PROVIDE()` 看起来和普通赋值一样？

因为目前：

```text
main.o
```

没有自己定义：

```text
image_start
image_end
```

于是：

```ld
PROVIDE(image_start = .);
```

就会发挥作用：

```text
程序没有 image_start
        ↓
linker script 提供
        ↓
image_start = .
```

因此：

```text
nm
```

还是能看到它。

---

# 十三、现在做一个真正有意义的实验

在 `main.c` 中自己定义：

```c
char image_start;
```

例如：

```c
char image_start;

int main(void)
{
    return image_start;
}
```

然后：

```bash
gcc -c main.c -o main.o
```

重新链接：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    -o provide-override.elf \
    -Map=provide-override.map
```

这时候：

```ld
PROVIDE(image_start = .);
```

不会简单粗暴地覆盖程序自己的定义。

这就是：

```text
PROVIDE
```

和：

```ld
image_start = .;
```

非常重要的区别。

---

# 十四、恢复 main.c

为了后续实验，恢复：

```c
extern char image_start[];
extern char image_end[];

int main(void)
{
    long size = image_end - image_start;

    return size == 0;
}
```

---

# 十五、实验 09-3：`PROVIDE_HIDDEN()`

现在修改：

```ld
PROVIDE(image_start = .);
```

为：

```ld
PROVIDE_HIDDEN(image_start = .);
```

同样：

```ld
PROVIDE_HIDDEN(image_end = .);
```

完整：

```ld
.text :
{
    PROVIDE_HIDDEN(image_start = .);

    *(.text)
    *(.text.*)

    PROVIDE_HIDDEN(image_end = .);
} > ROM :text
```

重新链接：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    -o hidden.elf \
    -Map=hidden.map
```

---

# 十六、用 `readelf -s` 看 Symbol

执行：

```bash
readelf -s hidden.elf | grep image_
```

这里重点观察：

```text
Bind
Vis
Ndx
Value
```

尤其：

```text
Vis
```

应该体现 hidden visibility。

再执行：

```bash
nm -n hidden.elf | grep image_
```

你会发现：

> `nm` 的显示形式和 `readelf -s` 的完整 ELF symbol 属性并不完全相同。

所以学习 ELF symbol 属性时：

```text
readelf -s
```

比单纯：

```text
nm
```

更完整。

---

# 十七、三种 symbol 放一起比较

| 写法                         | 作用              |
| -------------------------- | --------------- |
| `foo = .;`                 | 无条件定义           |
| `PROVIDE(foo = .);`        | 没有其他定义时提供       |
| `PROVIDE_HIDDEN(foo = .);` | 提供默认定义 + hidden |

可以画成：

```text
foo = .
│
└── 强制定义


PROVIDE(foo = .)
│
├── 程序已有 foo
│      ↓
│    使用程序自己的
│
└── 没有 foo
       ↓
     linker 提供


PROVIDE_HIDDEN(foo = .)
│
└── 与 PROVIDE 类似
       +
   ELF hidden
```

---

# 十八、进入真正有用的 linker symbol：`ORIGIN()`

前面我们写：

```ld
MEMORY
{
    ROM (rx) : ORIGIN = 0x00400000, LENGTH = 64K
    RAM (rw) : ORIGIN = 0x00600000, LENGTH = 64K
}
```

现在 linker script 可以直接引用：

```ld
ORIGIN(ROM)
```

也可以：

```ld
LENGTH(ROM)
```

于是：

```ld
ORIGIN(RAM) + LENGTH(RAM)
```

就是：

```text
RAM 末尾地址
```

---

# 十九、实验 09-4：自动生成 stack 边界

把：

```ld
PROVIDE_HIDDEN(image_end = .);
```

后面增加：

```ld
PROVIDE(__ram_start = ORIGIN(RAM));
PROVIDE(__ram_end = ORIGIN(RAM) + LENGTH(RAM));
PROVIDE(__stack_top = ORIGIN(RAM) + LENGTH(RAM));
```

完整：

```ld
ENTRY(_start)

MEMORY
{
    ROM (rx) : ORIGIN = 0x00400000, LENGTH = 64K
    RAM (rw) : ORIGIN = 0x00600000, LENGTH = 64K
}

PHDRS
{
    text PT_LOAD FLAGS(5);
    data PT_LOAD FLAGS(6);
}

SECTIONS
{
    .text :
    {
        PROVIDE_HIDDEN(image_start = .);

        *(.text)
        *(.text.*)

        PROVIDE_HIDDEN(image_end = .);
    } > ROM :text
}

PROVIDE(__ram_start = ORIGIN(RAM));
PROVIDE(__ram_end   = ORIGIN(RAM) + LENGTH(RAM));
PROVIDE(__stack_top = ORIGIN(RAM) + LENGTH(RAM));
```

main.c 中添加对新增段的引用

```
extern char __ram_start[];
extern char __ram_end[];
extern char __stack_top[];


void *ram_lo = __ram_start;
void *ram_hi = __ram_end;
void *stack_top = __stack_top;

```

---

# 二十、重新链接

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    -o memory-symbols.elf \
    -Map=memory-symbols.map
```

然后：

```bash
nm -n memory-symbols.elf
```

寻找：

```text
__ram_start
__ram_end
__stack_top
```

---

# 二十一、验证计算结果

假设：

```ld
RAM (rw) :
    ORIGIN = 0x00600000
    LENGTH = 64K
```

那么：

```text
64K = 0x10000
```

因此：

```text
__ram_start
=
0x00600000
```

而：

```text
__ram_end
=
0x00600000 + 0x10000
=
0x00610000
```

所以：

```text
RAM
0x00600000
    │
    │
    │ 64 KB
    │
    ▼
0x00610000
```

`__stack_top`：

```text
0x00610000
```

于是以后 startup code 可以：

```asm
mov $__stack_top, %rsp
```

当然，这只是概念实验；真正 x86-64 Linux 进程不能简单地把这种自定义地址当作可用用户栈。**这里是在学习 linker 的地址计算能力，而不是构造 Linux ABI 下的正常进程栈。**

---

# 二十二、为什么 `ORIGIN()` 很重要？

假设以后换 MCU：

```text
RAM = 128 KB
```

你只需要修改：

```ld
RAM (rw) :
    ORIGIN = 0x20000000,
    LENGTH = 128K
```

而不需要手工修改：

```ld
__stack_top = ...
```

因为 linker 自动计算：

```ld
ORIGIN(RAM) + LENGTH(RAM)
```

这就是 linker script 中非常重要的：

> **符号化地址计算。**

---

# 二十三、实验 09-5：给 RAM 划出 Stack 区

现在进一步做一个很典型的 MCU linker script。

```ld
MEMORY
{
    RAM (rw) : ORIGIN = 0x00600000, LENGTH = 64K
}
```

定义：

```ld
STACK_SIZE = 4K;
```

然后：

```ld
__stack_top = ORIGIN(RAM) + LENGTH(RAM);
__stack_bottom = __stack_top - STACK_SIZE;
```

即：

```ld
STACK_SIZE = 4K;

PROVIDE(__stack_top =
    ORIGIN(RAM) + LENGTH(RAM));

PROVIDE(__stack_bottom =
    __stack_top - STACK_SIZE);
```

假设：

```text
RAM:
0x600000
    │
    │
    │ application
    │
    │
    ├──────────────
    │ stack
    │ 4K
    │
0x610000
```

那么：

```text
__stack_bottom
=
0x60F000
```

```text
__stack_top
=
0x610000
```

---

# 二十四、现在把 `.bss` 放进去

完整 linker script：

```ld
ENTRY(_start)

MEMORY
{
    ROM (rx) : ORIGIN = 0x00400000, LENGTH = 64K
    RAM (rw) : ORIGIN = 0x00600000, LENGTH = 64K
}

PHDRS
{
    text PT_LOAD FLAGS(5);
    data PT_LOAD FLAGS(6);
}

SECTIONS
{
    .text :
    {
        PROVIDE_HIDDEN(__text_start = .);

        *(.text)
        *(.text.*)

        PROVIDE_HIDDEN(__text_end = .);
    } > ROM :text

    .rodata :
    {
        *(.rodata)
        *(.rodata.*)
    } > ROM :text

    .data :
    {
        __data_start = .;

        *(.data)
        *(.data.*)

        __data_end = .;
    } > RAM AT > ROM :data

    __data_load = LOADADDR(.data);

    .bss :
    {
        __bss_start = .;

        *(.bss)
        *(.bss.*)
        *(COMMON)

        __bss_end = .;
    } > RAM :data
}

STACK_SIZE = 4K;

PROVIDE(__ram_start =
    ORIGIN(RAM));

PROVIDE(__ram_end =
    ORIGIN(RAM) + LENGTH(RAM));

PROVIDE(__stack_top =
    ORIGIN(RAM) + LENGTH(RAM));

PROVIDE(__stack_bottom =
    __stack_top - STACK_SIZE);
```

这已经开始接近真正的嵌入式 linker script 了。

---

# 二十五、Map 文件现在会变得非常有意思

重新链接：

```bash
ld \
    -T linker.ld \
    start.o \
    main.o \
    -o memory-layout.elf \
    -Map=memory-layout.map
```

然后：

```bash
grep -E \
'__text|__data|__bss|__ram|__stack' \
memory-layout.map
```

你应该能看到：

```text
__text_start
__text_end

__data_start
__data_end
__data_load

__bss_start
__bss_end

__ram_start
__ram_end

__stack_top
__stack_bottom
```

于是 map 文件开始成为一张：

> **整个固件内存地图。**

---

# 二十六、建议再用 `readelf -s`

```bash
readelf -s memory-layout.elf \
    | grep -E '__text|__data|__bss|__ram|__stack'
```

这样可以把：

```text
linker script
        ↓
map
        ↓
ELF Symbol Table
```

完整串起来。

---

# 二十七、实验 09-6：利用 linker symbol 做“链接期断言”

现在进入一个非常实用的技巧。

假设：

```text
RAM
```

只有：

```text
64 KB
```

但是我们要求：

```text
stack = 4 KB
```

如果 `.bss` 已经把 RAM 占满怎么办？

linker 应该直接报错，而不是让固件悄悄生成一个错误布局。

这时候使用：

```ld
ASSERT()
```

例如：

```ld
ASSERT(
    __bss_end <= __stack_bottom,
    "RAM overflow: .bss overlaps stack"
);
```

完整：

```ld
__stack_top =
    ORIGIN(RAM) + LENGTH(RAM);

__stack_bottom =
    __stack_top - STACK_SIZE;

ASSERT(
    __bss_end <= __stack_bottom,
    "RAM overflow: .bss overlaps stack"
);
```

这是 linker script 非常强大的能力：

```text
编译阶段
   ↓
链接阶段
   ↓
检查内存布局
   ↓
错误
   ↓
构建失败
```

而不是：

```text
烧录
 ↓
启动
 ↓
莫名其妙崩溃
```

---

# 二十八、把它理解成“编译期内存单元测试”

例如：

```ld
ASSERT(
    __bss_end <= __stack_bottom,
    "RAM overflow"
);
```

实际上是在做：

```text
测试条件：

.bss_end <= stack_bottom

如果：
    true  → 链接成功

如果：
    false → ld 失败
```

所以大型嵌入式工程通常会大量使用：

```ld
ASSERT()
```

检查：

```text
Flash overflow
RAM overflow
stack overlap
bootloader overlap
application overlap
vector table alignment
```

---

# 二十九、今天的 `PROVIDE` 与 `ASSERT` 已经开始组成一个完整体系

现在：

```text
MEMORY
   │
   ├── ORIGIN()
   └── LENGTH()
          │
          ▼
      地址计算
          │
          ▼
      linker symbols
          │
   ┌──────┼────────┐
   ▼      ▼        ▼
 PROVIDE  = .    ASSERT
   │
   ▼
 startup / C / bootloader
```

也就是说：

> linker script 已经不只是“排版文件”。

它实际上开始像一个：

**专门描述固件内存布局并进行链接期验证的小型程序。**

---

# 三十、今天最值得记住的 7 个东西

| 语法                         | 作用                            |
| -------------------------- | ----------------------------- |
| `foo = .;`                 | 无条件创建/定义 linker symbol        |
| `PROVIDE(foo = .);`        | 程序没有定义时提供默认 symbol            |
| `PROVIDE_HIDDEN(foo = .);` | 默认 symbol + hidden visibility |
| `ORIGIN(RAM)`              | MEMORY 区域起始地址                 |
| `LENGTH(RAM)`              | MEMORY 区域长度                   |
| `ASSERT(expr, msg)`        | 链接期检查                         |
| `LOADADDR(.data)`          | 获取 section 的 LMA              |

其中：

```text
PROVIDE
```

解决：

```text
“给程序一个默认地址符号”
```

而：

```text
ASSERT
```

解决：

```text
“如果内存布局不合法，直接让链接失败”
```

---

# 三十一、最终脑图

到实验 09 为止，GNU ld 的核心已经可以画成：

```text
                         GNU ld
                           │
             ┌─────────────┼─────────────┐
             │             │             │
             ▼             ▼             ▼
          SECTIONS       MEMORY        PHDRS
             │             │             │
             │             │             │
             ▼             ▼             ▼
          Section       ROM/RAM        Segment
             │             │
             ├─────────────┘
             │
             ▼
        地址计算 / symbols
             │
      ┌──────┼──────────┐
      ▼      ▼          ▼
    ALIGN  ADDR      LOADADDR
      │
      ▼
   SUBALIGN
      │
      ▼
 Input Sections
      │
      ▼
 --gc-sections
      │
 ┌────┴─────┐
 ▼          ▼
删除       KEEP
           │
           ▼
        保留
           
linker symbols
      │
 ┌────┼───────────┐
 ▼    ▼           ▼
PROVIDE  PROVIDE_HIDDEN  ASSERT
      │
      ▼
 startup / bootloader / memory validation
```

---

# 三十二、下一实验：真正进入 `.a` 静态库

下一步我们就不再主要研究 linker script 语法，而是进入 `ld` 最经典、也最容易让人抓狂的问题：

# 实验 10：为什么 `.a` 里的代码有时候就是“不链接”？

我们会建立：

```text
libfoo.a
├── foo1.o
├── foo2.o
└── foo3.o
```

然后制造：

```text
main.o
   ↓
foo()
   ↓
libfoo.a
```

观察：

```bash
ld main.o libfoo.a
```

为什么能工作？

再反过来：

```bash
ld libfoo.a main.o
```

为什么可能失败？

然后进一步实验：

```text
libA.a → libB.a
libB.a → libA.a
```

制造循环依赖。

最后使用：

```bash
--start-group
--end-group
```

解决。

届时我们会把：

```text
Archive
Symbol Resolution
Input File Order
GC
KEEP
Map
```

全部串起来。

这一步是理解 GNU `ld` **“为什么它没有把我写好的代码链接进来”** 的关键。

[1]: https://sourceware.org/binutils/docs/ld.pdf?utm_source=chatgpt.com "The GNU linker"
[2]: https://www.sourceware.org/binutils/docs-2.36/ld.pdf?utm_source=chatgpt.com "The GNU linker"

