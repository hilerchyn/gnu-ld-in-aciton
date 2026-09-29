# GNU ld 实战课程 · 实验 30

# `ASSERT()` + `NOCROSSREFS()` + `NOCROSSREFS_TO()`：让 linker 强制执行架构规则

上一节实验 29，我们已经把 **Linker Symbol** 体系打通：

```text
普通 Symbol
    ↓
PROVIDE()
    ↓
PROVIDE_HIDDEN()
    ↓
HIDDEN()
    ↓
ABSOLUTE()
    ↓
readelf -sW / nm / objdump -t
```

这一节进入一个更高级的阶段：

> **让 GNU ld 不只是“计算地址”，而是主动检查你的软件架构是否合法。**

GNU ld 官方文档明确提供了 `NOCROSSREFS()` 和 `NOCROSSREFS_TO()`，专门用于检测 Output Section 之间的非法引用；它们尤其适合嵌入式系统、Overlay、Bootloader/Application 等需要隔离的场景。([Sourceware][1])

我们这一节最终要实现：

```text
┌─────────────────────┐
│     BOOTLOADER      │
│                     │
│ boot_init()         │
│ boot_log()          │
└──────────┬──────────┘
           │
           │ 允许
           ▼
┌─────────────────────┐
│    APPLICATION      │
│                     │
│ app_main()          │
│ app_task()          │
└─────────────────────┘
```

但禁止：

```text
APPLICATION
     │
     X
     ▼
BOOTLOADER
```

然后让：

```ld
NOCROSSREFS_TO(.boot, .app)
```

直接在**链接阶段**报错。

这就从：

```text
Linker = 地址计算器
```

升级成：

```text
Linker = 架构规则检查器
```

---

# 一、实验 30 学习目标

这一节完成：

```text
① ASSERT()

② NOCROSSREFS()

③ NOCROSSREFS_TO()

④ Output Section 之间的引用

⑤ relocation 如何暴露跨 Section 依赖

⑥ readelf -r

⑦ objdump -dr

⑧ Map 文件定位问题

⑨ Bootloader / Application 隔离

⑩ Link-time Architecture Enforcement
```

最终形成：

```text
                ld
                 │
        ┌────────┼────────┐
        │        │        │
     ASSERT   NOCROSS   NOCROSS_TO
        │        │        │
        └────────┼────────┘
                 ▼
          Architecture Check
                 │
        ┌────────┴────────┐
        ▼                 ▼
      PASS              ERROR
        │                 │
        ▼                 ▼
      ELF             link failed
```

---

# 二、为什么这一节非常重要？

假设一个真实产品有：

```text
Bootloader
Application
Factory Test
Recovery
Secure Monitor
```

你可能规定：

```text
Bootloader
    ↓
Application
```

可以调用。

但是：

```text
Application
    ↓
Bootloader
```

绝对禁止。

为什么？

因为 Bootloader 升级以后：

```text
Application
```

不能依赖旧版本 Bootloader 的内部函数。

否则：

```text
Bootloader v1
    ↑
Application v1

Bootloader v2
    ↑
Application v1
```

就可能产生 ABI / 地址 / 行为兼容性问题。

最理想的方式不是：

```text
Code Review
```

也不是：

```text
测试阶段发现
```

而是：

# Link 时直接失败。

---

# 三、实验目录

建立：

```text
lab30/
├── boot.c
├── app.c
├── start.S
├── linker.ld
└── Makefile
```

---

# 四、实验 30-1：Bootloader 代码

创建 `boot.c`：

```c
__attribute__((section(".boot")))
int boot_log(void)
{
    return 100;
}

__attribute__((section(".boot")))
int boot_init(void)
{
    return boot_log();
}
```

这里我们故意使用：

```c
__attribute__((section(".boot")))
```

让这些函数进入：

```text
.boot
```

Input Section。

---

# 五、Application 代码

`app.c`：

```c
extern int boot_init(void);

__attribute__((section(".app")))
int app_task(void)
{
    return 10;
}

__attribute__((section(".app")))
int app_main(void)
{
    return app_task();
}
```

现在：

```text
app_main()
   ↓
app_task()
```

没有跨区域引用。

---

# 六、启动代码

`start.S`：

```asm
.global _start

.extern app_main

.text

_start:
    call app_main

.hang:
    hlt
    jmp .hang
```

因此：

```text
_start
   ↓
app_main
   ↓
app_task
```

---

# 七、编译

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
    -c boot.c \
    -o boot.o
```

```bash
gcc \
    -ffreestanding \
    -fno-pie \
    -fno-stack-protector \
    -ffunction-sections \
    -fdata-sections \
    -c app.c \
    -o app.o
```

---

# 八、实验 30-2：先不要使用 `NOCROSSREFS`

建立最简单 linker：

```ld
ENTRY(_start)

MEMORY
{
    ROM (rx) : ORIGIN = 0x00400000, LENGTH = 64K
}

