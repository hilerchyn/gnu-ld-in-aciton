step04:
	gcc \
		-ffreestanding \
		-fno-pie \
		-fno-stack-protector \
		-ffunction-sections \
		-c orphan.c \
		-o orphan.o
	gcc \
		-ffreestanding \
		-fno-pie \
		-fno-stack-protector \
		-c main.c \
		-o main.o
	gcc \
		-c start.S -o start.o
step09:
	gcc \
		-ffreestanding \
		-fno-pie \
		-fno-stack-protector \
		-ffunction-sections \
		-c orphan.c \
		-o orphan.o
	gcc \
		-ffreestanding \
		-fno-pie \
		-fno-stack-protector \
		-c main.c \
		-o main.o
	gcc \
		-c start.S -o start.o
	ld \
		-T linker.ld \
		start.o \
		main.o \
		orphan.o \
		-o orphan01.elf \
		-Map=orphan01.map

step17:
	gcc \
		-ffreestanding \
		-fno-pie \
		-fno-stack-protector \
		-ffunction-sections \
		-c orphan.c \
		-o orphan.o
	gcc \
		-ffreestanding \
		-fno-pie \
		-fno-stack-protector \
		-c main.c \
		-o main.o
	gcc \
		-c start.S -o start.o
	ld \
		--orphan-handling=warn \
		-T linker17.ld \
		start.o \
		main.o \
		orphan.o \
		-o orphan02.elf \
		-Map=orphan02.map

