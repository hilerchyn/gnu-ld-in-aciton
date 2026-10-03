lab1:
	gcc -c a.c b.c c.c
	readelf -SW a.o
	readelf -SW b.o
	readelf -SW c.o
	gcc \
	    a.o \
	    b.o \
	    c.o \
	    main.c \
	    -Wl,-T,linker.ld \
	    -Wl,-Map=reverse.map \
	    -o reverse.elf
	grep -A20 -B2 '\.my_registry' reverse.map
	readelf -SW reverse.elf
	objdump -h reverse.elf
	objdump -s -j .my_registry reverse.elf
lab3:
	gcc \
	    c.o \
	    a.o \
	    b.o \
	    main.c \
	    -Wl,-T,linker-sort-none.ld \
	    -Wl,-Map=sort-none.map \
	    -o sort-none.elf
	grep -A20 -B2 '\.raw_registry' sort-none.map
lab4:
	gcc -c \
	    plugin_a.c \
	    plugin_b.c \
	    plugin_c.c
	readelf -SW plugin_a.o
	readelf -SW plugin_b.o
	readelf -SW plugin_c.o
	gcc \
	    plugin_a.o \
	    plugin_b.o \
	    plugin_c.o \
	    main_lab4.c \
	    -Wl,-T,linker_exclude.ld \
	    -Wl,-Map=exclude.map \
	    -o exclude.elf
	grep -A25 -B2 '\.plugin_registry' exclude.map
lab7:
	gcc \
	    -ffunction-sections \
	    -fdata-sections \
	    -c \
	    main_lab4.c \
	    plugin_http.c \
	    plugin_mqtt.c \
	    plugin_debug.c \
	    plugin_disabled.c
	gcc \
	    main_lab4.o \
	    plugin_http.o \
	    plugin_mqtt.o \
	    plugin_debug.o \
	    plugin_disabled.o \
	    -Wl,-T,linker_lab7.ld \
	    -Wl,--gc-sections \
	    -Wl,-Map=plugin.map \
	    -o plugin.elf
	readelf -SW plugin.elf
	readelf -SW plugin.elf | grep plugin