SECTIONS
{
    .text :
    {
        *(.text)
        *(.text.*)
    } > ROM

    .boot :
    {
        *(.boot)
    } > ROM

    .app :
    {
        *(.app)
    } > ROM
}
```

链接：

```bash
ld \
    -T linker.ld \
    start.o \
    boot.o \
    app.o \
    -o normal.elf \
    -Map=normal.map
```

正常情况下：

```text
链接成功。
```

---

# 九、先观察 Section

```bash
readelf -SW normal.elf
```

应该看到：

```text
.text
.boot
.app
```

然后：

```bash
objdump -h normal.elf
```

记录：

```text
.boot
.app
```

的：

```text
VMA
Size
Offset
```

---

# 十、实验 30-3：观察 Application 内部调用

执行：

```bash
objdump -dr app.o
```

你应该看到类似：

```text
Disassembly of section .app:

0000000000000000 <app_task>:
   ...

0000000000000000 <app_main>:
   ...
   call ...
        R_X86_64_PLT32 app_task-0x4
```

具体 relocation 类型可能随编译参数/工具链变化。

重点不是死记：

```text
R_X86_64_PLT32
```

而是观察：

```text
app_main
   │
   └── relocation
          ↓
       app_task
```

---

# 十一、实验 30-4：制造真正的跨区域引用

现在修改 `app.c`：

```c
extern int boot_init(void);

__attribute__((section(".app")))
int app_task(void)
{
    return 10;
}

__attribute__((section(".app")))
int app_main(void)
{
    return boot_init();
}
```

现在架构变成：

```text
.app
 │
 │ call
 ▼
.boot
```

即：

```text
Application
     │
     ▼
Bootloader
```

---

# 十二、重新编译

```bash
gcc \
    -ffreestanding \
    -fno-pie \
    -fno-stack-protector \
    -ffunction-sections \
    -fdata-sections \
    -c app.c \
    -o app.o
```

---

# 十三、第一层验证：`objdump -dr`

```bash
objdump -dr app.o
```

现在你应该能够看到类似：

```text
app_main:
    ...
    call ...
        R_X86_64_PLT32 boot_init-0x4
```

这非常重要。

因为：

```text
C：

return boot_init();
```

经过编译后已经变成：

```text
machine instruction
        +
relocation
```

而：

```text
ld
```

正是利用这些 relocation 来完成最终地址解析。

---

# 十四、第二层验证：`readelf -r`

执行：

```bash
readelf -rW app.o
```

你会看到类似：

```text
Relocation section '.rela.app' ...

Offset
Info
Type
Symbol's Value
Symbol's Name

...
boot_init
```

于是：

```text
app.o
   │
   ├── .app
   │
   └── relocation
           │
           ▼
       boot_init
```

已经形成了完整的证据链。

---

# 十五、现在 linker 还不会阻止它

重新：

```bash
ld \
    -T linker.ld \
    start.o \
    boot.o \
    app.o \
    -o cross.elf \
    -Map=cross.map
```

依然可能：

```text
成功。
```

因为从普通 ELF 链接角度：

```text
app_main()
```

调用：

```text
boot_init()
```

完全合法。

但是从我们的：

```text
Bootloader / Application 架构
```

角度：

```text
非法。
```

这就是：

# `NOCROSSREFS` 的用武之地。

---

# 十六、实验 30-5：第一次使用 `NOCROSSREFS`

在 linker script 最后加入：

```ld
NOCROSSREFS(.boot .app);
```

完整：

```ld
ENTRY(_start)

MEMORY
{
    ROM (rx) : ORIGIN = 0x00400000, LENGTH = 64K
}

SECTIONS
{
    .text :
    {
        *(.text)
        *(.text.*)
    } > ROM

    .boot :
    {
        *(.boot)
    } > ROM

    .app :
    {
        *(.app)
    } > ROM
}

NOCROSSREFS(.boot .app);
```

重新链接：

```bash
ld \
    -T linker.ld \
    start.o \
    boot.o \
    app.o \
    -o nocross.elf \
    -Map=nocross.map
```

---

# 十七、现在应该发生什么？

GNU ld 应该报告跨 Output Section 的引用错误，具体错误文本会因 binutils 版本而有所不同。

关键是：

```text
link failed
```

也就是说：

```text
Application
    ↓
Bootloader
```

被 linker 拒绝。

GNU ld 官方文档规定，`NOCROSSREFS` 接收的是 **Output Section 名称**；如果这些 Section 之间存在交叉引用，ld 报错并返回非零状态。([Sourceware][1])

---

# 十八、非常重要：`NOCROSSREFS` 使用的是 Output Section

我们写：

```ld
NOCROSSREFS(.boot .app);
```

这里：

```text
.boot
.app
```

必须是：

# Output Section

不是：

```text
.boot_function
.app_function
```

这样的 Input Section。

所以必须理解：

```text
Input Section
     ↓
