# GNU ld 从零到精通 · 实验 01

# 不依赖 GCC：从 `.o` 到 ELF，亲手理解 GNU ld

这一节我们先不碰复杂的 `linker.ld`，目标只有一个：

> **亲眼看到：编译器生成 `.o` → `ld` 解析符号 → 合并 Section → 生成 ELF。**

---

# 🎯 实验目标

完成下面这个流程：

```text
main.c
   │
   │ gcc -c
   ▼
main.o
   │
   │ ld
   ▼
hello.elf
   │
   ├── readelf
   ├── objdump
   └── nm
```

并理解：

1. `.o` 文件到底是什么
2. `ld` 如何解决符号
3. `.text` 如何进入最终 ELF
4. ELF Entry Point 是什么
5. 为什么直接 `ld main.o` 往往不能得到一个能正常运行的 Linux 程序

---

# 一、先准备最简单的 C 程序

创建：

```text
01-hello-ld/
└── main.c
```

`main.c`：

```c
int main(void)
{
    return 42;
}
```

先只编译，不链接：

```bash
gcc -c main.c -o main.o
```

目录变成：

```text
01-hello-ld
│
├── main.c
└── main.o
```

这里最重要的一点：

```text
gcc -c
```

只做：

```text
C
↓
Compiler
↓
Assembly
↓
Assembler
↓
Object File
```

不会调用最终链接器。

---

# 二、查看 `.o` 文件

执行：

```bash
file main.o
```

通常会看到类似：

```text
main.o: ELF 64-bit LSB relocatable
```

注意：

# ⭐ relocatable

这说明：

```text
main.o
```

还不是最终程序。

它里面还有：

```text
未确定地址

未完成重定位

未解决符号
```

脑图：

```text
main.o
│
├── ELF
│
├── Relocatable Object
│
├── Sections
│
├── Symbols
│
└── Relocations
```

---

# 三、使用 readelf 查看 ELF Header

执行：

```bash
readelf -h main.o
```

重点看：

```text
Type:
```

通常：

```text
Type: REL (Relocatable file)
```

也就是说：

```text
main.o

ELF Type = ET_REL
```

脑图：

```text
ELF
│
├── ET_REL
│   └── .o
│
├── ET_EXEC
│   └── 可执行文件
│
├── ET_DYN
│   └── .so / PIE
│
└── ET_CORE
    └── Core Dump
```

---

# 四、查看 Section

执行：

```bash
readelf -S main.o
```

你会看到类似：

```text
.text

.data

.bss

.symtab

.strtab

.rela.text
```

现在建立第一个真正重要的模型：

```text
main.o
│
├── .text
│      │
│      └── 机器指令
│
├── .data
│      │
│      └── 已初始化全局变量
│
├── .bss
│      │
│      └── 未初始化全局变量
│
├── .symtab
│      │
│      └── Symbol Table
│
└── .rela.*
       │
       └── Relocation
```

---

# 五、查看机器代码

执行：

```bash
objdump -d main.o
```

你会看到类似：

```text
0000000000000000 <main>:

0: 55
1: 48 89 e5
...
```

这里有一个非常重要的现象：

```text
main 地址 = 0
```

为什么？

因为：

```text
main.o
```

还没有被放到最终内存地址。

所以：

```text
0
```

只是：

```text
.text Section 内的 Offset
```

不是最终运行地址。

---

# 六、查看 Symbol

执行：

```bash
nm main.o
```

你会看到：

```text
0000000000000000 T main
```

含义：

```text
00000000
    │
    ▼
Symbol Address / Offset

T
│
▼
Text Section

main
│
▼
函数名
```

也就是说：

```text
main
```

在：

```text
.text
```

里面。

---

# 七、第一次直接使用 ld

现在尝试：

```bash
ld main.o -o hello
```

可能出现：

```text
warning: cannot find entry symbol _start
```

为什么？

因为 Linux 程序真正的启动流程不是：

```text
CPU
↓
main()
```

而是：

```text
Kernel
↓
_start
↓
C Runtime
↓
初始化环境
↓
main()
↓
exit()
```

所以：

```text
main()
```

不是 ELF 的真正 Entry Point。

---

# 八、理解 `_start`

真正的 Linux 程序通常是：

```text
ELF Entry Point
       │
       ▼
     _start
       │
       ▼
CRT Startup Code
       │
       ▼
初始化 argc
初始化 argv
初始化 libc
       │
       ▼
     main()
       │
       ▼
    exit()
```

所以：

# ⭐ `main()` 是 C 语言入口

而：

# ⭐ `_start` 是程序入口

这两个概念千万不要混。

---

# 九、自己写 `_start`

创建：

```text
start.S
```

x86-64 Linux：

```asm
.global _start

_start:

    call main

    mov %eax, %edi

    mov $60, %eax

    syscall
```

这个程序非常简单。

逻辑：

```text
_start
   │
   ▼
main()
   │
   ▼
返回值
   │
   ▼
exit(return_value)
```

---

# 十、编译 start.S

执行：

```bash
gcc -c start.S -o start.o
```

现在：

```text
01-hello-ld
│
├── main.c
├── main.o
├── start.S
└── start.o
```

查看：

```bash
nm start.o
```

你会看到：

```text
0000000000000000 T _start
                 U main
```

现在终于出现了最重要的链接器模型。

```text
start.o

Defined:

_start

Undefined:

main
```

而：

```text
main.o

Defined:

main
```

所以：

```text
start.o
    │
    │ needs main
    ▼
Undefined Symbol
    │
    ▼
main.o
    │
    ▼
Defined Symbol
```

`ld` 的任务之一：

```text
Symbol Resolution
```

---

# 十一、真正执行链接

执行：

