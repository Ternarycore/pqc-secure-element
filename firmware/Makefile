# firmware/Makefile — Build ternarycore-secure firmware
# Run from firmware/ directory: cd firmware && make

CROSS = riscv64-elf-
CC    = $(CROSS)gcc
OBJCOPY = $(CROSS)objcopy
OBJDUMP = $(CROSS)objdump

ARCH_FLAGS = -march=rv32i -mabi=ilp32 -mstrict-align
CFLAGS  = -Os -Wall -nostdlib -nostartfiles -ffreestanding
CFLAGS += -I. $(ARCH_FLAGS)

LDFLAGS = -Wl,-T,link.ld -Wl,-Map,firmware.map -nostdlib -static $(ARCH_FLAGS)

SRCS = startup.S main.c
OBJS = startup.o main.o

TARGET = firmware.elf
HEX    = firmware.hex
LST    = firmware.lst
HEX32  = firmware_words.hex

.PHONY: all clean

all: $(HEX32)

$(HEX): $(TARGET)
	$(OBJCOPY) -O verilog -R .data $< $@

$(HEX32): $(HEX) hex2words.py
	python3 hex2words.py $< $@

$(LST): $(TARGET)
	$(OBJDUMP) -d $< > $@

$(TARGET): $(OBJS) link.ld
	$(CC) $(CFLAGS) -o $@ $(OBJS) $(LDFLAGS)
	$(MAKE) $(LST)

%.o: %.S
	$(CC) $(CFLAGS) -c -o $@ $<

%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<

clean:
	rm -f *.o *.elf *.hex *.lst *.map