Output Section
     ↓
NOCROSSREFS
```

它不是直接对：

```text
.o 文件中的 Section
```

做限制。

---

# 十九、实验 30-6：验证是哪个引用触发了错误

虽然 linker 已经告诉我们有 cross reference，但我们还需要自己证明。

首先：

```bash
readelf -rW app.o
```

找到：

```text
boot_init
```

然后：

```bash
objdump -dr app.o
```

找到：

```text
app_main
    ↓
boot_init
```

最后：

```bash
nm -n boot.o
```

找到：

```text
boot_init
```

于是完整证据：

```text
app.o
  │
  ├── .app
  │
  └── relocation → boot_init
                       │
                       ▼
                     boot.o
                       │
                       ▼
                    .boot
```

所以：

```text
.app → .boot
```

就是非法依赖。

---

# 二十、实验 30-7：反方向调用

现在让 Bootloader 调 Application。

修改 `boot.c`：

```c
extern int app_task(void);

__attribute__((section(".boot")))
int boot_log(void)
{
    return 100;
}

__attribute__((section(".boot")))
int boot_init(void)
{
    return app_task();
}
```

现在：

```text
.boot
   │
   ▼
.app
```

---

# 二十一、重新编译

```bash
gcc \
    -ffreestanding \
    -fno-pie \
    -fno-stack-protector \
    -ffunction-sections \
    -fdata-sections \
    -c boot.c \
    -o boot.o
```

---

# 二十二、重新链接

仍然：

```ld
NOCROSSREFS(.boot .app);
```

执行：

```bash
ld \
    -T linker.ld \
    start.o \
    boot.o \
    app.o \
    -o nocross2.elf \
    -Map=nocross2.map
```

你仍然会得到：

```text
cross-reference error
```

因为：

```text
NOCROSSREFS
```

表达的是：

# 双向都禁止。

也就是：

```text
.boot → .app
.app  → .boot
```

都不允许。

---

# 二十三、`NOCROSSREFS` 的模型

可以画成：

```text
         NOCROSSREFS
              │
       ┌──────┴──────┐
       │             │
     .boot          .app
       │             │
       X─────────────X
       │             │
       └─────────────┘

禁止：
.boot → .app

禁止：
.app → .boot
```

所以：

```ld
NOCROSSREFS(.boot .app);
```

就是：

> `.boot` 和 `.app` 必须完全独立。

---

# 二十四、实验 30-8：真正需要的是“单向约束”

但真实 Bootloader/Application 经常不是：

```text
完全隔离
```

而是：

```text
Bootloader
    ↓
Application
```

允许某些方向。

比如：

```text
Bootloader
    ↓
Application Entry
```

但是：

```text
Application
    X
    ↓
Bootloader Internal
```

不允许。

这时候：

# `NOCROSSREFS()` 太严格。

需要：

# `NOCROSSREFS_TO()`。

---

# 二十五、`NOCROSSREFS_TO()` 的语义

GNU ld 文档说明：

```ld
NOCROSSREFS_TO(tosection fromsection ...)
```

表示：

> 第一个 Section 是禁止被后续 Section 引用的目标。

也就是说：

```ld
NOCROSSREFS_TO(.boot .app);
```

表达：

```text
.app
   │
   X
   ▼
.boot
```

禁止：

```text
.app → .boot
```

但：

```text
.boot → .app
```

不在这个规则的禁止方向内。([Sourceware][2])

---

# 二十六、这就是我们真正想要的架构

```text
┌───────────────┐
│  BOOTLOADER   │
│               │
│ boot_init()   │
└───────┬───────┘
        │
        │ allowed
        ▼
┌───────────────┐
│ APPLICATION   │
│               │
│ app_main()    │
└───────────────┘
```

但是：

```text
APPLICATION
      │
      X
      ▼
BOOTLOADER
```

---

# 二十七、实验 30-9：构造单向允许案例

让 `boot.c`：

```c
extern int app_task(void);

__attribute__((section(".boot")))
int boot_log(void)
{
    return 100;
}

__attribute__((section(".boot")))
int boot_init(void)
{
    return app_task();
}
```

让 `app.c`：

```c
__attribute__((section(".app")))
int app_task(void)
{
    return 10;
}

__attribute__((section(".app")))
int app_main(void)
{
    return app_task();
}
```

现在：

```text
.boot → .app
```

存在引用。

但是：

```text
.app → .boot
```

没有引用。

---

# 二十八、linker 改成：

```ld
ENTRY(_start)

MEMORY
{
    ROM (rx) : ORIGIN = 0x00400000, LENGTH = 64K
}

SECTIONS
{
    .text :
    {
        *(.text)
        *(.text.*)
    } > ROM

    .boot :
    {
        *(.boot)
    } > ROM

    .app :
    {
        *(.app)
    } > ROM
}

