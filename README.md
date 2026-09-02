# 《GNU ld 从零到精通：10 个递进式实战实验》


包含：

```
01-hello-ld
     ├── main.c
     ├── start.S
     └── linker.ld

02-symbol
     ├── symbol.c
     └── linker.ld

03-sections
     ├── main.c
     └── linker.ld

04-rom-ram
     ├── start.S
     ├── main.c
     └── linker.ld

05-data-copy
     ├── startup.S
     ├── main.c
     └── linker.ld

06-gc-sections
07-static-library
08-partial-link
09-elf-phdr
10-map-file-debug
```


每个实验都配：

源码 → 编译命令 → ld 工作过程 → readelf 验证 → objdump 验证 → map 文件分析 → 脑图

这样学完，你基本就能真正“驾驭” GNU ld，而不是只会看 linker script。

