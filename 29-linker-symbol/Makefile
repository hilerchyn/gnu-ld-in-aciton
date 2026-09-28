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
	ld \
		-T linker.ld \
		start.o \
		main.o \
		-o symbols.elf \
		-Map=symbols.map
	nm -n symbols.elf
lab2:
	nm -n symbols.elf
	readelf -sW symbols.elf

lab3:
	ld \
		-T linker.ld \
		start.o \
		main.o \
		-o absolute.elf \
		-Map=absolute.map
	nm -n absolute.elf | grep firmware
lab5:
	ld \
		-T linker_absolute.ld \
		start.o \
		main.o \
		-o absolute2.elf \
		-Map=absolute2.map
	readelf -sW absolute2.elf

lab6:
	ld \
		-T linker_provide.ld \
		start.o \
		main.o \
		-o provide.elf \
		-Map=provide.map
	nm -n provide.elf

lab7:
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
		-c main_lab7.c \
		-o main_lab7.o
	ld \
		-T linker_provide.ld \
		start.o \
		main_lab7.o \
		-o provide-ref.elf \
		-Map=provide-ref.map
	nm -n provide-ref.elf
