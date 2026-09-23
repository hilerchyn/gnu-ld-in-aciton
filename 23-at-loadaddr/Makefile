lab1:
	gcc \
		-ffreestanding \
		-fno-pie \
		-fno-stack-protector \
		-fdata-sections \
		-c data.c \
		-o data.o
lab2:
	gcc \
		-ffreestanding \
		-fno-pie \
		-fno-stack-protector \
		-ffunction-sections \
		-c main.c \
		-o main.o

lab4:
	gcc -c start.S -o start.o
	ld \
	    -T linke.ld \
	    start.o \
	    main.o \
	    data.o \
	    -o bad-data.elf \
	    -Map=bad-data.map

lab5:
	ld \
	    -T linker_lab5.ld \
	    start.o \
	    main.o \
	    data.o \
	    -o data-at.elf \
	    -Map=data-at.map

lab6:
	ld \
	    -T linker_lab6.ld \
	    start.o \
	    main.o \
	    data.o \
	    -o data-symbols.elf \
	    -Map=data-symbols.map




