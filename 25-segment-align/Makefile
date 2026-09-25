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
	ld \
		-T linker.ld \
		start.o \
		main.o \
		data.o \
		-o default.elf \
		-Map=default.map
	readelf -lW default.elf
lab5:
	ld \
		-T linker-maxpage.ld -z max-page-size=4096 -z noexecstack \
		start.o \
		main.o \
		data.o \
		-o maxpage.elf \
		-Map=maxpage.map
	readelf -lW maxpage.elf
