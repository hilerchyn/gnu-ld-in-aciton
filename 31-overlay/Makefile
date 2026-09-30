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
	    -c overlay_a.c \
	    -o overlay_a.o
	gcc \
	    -ffreestanding \
	    -fno-pie \
	    -fno-stack-protector \
	    -ffunction-sections \
	    -fdata-sections \
	    -c overlay_b.c \
	    -o overlay_b.o
	gcc \
	    -ffreestanding \
	    -fno-pie \
	    -fno-stack-protector \
	    -ffunction-sections \
	    -fdata-sections \
	    -c overlay_c.c \
	    -o overlay_c.o
	objdump -h overlay_a.o
	objdump -h overlay_b.o
	objdump -h overlay_c.o
lab2:
	ld \
	    -T linker.ld \
	    start.o \
	    main.o \
	    overlay_a.o \
	    overlay_b.o \
	    overlay_c.o \
	    -o normal-overlay.elf \
	    -Map=normal-overlay.map
	objdump -h normal-overlay.elf
lab3:
	ld \
	    -T linker_lab3.ld \
	    start.o \
	    main.o \
	    overlay_a.o \
	    overlay_b.o \
	    overlay_c.o \
	    -o overlay.elf \
	    -Map=overlay.map
	readelf -SW overlay.elf
	nm -n overlay.elf
	
