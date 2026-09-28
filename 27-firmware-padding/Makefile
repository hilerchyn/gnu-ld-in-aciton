lab1:
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
	    -c data.c \
	    -o data.o
	objdump -h data.o


lab2:
	ld \
	    -T linker.ld \
	    start.o \
	    main.o \
	    data.o \
	    -o align0.elf \
	    -Map=align0.map
	readelf -SW align0.elf
	ld \
	    -T linker_lab2_100.ld \
	    start.o \
	    main.o \
	    data.o \
	    -o align100.elf \
	    -Map=align100.map
	readelf -SW align100.elf
	objdump -s -j .text align100.elf
lab6:
	ld \
	    -T linker_lab2_100.ld \
	    start.o \
	    main.o \
	    data.o \
	    -o fill2.elf \
	    -Map=fill2.map
	readelf -SW fill2.elf
	objdump -s -j .text fill2.elf
lab8:
	ld \
	    -T linker_lab8.ld \
	    start.o \
	    main.o \
	    data.o \
	    -o header.elf \
	    -Map=header.map
	readelf -SW header.elf
	objdump -s -j .firmware_header header.elf
