# GNU ld 实战课程 · 实验 34

## `REVERSE` + `SORT_NONE` + `EXCLUDE_FILE`

上一节实验 33，我们已经把 **Input Section 排序**完整跑通了：

```text
Input Section
      │
      ├── SORT_BY_NAME
      ├── SORT_BY_ALIGNMENT
      └── SORT_BY_INIT_PRIORITY
                 │
                 ▼
          Output Section
```

这一节继续往前走，但重点会发生一个变化：

> **不是“如何排序”，而是“如何反转排序、关闭隐式排序，以及在排序过程中排除指定目标文件”。**

这些功能在大型工程、插件系统、启动代码、固件分区中非常实用。

GNU ld 当前文档明确规定：

* `SORT` 是 `SORT_BY_NAME` 的别名；
* `REVERSE` 可以反转排序；单独使用时相当于按名称逆序；
* `SORT_NONE` 用于禁止默认的隐式排序；
* `EXCLUDE_FILE` 可以放进排序命令内部，但不能反过来把 `SORT_*` 放进 `EXCLUDE_FILE`；
* Section sorting 最多允许一层嵌套。([Sourceware][1])

---

# 一、实验 34 总体路线

本节分成 7 个递进实验：

```text
实验 34-1
REVERSE
   ↓
实验 34-2
REVERSE + SORT_BY_NAME
   ↓
实验 34-3
SORT_NONE
   ↓
实验 34-4
EXCLUDE_FILE
   ↓
实验 34-5
EXCLUDE_FILE + SORT
   ↓
实验 34-6
KEEP + EXCLUDE_FILE + SORT
   ↓
实验 34-7
综合实验：Plugin Registry
```

最终我们要得到这样的结构：

```text
                    *.o
                     │
          ┌──────────┼──────────┐
          │          │          │
       plugin-a   plugin-b   plugin-c
          │          │          │
          └──────────┼──────────┘
                     │
                GNU ld
                     │
          EXCLUDE_FILE(plugin-b.o)
                     │
                  SORT
                     │
                     ▼
             .plugin_registry
```

---

# 二、实验 34-1：`REVERSE`

先从最简单的开始。

上一节：

```ld
*(SORT_BY_NAME(.my_init.*))
```

得到：

```text
.my_init.10
.my_init.20
.my_init.30
```

那么：

```ld
*(REVERSE(.my_init.*))
```

会得到：

```text
.my_init.30
.my_init.20
.my_init.10
```

官方文档规定，单独使用 `REVERSE` 时，它隐含的是：

```text
REVERSE
    ↓
SORT_BY_NAME
    ↓
反向排序
```

也就是：

```text
Z → A
```

而不是：

```text
A → Z
```

([Sourceware][1])

---

# 三、实验目录

继续使用：

```text
ld-lab/
└── 34-sort-advanced/
    ├── a.c
    ├── b.c
    ├── c.c
    ├── main.c
    └── linker.ld
```

---

# 四、源码

## `a.c`

```c
__attribute__((section(".my_init.10"), used))
const char init_a[] = "A";
```

## `b.c`

```c
__attribute__((section(".my_init.20"), used))
const char init_b[] = "B";
```

## `c.c`

```c
__attribute__((section(".my_init.30"), used))
const char init_c[] = "C";
```

---

# 五、编译

```bash
gcc -c a.c b.c c.c
```

验证：

```bash
readelf -SW a.o
readelf -SW b.o
readelf -SW c.o
```

应该分别看到：

```text
.my_init.10
.my_init.20
.my_init.30
```

---

# 六、创建 `linker.ld`

```ld
SECTIONS
{
    .my_registry :
    {
        __my_registry_start = .;

        *(REVERSE(.my_init.*))

        __my_registry_end = .;
    }
}

INSERT BEFORE .text;
```

这里特别注意：

```ld
*(REVERSE(.my_init.*))
```

是合法形式。

不是：

```ld
REVERSE(*(.my_init.*))
```

