lab2:
	gcc \
		-ffreestanding \
		-fno-pie \
		-fno-stack-protector \
		-fdata-sections \
		-c metadata.c \
		-o metadata.o 
	objdump -h metadata.o
	objdump -s --section=.my_metadata metadata.o

lab3:
	gcc -c start.S -o start.o
	gcc \
		-ffreestanding \
		-fno-pie \
		-fno-stack-protector \
		-c main.c \
		-o main.o 
	gcc \
		-ffreestanding \
		-fno-pie \
		-fno-stack-protector \
		-fdata-sections \
		-c metadata.c \
		-o metadata.o 
	ld \
		-T insert.ld \
		start.o \
		main.o \
		metadata.o \
		-o insert01.elf \
		-Map=insert01.map
	readelf -S insert01.elf

lab4:
	gcc -c start.S -o start.o
	gcc \
		-ffreestanding \
		-fno-pie \
		-fno-stack-protector \
		-c main.c \
		-o main.o 
	gcc \
		-ffreestanding \
		-fno-pie \
		-fno-stack-protector \
		-fdata-sections \
		-c metadata.c \
		-o metadata.o 
	ld \
		-T insert_before.ld \
		start.o \
		main.o \
		metadata.o \
		-o insert02.elf \
		-Map=insert02.map
	readelf -S insert02.elf

lab7:
	gcc -c start.S -o start.o
	gcc \
		-ffreestanding \
		-fno-pie \
		-fno-stack-protector \
		-ffunction-sections \
		-fdata-sections \
		-c main_lab7.c \
		-o main.o 
	gcc \
		-ffreestanding \
		-fno-pie \
		-fno-stack-protector \
		-fdata-sections \
		-c metadata.c \
		-o metadata.o 
	ld \
		-T insert_before.ld \
		start.o \
		main.o \
		metadata.o \
		-o insert07.elf \
		-Map=insert07.map
	readelf -S insert07.elf
lab13:
	gcc -c start.S -o start.o
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
		-fdata-sections \
		-c metadata_lab13.c \
		-o metadata.o 
	ld \
		-T insert_lab13.ld \
		start.o \
		main.o \
		metadata.o \
		-o firmware.elf \
		-Map=firmware.map
	readelf -S firmware.elf