NOCROSSREFS_TO(.boot .app);
```

注意顺序：

```text
TO:
.boot

FROM:
.app
```

---

# 二十九、链接

```bash
ld \
    -T linker.ld \
    start.o \
    boot.o \
    app.o \
    -o one-way.elf \
    -Map=one-way.map
```

理论结果：

```text
成功。
```

因为：

```text
.boot → .app
```

允许。

---

# 三十、制造反方向违规

现在修改 `app.c`：

```c
extern int boot_init(void);

__attribute__((section(".app")))
int app_task(void)
{
    return 10;
}

__attribute__((section(".app")))
int app_main(void)
{
    return boot_init();
}
```

现在：

```text
.app
  │
  ▼
.boot
```

---

# 三十一、重新编译

```bash
gcc \
    -ffreestanding \
    -fno-pie \
    -fno-stack-protector \
    -ffunction-sections \
    -fdata-sections \
    -c app.c \
    -o app.o
```

然后：

```bash
ld \
    -T linker.ld \
    start.o \
    boot.o \
    app.o \
    -o one-way-bad.elf \
    -Map=one-way-bad.map
```

现在应该：

```text
失败。
```

这就是：

# `NOCROSSREFS_TO()` 的价值。

---

# 三十二、实验 30-10：把引用链完整画出来

使用：

```bash
objdump -dr app.o
```

你会得到：

```text
app_main
   │
   │ relocation
   ▼
boot_init
```

再：

```bash
nm -n boot.o | grep boot_init
```

确认：

```text
boot_init
```

属于：

```text
.boot
```

于是：

```text
.app
  │
  ├── app_main
  │
  └── relocation
           │
           ▼
       boot_init
           │
           ▼
         .boot
```

而：

```ld
NOCROSSREFS_TO(.boot .app);
```

检测到：

```text
from = .app
to = .boot
```

于是：

```text
ERROR
```

---

# 三十三、实验 30-11：`ASSERT()` 登场

现在我们回到另一个 linker 强大功能：

```ld
ASSERT(expression, "message");
```

例如：

```ld
ASSERT(
    SIZEOF(.boot) <= 0x4000,
    "ERROR: bootloader too large"
);
```

意思：

```text
.boot > 16 KB
        ↓
链接失败
```

---

# 三十四、制造 Bootloader 大小限制

linker：

```ld
.boot :
{
    __boot_start = .;

    *(.boot)

    __boot_end = .;
} > ROM
```

然后：

```ld
ASSERT(
    (__boot_end - __boot_start) <= 0x4000,
    "ERROR: bootloader exceeds 16K"
);
```

---

# 三十五、为什么使用 Symbol 差值？

因为：

```text
__boot_end
-
__boot_start
```

就是：

```text
.boot size
```

所以：

```ld
ASSERT(
    (__boot_end - __boot_start) <= 0x4000,
    "ERROR: bootloader exceeds 16K"
);
```

本质就是：

```text
if (.boot_size > 16K)
    link_error();
```

---

# 三十六、实验 30-12：故意让 ASSERT 失败

可以简单加入：

```ld
ASSERT(
    SIZEOF(.boot) == 0,
    "ERROR: test ASSERT failed"
);
```

链接：

```bash
ld \
    -T linker.ld \
    start.o \
    boot.o \
    app.o \
    -o assert.elf \
    -Map=assert.map
```

必然失败。

这一步的意义是：

> **先验证 ASSERT 的机制，再写真正的约束。**

---

# 三十七、ASSERT 的几个典型应用

## 1. ROM 容量

```ld
ASSERT(
    __image_end <= __rom_end,
    "ERROR: firmware exceeds ROM"
);
```

---

## 2. RAM 容量

```ld
ASSERT(
    __bss_end <= __ram_end,
    "ERROR: RAM overflow"
);
```

---

## 3. Stack

```ld
ASSERT(
    __heap_start < __stack_bottom,
    "ERROR: heap overlaps stack"
);
```

---

## 4. Bootloader

```ld
ASSERT(
    SIZEOF(.boot) <= 0x8000,
    "ERROR: bootloader exceeds 32K"
);
```

---

## 5. Application

```ld
ASSERT(
    SIZEOF(.app) <= 0x70000,
    "ERROR: application too large"
);
```

---

# 三十八、实验 30-13：建立真实 Boot/App Memory Layout

现在把 ROM 分成两个逻辑区域：

```ld
MEMORY
{
    BOOT_ROM (rx) :
        ORIGIN = 0x00400000,
        LENGTH = 32K

    APP_ROM (rx) :
        ORIGIN = 0x00408000,
        LENGTH = 480K

    RAM (rw) :
        ORIGIN = 0x00600000,
        LENGTH = 64K
}
```

然后：

```ld
.boot :
{
    __boot_start = .;

    *(.boot)

    __boot_end = .;
} > BOOT_ROM
```

Application：

```ld
.app :
{
    __app_start = .;

    *(.app)

    __app_end = .;
} > APP_ROM
```

---

# 三十九、加入容量检查

```ld
ASSERT(
    SIZEOF(.boot) <= LENGTH(BOOT_ROM),
    "ERROR: bootloader overflow"
);