---

# 七、链接

为了保证实验简单，继续用 GCC 驱动：

```bash
gcc \
    a.o \
    b.o \
    c.o \
    main.c \
    -Wl,-T,linker.ld \
    -Wl,-Map=reverse.map \
    -o reverse.elf
```

---

# 八、Map 验证

执行：

```bash
grep -A20 -B2 '\.my_registry' reverse.map
```

核心应该类似：

```text
.my_registry

*(REVERSE(.my_init.*))

.my_init.30
.my_init.20
.my_init.10
```

也就是：

```text
30
 ↓
20
 ↓
10
```

---

# 九、readelf 验证

```bash
readelf -SW reverse.elf
```

找到：

```text
.my_registry
```

然后：

```bash
objdump -h reverse.elf
```

确认：

```text
.my_registry
```

的：

```text
VMA
LMA
Size
File off
Algn
```

---

# 十、objdump 验证真实数据

```bash
objdump -s -j .my_registry reverse.elf
```

因为：

```text
.my_init.30 → C
.my_init.20 → B
.my_init.10 → A
```

所以数据顺序应该体现：

```text
C
B
A
```

这一步很重要。

我们不是只看：

```text
Section Header
```

而是继续验证：

```text
Map
  ↓
Section
  ↓
实际二进制
```

---

# 十一、实验 34-2：`REVERSE(SORT_BY_NAME())`

现在不要依赖 `REVERSE` 的隐式行为。

明确写：

```ld
*(REVERSE(SORT_BY_NAME(.my_init.*)))
```

完整 linker：

```ld
SECTIONS
{
    .my_registry :
    {
        __my_registry_start = .;

        *(REVERSE(SORT_BY_NAME(.my_init.*)))

        __my_registry_end = .;
    }
}

INSERT BEFORE .text;
```

---

# 十二、它到底是什么意思？

执行顺序可以理解为：

```text
.my_init.*
      │
      ▼
SORT_BY_NAME
      │
      ▼
10 20 30
      │
      ▼
REVERSE
      │
      ▼
30 20 10
```

因此：

```text
REVERSE(SORT_BY_NAME(...))
```

是一个非常直观的写法。

---

# 十三、注意一个非常容易混淆的点

这两个：

```ld
REVERSE(.foo.*)
```

和：

```ld
REVERSE(SORT_BY_NAME(.foo.*))
```

在这个场景下最终效果相同。

因为：

```text
REVERSE
```

单独使用时已经隐含：

```text
SORT_BY_NAME
```

官方文档对此有明确说明。([Sourceware][1])

但我建议课程和实际项目中优先写：

```ld
REVERSE(SORT_BY_NAME(.foo.*))
```

因为它的意图非常明确：

> **先按名字排序，再反转。**

---

# 十四、实验 34-3：`SORT_NONE`

这个实验非常关键。

因为 GNU ld 在某些情况下存在**隐式排序**。

我们之前已经习惯：

```ld
*(.foo.*)
```

然后认为：

> “没有 SORT，所以完全按照输入顺序。”

这个理解并不总是可靠。

GNU ld 支持：

```ld
SORT_NONE(...)
```

明确要求：

> 不进行隐式 Section 排序。

官方文档将 `SORT_NONE` 列为 Section sorting 命令的一部分。([Sourceware][2])

---

# 十五、为什么会存在“隐式排序”？

这是 GNU ld 一个比较容易被忽略的细节。

例如系统默认 linker script 可能在处理：

```text
.ctors
.dtors
.init_array
.fini_array
```

时采用特殊的排序规则。

所以大型项目中，如果你真的想表达：

> **完全按照 linker 输入顺序处理这些 Input Section。**

可以使用：

```ld
*(SORT_NONE(.foo.*))
```

---

# 十六、实验

创建：

```ld
SECTIONS
{
    .raw_registry :
    {
        __raw_start = .;

        *(SORT_NONE(.my_init.*))

        __raw_end = .;
    }
}

INSERT BEFORE .text;
```

