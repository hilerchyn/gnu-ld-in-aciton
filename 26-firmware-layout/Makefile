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
            	-c data.c \
            	-o data.o
	gcc \
		-ffreestanding \
            	-fno-pie \
            	-fno-stack-protector \
            	-ffunction-sections \
            	-fdata-sections \
            	-c main.c \
            	-o main.o
	objdump -h start.o
	objdump -h main.o
	objdump -h data.o
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
            	-c data.c \
            	-o data.o
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
		data.o \
		-o firmware.elf \
		-Map=firmware.map
	readelf -SW firmware.elf
	objdump -h firmware.elf
	readelf -lW firmware.elf
lab4:
	nm -n firmware.elf

lab5:
	ld \
		-T linker_lab5.ld \
		start.o \
		main.o \
		data.o \
		-o firmware_lab5.elf \
		-Map=firmware_lab5.map
	nm -n firmware_lab5.elf
lab8:
	ld \
		-T linker_lab5.ld \
		start.o \
		main.o \
		data.o \
		-o firmware_lab8.elf \
		-Map=firmware_lab8.map
	nm -n firmware_lab8.elf

lab9:
	ld \
		-T linker_lab5.ld \
		start.o \
		main.o \
		data.o \
		-o firmware_lab9.elf \
		-Map=firmware_lab9.map
	objcopy \
		-O binary \
		firmware_lab9.elf \
		firmware_lab9.bin
	ls -lh firmware_lab9.elf firmware_lab9.bin
	xxd firmware_lab9.bin | head -n 40
	hexdump -C firmware_lab9.bin | head -n 40

lab11:
	objdump -d firmware_lab9.elf
	objdump -s -j .text firmware_lab9.elf
	hexdump -C firmware_lab9.bin
lab12:
	objdump -s -j .text firmware_lab9.elf
	objdump -s -j .data firmware_lab9.elf