ASSERT(
    SIZEOF(.app) <= LENGTH(APP_ROM),
    "ERROR: application overflow"
);
```

现在 linker 本身成为：

```text
Bootloader partition checker
```

和：

```text
Application partition checker
```

---

# 四十、Map 文件现在应该怎么分析？

链接成功以后：

```bash
less one-way.map
```

重点找到：

```text
.boot
.app
```

例如：

```text
.boot
    0x00400000
    0x00000150

.app
    0x00408000
    0x00000080
```

然后检查：

```text
BOOT_ROM
0x00400000
    +
0x8000
=
0x00408000
```

正好：

```text
BOOT_ROM end
=
APP_ROM start
```

这就是非常典型的：

# Firmware Partition Layout

---

# 四十一、实验 30-14：验证 Output Section 的地址

```bash
readelf -SW firmware.elf
```

观察：

```text
.boot
.app
```

然后：

```bash
objdump -h firmware.elf
```

对比：

```text
VMA
LMA
Size
```

---

# 四十二、实验 30-15：验证引用

```bash
readelf -rW app.o
```

寻找：

```text
boot_init
```

然后：

```bash
objdump -dr app.o
```

得到：

```text
app_main
   ↓
relocation
   ↓
boot_init
```

这是：

```text
源码
 ↓
机器码
 ↓
relocation
 ↓
linker
```

最完整的一次验证。

---

# 四十三、为什么 `readelf -rW firmware.elf` 可能看不到这些 relocation？

因为：

```text
.o
```

是：

```text
relocatable object
```

其中：

```text
relocation
```

还没有被最终解析。

而：

```text
firmware.elf
```

是：

```text
final linked ELF
```

正常情况下，许多静态链接 relocation 已经被处理掉了。

所以研究：

```text
为什么 .app 引用了 .boot？
```

最直接的是：

```bash
readelf -rW app.o
```

而不是只看最终：

```bash
readelf -rW firmware.elf
```

---

# 四十四、这也是为什么 `objdump -dr` 特别好用

```bash
objdump -dr app.o
```

同时显示：

```text
-d
disassembly

-r
relocation
```

因此可以直接看到：

```text
汇编指令
+
对应 relocation
```

例如：

```text
call ...
    R_X86_64_PLT32 boot_init-0x4
```

这是分析：

```text
“谁调用了谁”
```

非常高效的方法。

---

# 四十五、实验 30-16：完整的 Bootloader/Application 规则

现在最终 linker：

```ld
ENTRY(_start)

MEMORY
{
    BOOT_ROM (rx) :
        ORIGIN = 0x00400000,
        LENGTH = 32K

    APP_ROM (rx) :
        ORIGIN = 0x00408000,
        LENGTH = 480K

    RAM (rw) :
        ORIGIN = 0x00600000,
        LENGTH = 64K
}

SECTIONS
{
    .text :
    {
        *(.text)
        *(.text.*)
    } > APP_ROM

    .boot :
    {
        __boot_start = .;

        *(.boot)

        __boot_end = .;
    } > BOOT_ROM

    .app :
    {
        __app_start = .;

        *(.app)

        __app_end = .;
    } > APP_ROM

    .data :
    {
        __data_start = .;

        *(.data)
        *(.data.*)

        __data_end = .;
    } > RAM AT > APP_ROM

    .bss :
    {
        __bss_start = .;

        *(.bss)
        *(.bss.*)
        *(COMMON)

        __bss_end = .;
    } > RAM
}

ASSERT(
    SIZEOF(.boot) <= LENGTH(BOOT_ROM),
    "ERROR: bootloader exceeds BOOT_ROM"
);

ASSERT(
    SIZEOF(.app) <= LENGTH(APP_ROM),
    "ERROR: application exceeds APP_ROM"
);

ASSERT(
    __bss_end <= ORIGIN(RAM) + LENGTH(RAM),
    "ERROR: RAM overflow"
);

NOCROSSREFS_TO(
    .boot
    .app
);
```

---

# 四十六、这里有一个重要的设计问题

上面的：

```ld
NOCROSSREFS_TO(.boot .app);
```

表达的是：

```text
.app → .boot
```

禁止。

但是：

```text
.boot → .app
```

允许。

这正好符合：

```text
Bootloader
     ↓
Application
```

的单向依赖模型。

但实际产品中，我们通常不会允许 Bootloader 直接依赖 Application 的**内部函数**。

所以更好的设计可能是：

```text
.boot
   │
   ▼
.boot_api
   │
   ▼
.app
```

或者：

```text
.boot
   │
   ▼
