all:
	gcc -c start.S -o start.o
	gcc -ffreestanding -fno-pie -fno-stack-protector -c foo.c -o foo.o
	gcc -ffreestanding -fno-pie -fno-stack-protector -c bar.c -o bar.o
	gcc -ffreestanding -fno-pie -fno-stack-protector -c baz.c -o baz.o
	gcc -ffreestanding -fno-pie -fno-stack-protector -fdata-sections -ffunction-sections -c vector.c -o vector.o
	gcc -ffreestanding -fno-pie -fno-stack-protector -ffunction-sections -c main.c -o main.o
	ld \
	       --gc-sections \
       	       -T linker.ld \
	       start.o \
	       main.o \
	       foo.o \
	       bar.o \
	       baz.o \
	       vector.o \
	       -o vector01.elf \
	       -Map=vector01.map
step29:
	gcc -c start.S -o start.o
	gcc -ffreestanding -fno-pie -fno-stack-protector -ffunction-sections -c main.c -o main.o
	gcc -ffreestanding -fno-pie -fno-stack-protector -fdata-sections -ffunction-sections -c init_a.c -o init_a.o
	gcc -ffreestanding -fno-pie -fno-stack-protector -fdata-sections -ffunction-sections -c init_b.c -o init_b.o
	gcc -ffreestanding -fno-pie -fno-stack-protector -fdata-sections -ffunction-sections -c init_c.c -o init_c.o
	ld \
	       --gc-sections \
       	       -T linker29.ld \
	       start.o \
	       main.o \
	       foo.o \
	       init_a.o \
	       init_b.o \
	       init_c.o \
	       -o init-array.elf \
	       -Map=init-array.map
	grep -A 30 "\.init_array" init-array.map

