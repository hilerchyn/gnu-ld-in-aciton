#!/bin/bash

gcc \
    -fno-asynchronous-unwind-tables \
    -fno-unwind-tables \
    -c main.c \
    -o main.o


gcc -c start.S -o start.o

ld \
    -T linker.ld \
    start.o \
    main.o \
    -o custom.elf \
    -Map=custom.map \
    --verbose