.shared
   ▲
   │
.app
```

这就引出了下一阶段的：

# `.shared` / API / ABI 边界设计。

---

# 四十七、实验 30-17：建立 Shared API 区域

创建：

```c
/* shared.c */

__attribute__((section(".shared")))
int system_version(void)
{
    return 1;
}
```

Boot：

```c
extern int system_version(void);

__attribute__((section(".boot")))
int boot_init(void)
{
    return system_version();
}
```

App：

```c
extern int system_version(void);

__attribute__((section(".app")))
int app_main(void)
{
    return system_version();
}
```

现在：

```text
.boot ─────┐
           │
           ▼
        .shared
           ▲
           │
.app ──────┘
```

这种结构更加合理。

---

# 四十八、架构图

最终：

```text
             ┌─────────────┐
             │   .boot     │
             └──────┬──────┘
                    │
                    ▼
             ┌─────────────┐
             │  .shared    │
             └──────▲──────┘
                    │
             ┌──────┴──────┐
             │    .app     │
             └─────────────┘
```

我们希望：

```text
.boot → .shared    OK
.app  → .shared    OK
```

但是：

```text
.boot → .app       X
.app  → .boot      X
```

这时候：

```ld
NOCROSSREFS(.boot .app);
```

就非常适合。

---

# 四十九、实验 30-18：完整双向隔离

增加：

```ld
NOCROSSREFS(
    .boot
    .app
);
```

这表示：

```text
.boot ↔ .app
```

完全隔离。

同时：

```text
.boot → .shared
.app → .shared
```

仍然允许。

这就是：

# 分层架构

而不是简单的：

# 两个孤立模块。

---

# 五十、实验 30-19：把 ASSERT 与 NOCROSSREFS 组合

现在我们拥有：

```text
容量约束：
ASSERT()

架构约束：
NOCROSSREFS()

单向约束：
NOCROSSREFS_TO()
```

于是 linker 可以表达：

```text
Bootloader：
    最大 32K

Application：
    最大 480K

RAM：
    最大 64K

Boot ↔ App：
    禁止互相调用

App → Boot：
    特别禁止

Boot → Shared：
    允许

App → Shared：
    允许
```

这已经是：

# Link-time Architecture Contract

---

# 五十一、实验 30-20：故意制造三个错误

## 错误 A：Bootloader 太大

```ld
ASSERT(
    SIZEOF(.boot) <= 0x10,
    "ERROR: bootloader too large"
);
```

结果：

```text
ld
 ↓
ERROR
```

---

## 错误 B：App 调 Boot

```text
.app
  ↓
boot_init
  ↓
.boot
```

结果：

```text
NOCROSSREFS_TO
 ↓
ERROR
```

---

## 错误 C：Boot 与 App 互相调用

```text
.boot → .app
.app → .boot
```

结果：

```text
NOCROSSREFS
 ↓
ERROR
```

这三个错误分别对应：

```text
容量
架构
方向
```

---

# 五十二、实验 30-21：Map 文件如何定位架构错误？

如果 linker 报：

```text
cross reference
```

第一步：

```bash
objdump -dr app.o
```

找：

```text
boot_init
```

第二步：

```bash
readelf -rW app.o
```

确认 relocation。

第三步：

```bash
nm -n boot.o
```

确认：

```text
boot_init
```

属于哪个 Input Section。

第四步：

```bash
readelf -SW app.o
```

确认：

```text
.app
```

第五步：

查看 linker：

```ld
.app : { *(.app) }
.boot : { *(.boot) }
```

最终形成：

```text
Input Section
      ↓
Output Section
      ↓
Relocation
      ↓
Cross-reference
      ↓
NOCROSSREFS
      ↓
ERROR
```

---

# 五十三、实验 30-22：Map 文件的一个重要认识

`NOCROSSREFS()` 失败时：

```text
firmware.elf
```

可能根本不会生成一个可用的最终 ELF。

因此不要把：

```text
Map
```

当成：

```text
一定存在的最终产物
```

具体行为和失败点取决于 linker 处理阶段。

更可靠的诊断来源是：

```text
1. linker error
2. .o relocation
3. linker script
4. map（如果已产生）
```

---

# 五十四、实验 30-23：完整验证命令表

### 查看 Input Section

```bash
objdump -h boot.o
objdump -h app.o
objdump -h shared.o
```

---

### 查看 relocation

```bash
readelf -rW boot.o
readelf -rW app.o
```

---

### 查看反汇编 + relocation

```bash
objdump -dr boot.o
objdump -dr app.o
```

---

### 查看最终 Section

```bash
readelf -SW firmware.elf
```

---

### 查看最终 Symbol

```bash
readelf -sW firmware.elf
```

---

### 查看 Segment

```bash
readelf -lW firmware.elf
```

---

### 查看 Map

```bash
less firmware.map
```

---

# 五十五、实验 30-24：为什么这些检查应该放到 linker？

考虑：

```text
Application
    ↓