保存：

```text
linker-sort-none.ld
```

---

# 十七、链接

```bash
gcc \
    c.o \
    a.o \
    b.o \
    main.c \
    -Wl,-T,linker-sort-none.ld \
    -Wl,-Map=sort-none.map \
    -o sort-none.elf
```

注意输入顺序：

```text
c.o
a.o
b.o
```

---

# 十八、Map 分析

```bash
grep -A20 -B2 '\.raw_registry' sort-none.map
```

重点观察：

```text
.my_init.30
.my_init.10
.my_init.20
```

这就是：

```text
c.o
 ↓
a.o
 ↓
b.o
```

形成的顺序。

因此：

```text
SORT_NONE
```

可以理解成：

```text
“别替我聪明地排序。”
```

---

# 十九、`SORT_NONE` 和普通 `*()` 的关系

不要简单记成：

```text
*()       = 排序
SORT_NONE = 不排序
```

更准确的理解是：

```text
*()
   ↓
允许 ld 根据规则进行默认处理

SORT_NONE()
   ↓
明确关闭隐式排序
```

这是一个非常重要的 linker script 思维。

---

# 二十、实验 34-4：`EXCLUDE_FILE`

现在进入真正实用的功能。

假设我们有：

```text
a.o
b.o
c.o
```

每个都有：

```text
.plugin.*
```

我们希望：

```text
a.o   → 收集
b.o   → 排除
c.o   → 收集
```

那么：

```ld
*(EXCLUDE_FILE(b.o) .plugin.*)
```

意思就是：

```text
所有匹配 .plugin.*
        │
        ├── b.o ❌
        │
        ├── a.o ✓
        └── c.o ✓
```

---

# 二十一、源码

## `plugin_a.c`

```c
__attribute__((section(".plugin.100"), used))
const char plugin_a[] = "PLUGIN_A";
```

## `plugin_b.c`

```c
__attribute__((section(".plugin.200"), used))
const char plugin_b[] = "PLUGIN_B";
```

## `plugin_c.c`

```c
__attribute__((section(".plugin.300"), used))
const char plugin_c[] = "PLUGIN_C";
```

---

# 二十二、编译

```bash
gcc -c \
    plugin_a.c \
    plugin_b.c \
    plugin_c.c
```

检查：

```bash
readelf -SW plugin_a.o
readelf -SW plugin_b.o
readelf -SW plugin_c.o
```

应该得到：

```text
plugin_a.o
    .plugin.100

plugin_b.o
    .plugin.200

plugin_c.o
    .plugin.300
```

---

# 二十三、linker script

```ld
SECTIONS
{
    .plugin_registry :
    {
        __plugin_start = .;

        *(EXCLUDE_FILE(plugin_b.o) .plugin.*)

        __plugin_end = .;
    }
}

INSERT BEFORE .text;
```

---

# 二十四、链接

```bash
gcc \
    plugin_a.o \
    plugin_b.o \
    plugin_c.o \
    main.c \
    -Wl,-T,linker.ld \
    -Wl,-Map=exclude.map \
    -o exclude.elf
```

---

# 二十五、Map 分析

```bash
grep -A25 -B2 '\.plugin_registry' exclude.map
```

应该看到：

```text
.plugin_registry

.plugin.100   plugin_a.o
.plugin.300   plugin_c.o
```

而：

```text
.plugin.200   plugin_b.o
```

不会进入：

```text
.plugin_registry
```

---

# 二十六、但是注意一个重要事实

`EXCLUDE_FILE` 并不是：

> “从整个 ELF 删除这个 `.o`。”

它只是：

> **在当前 Input Section 描述中，不让指定文件的匹配 Section 被这个模式收集。**

例如：

```ld
*(EXCLUDE_FILE(plugin_b.o) .plugin.*)
```

只排除：

```text
plugin_b.o
```

中的：

```text
.plugin.*
```

如果：

