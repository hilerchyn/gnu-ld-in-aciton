lab1:
	gcc -ffreestanding -c start.S main.c
	readelf -SW start.o
	readelf -SW main.o
	ld \
		-T linker.ld \
		start.o \
		main.o \
		-o memory01.elf \
		-Map=memory01.map
	readelf -SW memory01.elf
	objdump -h memory01.elf