Bootloader
```

如果只依赖：

```text
Code Review
```

开发者可能写：

```c
boot_init();
```

编译完全通过。

如果只依赖：

```text
Unit Test
```

测试可能没有覆盖：

```text
升级场景
```

但：

```ld
NOCROSSREFS_TO(.boot .app);
```

会让：

```text
CI
 ↓
ld
 ↓
FAIL
```

所以：

# 错误越早发现越好。

---

# 五十六、这就是 Linker Script 的“架构级”价值

传统理解：

```text
ld
=
把 .o 拼成 ELF
```

现在升级为：

```text
ld
=
地址布局
+
内存容量检查
+
Section 隔离
+
依赖方向检查
+
Firmware 架构约束
```

这也是为什么大型嵌入式项目的 linker script 往往非常复杂。

---

# 五十七、实验 30-25：最终 Firmware Architecture

我们最终可以设计：

```text
FLASH
┌────────────────────────────────────┐
│ BOOT                              │
│                                    │
│ .boot                              │
│                                    │
├────────────────────────────────────┤
│ SHARED                             │
│                                    │
│ .shared                            │
│                                    │
├────────────────────────────────────┤
│ APPLICATION                        │
│                                    │
│ .text                              │
│ .rodata                            │
│ .app                               │
│ .firmware_header                  │
│ .data image                       │
└────────────────────────────────────┘

RAM
┌────────────────────────────────────┐
│ .data                              │
│ .bss                               │
│ heap                               │
│                                    │
│ stack                              │
└────────────────────────────────────┘
```

架构规则：

```text
BOOT ───────→ SHARED
  │
  X
  │
  APPLICATION

APPLICATION ─→ SHARED
  │
  X
  │
  BOOT
```

这就是：

# Linker Enforced Architecture

---

# 五十八、实验 30-26：最终 linker.ld

建议这一节最终保存一个版本：

```ld
ENTRY(_start)

MEMORY
{
    BOOT_ROM (rx) :
        ORIGIN = 0x00400000,
        LENGTH = 32K

    APP_ROM (rx) :
        ORIGIN = 0x00408000,
        LENGTH = 480K

    RAM (rw) :
        ORIGIN = 0x00600000,
        LENGTH = 64K
}

SECTIONS
{
    /*
     * =========================
     * Bootloader
     * =========================
     */

    .boot :
    {
        __boot_start = .;

        *(.boot)
        *(.boot.*)

        __boot_end = .;
    } > BOOT_ROM


    /*
     * =========================
     * Shared
     * =========================
     */

    .shared :
    {
        __shared_start = .;

        *(.shared)
        *(.shared.*)

        __shared_end = .;
    } > APP_ROM


    /*
     * =========================
     * Application
     * =========================
     */

    .text :
    {
        __text_start = .;

        *(.text)
        *(.text.*)

        __text_end = .;
    } > APP_ROM

    .rodata :
    {
        __rodata_start = .;

        *(.rodata)
        *(.rodata.*)

        __rodata_end = .;
    } > APP_ROM

    .app :
    {
        __app_start = .;

        *(.app)
        *(.app.*)

        __app_end = .;
    } > APP_ROM


    /*
     * =========================
     * Data
     * =========================
     */

    .data :
    {
        __data_start = .;

        *(.data)
        *(.data.*)

        __data_end = .;
    } > RAM AT > APP_ROM


    /*
     * =========================
     * BSS
     * =========================
     */

    .bss :
    {
        __bss_start = .;

        *(.bss)
        *(.bss.*)
        *(COMMON)

        __bss_end = .;
    } > RAM


    /*
     * =========================
     * Memory constraints
     * =========================
     */

    ASSERT(
        SIZEOF(.boot) <= LENGTH(BOOT_ROM),
        "ERROR: bootloader exceeds BOOT_ROM"
    );

    ASSERT(
        SIZEOF(.app) <= LENGTH(APP_ROM),
        "ERROR: application exceeds APP_ROM"
    );

    ASSERT(
        __bss_end <=
        ORIGIN(RAM) + LENGTH(RAM),
        "ERROR: RAM overflow"
    );


    /*
     * =========================
     * Architecture constraints
     * =========================
     */

    NOCROSSREFS(
        .boot
        .app
    );
}
```

---

# 五十九、实验 30-27：如果要表达“只禁止 App → Boot”

把：

```ld
NOCROSSREFS(
    .boot
    .app
);
```

改成：

```ld
NOCROSSREFS_TO(
    .boot
    .app
);
```

语义变成：

```text
.app → .boot
```

禁止。

而：

```text
.boot → .app
```

允许。

官方文档特别强调，`NOCROSSREFS_TO()` 的第一个参数是 **to section**，后面的参数是来源 Section。([Sourceware][2])

这个参数顺序千万别写反。

---

# 六十、实验 30-28：最终完整验证链

## ① 编译

```bash
gcc -ffreestanding -fno-pie -fno-stack-protector \
    -ffunction-sections -fdata-sections \
    -c boot.c -o boot.o