```text
plugin_b.o
```

还有：

```text
.text
.data
.rodata
```

这些仍然可以通过其他规则进入 ELF。

这一点非常重要。

---

# 二十七、实验 34-5：`EXCLUDE_FILE + SORT_BY_NAME`

这才是工程中更常见的写法：

```ld
*(SORT_BY_NAME(EXCLUDE_FILE(plugin_b.o) .plugin.*))
```

注意这个语法顺序。

官方 GNU ld 文档明确支持：

```ld
*(SORT_BY_NAME(EXCLUDE_FILE(foo) .text*))
```

但不支持：

```ld
*(EXCLUDE_FILE(foo) SORT_BY_NAME(.text*))
```

也就是说：

```text
正确：

SORT
 └── EXCLUDE_FILE

错误：

EXCLUDE_FILE
 └── SORT
```

([Sourceware][1])

---

# 二十八、为什么必须这样设计？

把：

```ld
SORT_BY_NAME(EXCLUDE_FILE(plugin_b.o) .plugin.*)
```

拆开：

```text
                .plugin.*
                    │
                    ▼
              EXCLUDE_FILE
                    │
                    ▼
              剩余 Input Sections
                    │
                    ▼
              SORT_BY_NAME
                    │
                    ▼
              最终排序结果
```

例如：

```text
.plugin.300 plugin_c.o
.plugin.100 plugin_a.o
.plugin.200 plugin_b.o
```

先排除：

```text
.plugin.200
```

然后剩下：

```text
.plugin.300
.plugin.100
```

再排序：

```text
.plugin.100
.plugin.300
```

---

# 二十九、验证

```bash
gcc \
    plugin_c.o \
    plugin_b.o \
    plugin_a.o \
    main.c \
    -Wl,-T,linker.ld \
    -Wl,-Map=exclude-sort.map \
    -o exclude-sort.elf
```

故意打乱输入顺序：

```text
c
b
a
```

但最终：

```text
.plugin.100
.plugin.300
```

因为：

```text
b → EXCLUDE
剩下 → SORT
```

---

# 三十、实验 34-6：`KEEP + EXCLUDE_FILE + SORT`

现在把上一节的 `KEEP` 加回来。

```ld
SECTIONS
{
    .plugin_registry :
    {
        __plugin_start = .;

        KEEP(
            *(
                SORT_BY_NAME(
                    EXCLUDE_FILE(plugin_b.o)
                    .plugin.*
                )
            )
        )

        __plugin_end = .;
    }
}

INSERT BEFORE .text;
```

这句话非常值得你把它拆成四层：

```text
KEEP
 │
 └── *()
      │
      └── SORT_BY_NAME
            │
            └── EXCLUDE_FILE
                  │
                  └── .plugin.*
```

也就是：

```text
保留
 ↓
匹配
 ↓
排序
 ↓
排除
```

---

# 三十一、为什么 `KEEP` 仍然重要？

假设：

```bash
-Wl,--gc-sections
```

打开。

那么：

```text
.plugin.100
.plugin.300
```

可能没有普通 C 引用。

于是：

```text
GC
 ↓
认为没人使用
 ↓
删除
```

但：

```ld
KEEP(...)
```

告诉 linker：

> 不要因为 `--gc-sections` 把它们清掉。

所以完整 Registry 模式：

```ld
KEEP(
    *(
        SORT_BY_NAME(
            EXCLUDE_FILE(...)
            .plugin.*
        )
    )
)
```

就很强了。

---

# 三十二、实验 34-7：完整 Plugin Registry

现在我们做一个稍微像真实系统的例子。

目录：

```text
plugin-demo/
├── main.c
├── plugin_http.c
├── plugin_mqtt.c
├── plugin_debug.c
├── plugin_disabled.c
└── linker.ld
```

---

# 三十三、Plugin 定义

## `plugin_http.c`

```c
typedef void (*plugin_fn)(void);

static void http_init(void)
{
}

__attribute__((section(".plugin.100"), used))
plugin_fn http_plugin = http_init;
```

