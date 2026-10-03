lab1:
	ld --version > default.ld
lab2:
	gcc \
	    -ffunction-sections \
	    -fdata-sections \
	    -g \
	    -c main.c \
	    -o main.o
	gcc \
		main.o \
		-Wl,-Map,default.map \
		-o default.elf
	readelf -SW default.elf
	objdump -h default.elf
lab4:
	gcc \
	    -ffunction-sections \
	    -fdata-sections \
	    -g \
	    -c header.c \
	    -o header.o
	objdump -h header.o
lab5:
	gcc \
	    main.o \
	    header.o \
	    -Wl,-Map,orphan.map \
	    -o orphan.elf
	readelf -SW orphan.elf
	readelf -SW orphan.elf | grep firmware