```bash
ld start.o main.o -o hello
```

现在：

```text
hello
```

已经生成。

查看：

```bash
file hello
```

通常：

```text
ELF 64-bit LSB executable
```

注意现在变成：

```text
Executable
```

而不再是：

```text
Relocatable
```

---

# 十二、查看 ELF Header

执行：

```bash
readelf -h hello
```

重点：

```text
Type: EXEC
```

还有：

```text
Entry point address:
```

例如：

```text
Entry point address: 0x401000
```

脑图：

```text
hello ELF

Entry Point
    │
    ▼
0x401000
    │
    ▼
_start
```

---

# 十三、验证 `_start` 是否真的在 Entry Point

执行：

```bash
nm hello
```

例如：

```text
0000000000401000 T _start
0000000000401011 T main
```

然后：

```text
Entry Point

0x401000
```

以及：

```text
_start

0x401000
```

完全一致。

所以：

```text
ELF Entry Point
       │
       ▼
_start
```

---

# 十四、objdump 查看最终代码

执行：

```bash
objdump -d hello
```

你会看到：

```text
0000000000401000 <_start>:

401000:
```

然后：

```text
call 4010xx <main>
```

这说明：

原来：

```text
start.o

call main
```

还是：

```text
Symbol Reference
```

经过：

```text
ld
```

之后：

```text
call 0x4010xx
```

变成了具体地址。

这就是：

# ⭐ Relocation

---

# 十五、整个链接过程第一次完整展开

现在我们已经可以画出：

```text
                C Source
                   │
                   ▼
                Compiler
                   │
                   ▼
                 main.o
                   │
                   │
                   │ Defines main
                   │
                   ▼
                GNU ld
                   ▲
                   │
                   │ Undefined main
                   │
                 start.o
                   │
                   │ Defines _start
                   │
                   ▼
              Symbol Resolution
                   │
                   ▼
              Section Merge
                   │
                   ▼
              Address Layout
                   │
                   ▼
               Relocation
                   │
                   ▼
                 hello
                   │
                   ▼
                ELF EXEC
```

---

# 十六、查看最终 Section

执行：

```bash
readelf -S hello
```

你会看到类似：

```text
.text
```

可能还有：

```text
.symtab

.strtab
```

我们的程序非常小，所以没有复杂的：

```text
libc

.dynamic

.got

.plt
```

这正是这个实验的价值：

# ⭐ 先理解最纯粹的 ld。

---

# 十七、Map File：第一次观察链接器内部布局

重新链接：

```bash
ld start.o main.o \
   -o hello \
   -Map=hello.map
```

现在：

```text
hello.map
```

出现。

目录：

```text
01-hello-ld
│
├── main.c
├── main.o
├── start.S
├── start.o
├── hello
└── hello.map
```

查看：

```bash
cat hello.map
```

你会看到类似：

```text
.text
0x0000000000401000
```

下面：

```text
start.o
```

然后：

```text
main.o
```

模型：

```text
.text
│
├── start.o(.text)
│
└── main.o(.text)
```

这就是：

# ⭐ Input Section → Output Section

---

# 十八、Map 文件如何阅读？

重点看：

```text
.text
```

你可能看到：

```text
.text           0x0000000000401000

start.o
    .text

main.o
    .text
```

翻译：

```text
最终 ELF

.text
│
├── 地址 0x401000
│
├── start.o 的 .text
│
└── main.o 的 .text
```

所以：

```text
多个 Input Sections
         │
         ▼
一个 Output Section
```

---

# 十九、这个实验最重要的 6 个知识点

记住：

```text
① .o 是 ET_REL

② .o 中地址通常只是 Section Offset

③ Symbol 可以是 Defined / Undefined

④ ld 负责 Symbol Resolution

⑤ ld 负责 Relocation

⑥ _start ≠ main
```

---

# 二十、最终实验目录

```text
01-hello-ld
│
├── main.c
│
├── start.S
│
├── main.o
│
├── start.o
│
├── hello
│
└── hello.map
```

---

# 🔥 完整命令

```bash
gcc -c main.c -o main.o

gcc -c start.S -o start.o

ld \
    start.o \
    main.o \
    -o hello \
    -Map=hello.map
```

运行：

```bash
./hello

echo $?
```

应该得到：

```text
42
```

---

# 🧠 本实验最终脑图

```text
GNU ld 实验 01
│
├── Source
│   │
│   ├── main.c
│   └── start.S
│
├── Compile
│   │
│   ├── main.o
│   └── start.o
│
├── Object File
│   │
│   ├── Sections
│   │
│   ├── Symbols
│   │
│   └── Relocations
│
├── Symbol Resolution
│   │
│   ├── start.o
│   │       │
│   │       └── U main
│   │
│   └── main.o
│           │
│           └── T main
│
├── ld
│   │
│   ├── Merge Sections
│   │
│   ├── Assign Addresses
│   │
│   ├── Resolve Symbols
│   │
│   └── Relocation
│
└── ELF
    │
    ├── Entry Point
    │       │
    │       └── _start
    │
    ├── .text
    │
    └── hello
```

---

# 🚀 下一实验预告：实验 02

下一步我们进入真正的 **Linker Script**：

```text
02-custom-linker-script
│
├── main.c
├── start.S
└── linker.ld
```

核心实验：

```ld
SECTIONS
{
    . = 0x100000;

    .text :
    {
        *(.text)
    }

    .data :
    {
        *(.data)
    }

    .bss :
    {
        *(.bss)
    }
}
```

然后用：

```bash
readelf
objdump
nm
map
```

亲眼验证：

# **Linker Script 如何决定 `.text`、`.data`、`.bss` 的地址。**

这一步开始，你就真正进入 GNU `ld` 最核心的世界了。