---

## `plugin_mqtt.c`

```c
typedef void (*plugin_fn)(void);

static void mqtt_init(void)
{
}

__attribute__((section(".plugin.200"), used))
plugin_fn mqtt_plugin = mqtt_init;
```

---

## `plugin_debug.c`

```c
typedef void (*plugin_fn)(void);

static void debug_init(void)
{
}

__attribute__((section(".plugin.300"), used))
plugin_fn debug_plugin = debug_init;
```

---

## `plugin_disabled.c`

```c
typedef void (*plugin_fn)(void);

static void disabled_init(void)
{
}

__attribute__((section(".plugin.999"), used))
plugin_fn disabled_plugin = disabled_init;
```

---

# 三十四、我们决定：

```text
HTTP       ✓
MQTT       ✓
DEBUG      ✓
DISABLED   ✗
```

因此：

```ld
EXCLUDE_FILE(plugin_disabled.o)
```

---

# 三十五、最终 linker script

```ld
SECTIONS
{
    .plugin_registry :
    {
        . = ALIGN(16);

        __plugin_registry_start = .;

        KEEP(
            *(
                SORT_BY_NAME(
                    EXCLUDE_FILE(plugin_disabled.o)
                    .plugin.*
                )
            )
        )

        __plugin_registry_end = .;
    }
}

INSERT BEFORE .text;
```

这已经是一个相当实用的 Registry linker script。

---

# 三十六、编译

```bash
gcc \
    -ffunction-sections \
    -fdata-sections \
    -c \
    main.c \
    plugin_http.c \
    plugin_mqtt.c \
    plugin_debug.c \
    plugin_disabled.c
```

---

# 三十七、链接

```bash
gcc \
    main.o \
    plugin_http.o \
    plugin_mqtt.o \
    plugin_debug.o \
    plugin_disabled.o \
    -Wl,-T,linker.ld \
    -Wl,--gc-sections \
    -Wl,-Map=plugin.map \
    -o plugin.elf
```

---

# 三十八、第一层验证：Section Header

```bash
readelf -SW plugin.elf
```

搜索：

```bash
readelf -SW plugin.elf | grep plugin
```

应该出现：

```text
.plugin_registry
```

---

# 三十九、第二层验证：Symbol

```bash
nm -n plugin.elf | grep plugin_registry
```

应该看到：

```text
__plugin_registry_start
__plugin_registry_end
```

例如：

```text
000000000000....
000000000000....
```

---

# 四十、第三层验证：Section Size

计算：

```text
end - start
```

例如：

```text
registry size = 24
```

如果每个指针是：

```text
8 bytes
```

那么：

```text
3 plugins × 8
=
24 bytes
```

这恰好可以验证：

```text
HTTP
MQTT
DEBUG
```

三个 Registry Entry 都存在。

---

# 四十一、第四层验证：Map

执行：

```bash
grep -A30 -B3 '\.plugin_registry' plugin.map
```

最终应该类似：

```text
.plugin_registry
                0x000000000000....

                __plugin_registry_start = .

*(SORT_BY_NAME(EXCLUDE_FILE(plugin_disabled.o) .plugin.*))

.plugin.100       plugin_http.o
.plugin.200       plugin_mqtt.o
.plugin.300       plugin_debug.o

                __plugin_registry_end = .
```

注意：

```text
.plugin.999
```

不应该出现。

---

# 四十二、第五层验证：objdump

```bash
objdump -h plugin.elf
```

再：

```bash
objdump -s -j .plugin_registry plugin.elf
```

你可以看到：

```text
plugin_http
plugin_mqtt
plugin_debug
```

对应的函数地址被连续放进 Registry。

---

# 四十三、这时候我们真正理解了 `EXCLUDE_FILE`

它不是简单的：

```text
黑名单文件
```

而是：

```text
Section Collection Filter
```

即：