```

```bash
gcc -ffreestanding -fno-pie -fno-stack-protector \
    -ffunction-sections -fdata-sections \
    -c app.c -o app.o
```

```bash
gcc -ffreestanding -fno-pie -fno-stack-protector \
    -ffunction-sections -fdata-sections \
    -c start.S -o start.o
```

---

## ② Input Section

```bash
objdump -h boot.o
objdump -h app.o
```

---

## ③ Relocation

```bash
readelf -rW app.o
```

---

## ④ 反汇编

```bash
objdump -dr app.o
```

---

## ⑤ Link

```bash
ld \
    -T linker.ld \
    start.o \
    boot.o \
    app.o \
    -o firmware.elf \
    -Map=firmware.map
```

---

## ⑥ Section

```bash
readelf -SW firmware.elf
```

---

## ⑦ Segment

```bash
readelf -lW firmware.elf
```

---

## ⑧ Symbol

```bash
readelf -sW firmware.elf
```

---

## ⑨ Map

```bash
less firmware.map
```

---

# 六十一、实验 30 最核心的知识对照

| 指令                 | 作用                           |
| ------------------ | ---------------------------- |
| `ASSERT()`         | 链接期表达式约束                     |
| `NOCROSSREFS()`    | 多个 Output Section 之间完全禁止交叉引用 |
| `NOCROSSREFS_TO()` | 禁止指定方向的引用                    |
| `readelf -rW`      | 查看 relocation                |
| `objdump -dr`      | 反汇编 + relocation             |
| `readelf -SW`      | 查看 Output Section            |
| `readelf -lW`      | 查看 Program Segment           |
| `nm -n`            | 快速查看 Symbol                  |
| `readelf -sW`      | 精确查看 Symbol Table            |
| `-Map=`            | 输出链接布局报告                     |

---

# 六十二、这节最重要的认知升级

以前：

```text
C
 ↓
Compiler
 ↓
Object
 ↓
Linker
 ↓
ELF
```

你可能认为：

> linker 只负责“算地址”。

现在可以把它理解成：

```text
C
 ↓
Compiler
 ↓
Object
 ↓
Relocation
 ↓
             ┌─────────────┐
             │     ld      │
             │             │
             │ 地址计算    │
             │ Section布局 │
             │ Segment布局 │
             │             │
             │ ASSERT      │
             │ NOCROSSREFS │
             │ NOCROSS_TO  │
             └──────┬──────┘
                    │
                    ▼
              Architecture
                Contract
                    │
              ┌─────┴─────┐
              ▼           ▼
             ELF        ERROR
```

所以：

# GNU ld 已经开始承担“架构守门员”的角色。

---

# 六十三、下一节：实验 31 —— `OVERLAY` + `AT` + `LOADADDR`：真正理解 Overlay

下一节我们继续沿着这条路线进入一个更高级、也更有意思的主题：

```text
Flash
─────────────────────────────
        Module A
        Module B
        Module C

RAM
─────────────────────────────
        同一个运行地址
             ▲
             │
      ┌──────┼──────┐
      │      │      │
     A      B      C
      │      │      │
      └──互斥运行───┘
```

也就是：

# `OVERLAY`

我们会做三个模块：

```text
.overlay_a
.overlay_b
.overlay_c
```

它们：

```text
LMA 不同
VMA 相同
```

然后研究：

```ld
OVERLAY :
{
    .ov_a { *(.ov_a) }
    .ov_b { *(.ov_b) }
    .ov_c { *(.ov_c) }
} > RAM AT > ROM
```

再验证：

```bash
readelf -SW
readelf -lW
objdump -h
nm
```

并研究 GNU ld 自动生成的：

```text
__load_start_xxx
__load_stop_xxx
```

以及：

```text
NOCROSSREFS()
```

为什么经常和 Overlay 一起出现。

最终实现：

```text
Flash
│
├── overlay A image
├── overlay B image
└── overlay C image
       │
       │ runtime copy
       ▼
RAM
┌──────────────────┐
│ shared address   │
│                  │
│ A / B / C        │
│ mutually         │
│ exclusive        │
└──────────────────┘
```

这会把我们在实验 26 学到的：

```text
VMA
LMA
AT
LOADADDR
```

与实验 30 的：

```text
NOCROSSREFS
```

真正组合起来，进入 GNU `ld` 的 **Overlay / 多镜像运行时装载**领域。

[1]: https://sourceware.org/binutils/docs/ld.pdf?utm_source=chatgpt.com "The GNU linker"
[2]: https://www.sourceware.org/binutils/docs/ld.pdf?utm_source=chatgpt.com "70                                                                 The GNU linker"

