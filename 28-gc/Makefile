lab2:
	gcc \
	    -ffreestanding \
	    -fno-pie \
	    -fno-stack-protector \
	    -ffunction-sections \
	    -fdata-sections \
	    -c start.S \
	    -o start.o
	gcc \
	    -ffreestanding \
	    -fno-pie \
	    -fno-stack-protector \
	    -ffunction-sections \
	    -fdata-sections \
	    -c main.c \
	    -o main.o
	gcc \
	    -ffreestanding \
	    -fno-pie \
	    -fno-stack-protector \
	    -ffunction-sections \
	    -fdata-sections \
	    -c functions.c \
	    -o functions.o
	gcc \
	    -ffreestanding \
	    -fno-pie \
	    -fno-stack-protector \
	    -ffunction-sections \
	    -fdata-sections \
	    -c data.c \
	    -o data.o
	objdump -h functions.o
	objdump -h data.o
lab4:
	ld \
	    -T linker.ld \
	    start.o \
	    main.o \
	    functions.o \
	    data.o \
	    -o no-gc.elf \
	    -Map=no-gc.map
	readelf -SW no-gc.elf
	nm -n no-gc.elf
lab5:
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
	readelf -SW gc.elf
	nm -n gc.elf
lab10:
	ld \
            --gc-sections \
	    --print-gc-sections \
	    -T linker_lab10.ld \
	    start.o \
	    main.o \
	    functions.o \
	    data.o \
	    -o keep.elf \
	    -Map=keep.map
	nm -n keep.elf | grep firmware
lab11:
	ld \
            --gc-sections \
	    -T linker_lab11.ld \
	    start.o \
	    main.o \
	    functions.o \
	    data.o \
	    -o discard.elf
	readelf -SW discard.elf