```text
所有 Input Sections
       │
       ▼
 wildcard
       │
       ▼
 EXCLUDE_FILE
       │
       ├── 排除指定文件
       │
       ▼
 SORT
       │
       ▼
 KEEP
       │
       ▼
 Output Section
```

---

# 四十四、一个非常重要的坑

不要写：

```ld
*(EXCLUDE_FILE(plugin_disabled.o) SORT_BY_NAME(.plugin.*))
```

GNU ld 当前文档明确指出，这种方向是不允许的。正确形式是：

```ld
*(SORT_BY_NAME(EXCLUDE_FILE(plugin_disabled.o) .plugin.*))
```

([Sourceware][1])

这个坑非常值得记住。

---

# 四十五、另一个坑：`REVERSE` 不是万能反转

官方文档特别说明：

> `REVERSE` 对 alignment 的反向排序目前不支持。

也就是说，不要想当然地写：

```ld
REVERSE(SORT_BY_ALIGNMENT(.foo.*))
```

然后期待：

```text
alignment

32
16
8

↓

8
16
32
```

GNU ld 当前文档明确说明这种 alignment reverse sorting 并不支持。([Sourceware][1])

因此：

```text
REVERSE
```

最适合：

```text
名称排序反转
```

而不是把它当成：

```text
任何 SORT_BY_* 都能反转
```

---

# 四十六、另一个重要限制：SORT 一次只能接一个 wildcard pattern

官方文档还特别说明：

```ld
*(REVERSE(.text* .init*))
```

这种写法不行。

应该拆开：

```ld
*(REVERSE(.text*))
*(REVERSE(.init*))
```

([Sourceware][1])

也就是说：

```text
一个 sorting command
        ↓
一个 wildcard pattern
```

这条规则以后遇到复杂 linker script 时非常重要。

---

# 四十七、实验 34-8：为什么 Map 比 readelf 更重要？

假设：

```bash
readelf -SW plugin.elf
```

看到：

```text
.plugin_registry
```

但是：

```text
你不知道里面到底是谁。
```

这时候：

```bash
objdump -h
```

也没办法告诉你：

```text
plugin_http.o
plugin_mqtt.o
plugin_debug.o
```

到底是谁进入了这个 Output Section。

但是：

```bash
grep -A30 '\.plugin_registry' plugin.map
```

可以直接看到：

```text
.plugin.100 plugin_http.o
.plugin.200 plugin_mqtt.o
.plugin.300 plugin_debug.o
```

所以这节以后，形成一个固定原则：

```text
readelf
    ↓
验证 ELF 结构

objdump
    ↓
验证 Section / 内容 / 指令

nm
    ↓
验证 Symbol

Map
    ↓
解释“为什么最终会这样”
```

---

# 四十八、把实验 33 + 34 连起来

现在我们的 linker 技能已经变成：

```text
                 Input Sections
                       │
             ┌─────────┴─────────┐
             │                   │
         EXCLUDE_FILE          wildcard
             │                   │
             └─────────┬─────────┘
                       │
                     SORT
                       │
             ┌─────────┼─────────┐
             │         │         │
           NAME      ALIGN    PRIORITY
             │
           REVERSE
             │
             ▼
           KEEP
             │
             ▼
      Output Section
             │
             ▼
           INSERT
```

这已经开始形成真正的：

# Linker Script 设计语言

而不是简单记忆语法。

---

# 四十九、这一节最应该掌握的语法

### 按名称升序

```ld
*(SORT_BY_NAME(.foo.*))
```

### 按名称降序

```ld
*(REVERSE(.foo.*))
```

或者：

```ld
*(REVERSE(SORT_BY_NAME(.foo.*)))
```

### 禁止隐式排序

```ld
*(SORT_NONE(.foo.*))
```

### 排除指定 `.o`

```ld
*(EXCLUDE_FILE(foo.o) .foo.*)
```

### 排除后再按名字排序

