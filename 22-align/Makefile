step04:
	gcc -ffreestanding -fno-pie -fno-stack-protector \
		-c a.c -o a.o
	gcc -ffreestanding -fno-pie -fno-stack-protector \
		-c b.c -o b.o
	gcc -ffreestanding -fno-pie -fno-stack-protector \
		-c c.c -o c.o
	gcc -ffreestanding -fno-pie -fno-stack-protector \
		-c start.S -o start.o
	gcc -ffreestanding -fno-pie -fno-stack-protector \
		-c main.c -o main.o
	ld -T linker.ld \
		start.o \
		main.o \
		a.o \
		b.o \
		c.o \
		-o align01.elf \
		-Map=align01.map
	readelf -S align01.elf

