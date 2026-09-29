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
		-c boot.c \
		-o boot.o
	gcc \
		-ffreestanding \
		-fno-pie \
		-fno-stack-protector \
		-ffunction-sections \
		-fdata-sections \
		-c app.c \
		-o app.o
lab2:
	ld \
		-T linker.ld \
		start.o \
		boot.o \
		app.o \
		-o normal.elf \
		-Map=normal.map
	readelf -SW normal.elf
	objdump -h normal.elf
lab3:
	objdump -dr app.o
lab4:
	gcc \
		-ffreestanding \
		-fno-pie \
		-fno-stack-protector \
		-ffunction-sections \
		-fdata-sections \
		-c app_lab4.c \
		-o app_lab4.o
	objdump -dr app_lab4.o
	readelf -rW app_lab4.o
	ld \
		-T linker.ld \
		start.o \
		boot.o \
		app_lab4.o \
		-o cross.elf \
		-Map=cross.map
lab5:
	gcc \
		-ffreestanding \
		-fno-pie \
		-fno-stack-protector \
		-ffunction-sections \
		-fdata-sections \
		-c app_lab4.c \
		-o app_lab4.o
	ld \
		-T linker_lab5.ld \
		start.o \
		boot.o \
		app_lab4.o \
		-o nocross.elf \
		-Map=nocross.map