```ld
*(SORT_BY_NAME(EXCLUDE_FILE(foo.o) .foo.*))
```

### 排除 + 排序 + 防 GC

```ld
KEEP(
    *(
        SORT_BY_NAME(
            EXCLUDE_FILE(foo.o)
            .foo.*
        )
    )
)
```

---

# 五十、最终综合模型

你现在应该能够看到一个非常漂亮的 linker pipeline：

```text
                    foo.o
                      │
                    bar.o
                      │
                    baz.o
                      │
                      ▼
              Input Section
                      │
                      ▼
             ┌─────────────────┐
             │ EXCLUDE_FILE    │
             └────────┬────────┘
                      │
                      ▼
                 SORT_BY_NAME
                      │
                      ▼
                   KEEP
                      │
                      ▼
              Output Section
                      │
                      ▼
              .plugin_registry
                      │
          ┌───────────┴───────────┐
          │                       │
    __registry_start       __registry_end
          │                       │
          └───────────┬───────────┘
                      │
                      ▼
                   C code
                      │
                      ▼
                 for (...)
                      │
                      ▼
              自动执行 Plugin
```

这就是我们前面一直在铺垫的：

> **利用 GNU ld 构建“自动注册机制”。**

---

# 五十一、本节实验验收标准

如果要把这节真正学扎实，不要只看懂代码。建议你把下面 5 个实验亲自跑出来：

```text
□ 34-1 REVERSE

□ 34-2 REVERSE(SORT_BY_NAME())

□ 34-3 SORT_NONE

□ 34-4 EXCLUDE_FILE

□ 34-5 EXCLUDE_FILE + SORT_BY_NAME
```

然后最终完成：

```text
□ 34-6 KEEP + EXCLUDE_FILE + SORT

□ 34-7 Plugin Registry
```

每个实验至少执行：

```bash
readelf -SW xxx.o
readelf -SW xxx.elf
objdump -h xxx.elf
objdump -s -j <section> xxx.elf
nm -n xxx.elf
grep -A30 <section> xxx.map
```

形成自己的固定验证套路。

---

# 五十二、下一阶段：实验 35

到这里，**Input Section → Output Section** 这一条线已经基本打通。

下一步就不应该继续在 SORT 上打转，而应该进入更重要的一层：

# 实验 35 —— `MEMORY` + `REGION_ALIAS` + `ORIGIN()` + `LENGTH()`

我们会开始真正解决：

```text
FLASH
   │
   ├── .text
   ├── .rodata
   └── .data 的 Load Image
           │
           ▼
RAM
   │
   ├── .data
   ├── .bss
   └── stack
```

并且重点解决你之前实验中遇到过的那类问题：

```text
address ... of section `.text'
is not within region `ROM'

section `.data' will not fit in region `ROM'

region `ROM' overflowed
```

下一阶段会把：

```text
MEMORY
ORIGIN
LENGTH
> REGION
AT > REGION
LOADADDR
SIZEOF
ADDR
ALIGN
ASSERT
```

组合起来。

然后再进入：

```text
实验 36
PHDRS

实验 37
Section → Segment

实验 38
FILEHDR / PHDRS / SIZEOF_HEADERS

实验 39
AT() / LOADADDR()

实验 40
ROM → RAM 数据初始化

实验 41
Copy Table

实验 42
Firmware Image Layout

实验 43
Bootloader + Application

实验 44
ELF → BIN / HEX

实验 45
综合 Firmware Linker Script
```

也就是说，从 **实验 35** 开始，我们会正式从：

```text
“研究 ld 如何组织 Section”
```

进入：

```text
“自己设计一个真实 CPU/MCU 的内存镜像”
```

这会是整个 GNU ld 实战课程里非常关键的一次升级。

[1]: https://sourceware.org/binutils/docs/ld.pdf?utm_source=chatgpt.com "The GNU linker"
[2]: https://sourceware.org/binutils/docs-2.43/ld.pdf?utm_source=chatgpt.com "The GNU linker"

