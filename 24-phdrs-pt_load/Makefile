lab1:
	gcc \
		-ffreestanding \
		-fno-pie \
		-fno-stack-protector \
		-ffunction-sections \
		-fdata-sections \
		-c start.S -o start.o
	gcc \
		-ffreestanding \
		-fno-pie \
		-fno-stack-protector \
		-ffunction-sections \
		-fdata-sections \
		-c main.c -o main.o
	gcc \
		-ffreestanding \
		-fno-pie \
		-fno-stack-protector \
		-ffunction-sections \
		-fdata-sections \
		-c data.c -o data.o
	ld \
		-T linker_default.ld \
		start.o \
		main.o \
		data.o \
		-o default.elf \
		-Map=default.map
	readelf -S default.elf

lab2:
	gcc \
		-ffreestanding \
		-fno-pie \
		-fno-stack-protector \
		-ffunction-sections \
		-fdata-sections \
		-c start.S -o start.o
	gcc \
		-ffreestanding \
		-fno-pie \
		-fno-stack-protector \
		-ffunction-sections \
		-fdata-sections \
		-c main.c -o main.o
	gcc \
		-ffreestanding \
		-fno-pie \
		-fno-stack-protector \
		-ffunction-sections \
		-fdata-sections \
		-c data.c -o data.o
	ld \
		-T linker_phdrs.ld \
		start.o \
		main.o \
		data.o \
		-o phdrs01.elf \
		-Map=phdrs01.map
	readelf -l phdrs01.elf

