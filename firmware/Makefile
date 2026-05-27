# firmware/Makefile — Build ternarycore-secure firmware
# Run from firmware/ directory: cd firmware && make

CROSS = riscv64-elf-
CC    = $(CROSS)gcc
OBJCOPY = $(CROSS)objcopy
OBJDUMP = $(CROSS)objdump

ARCH_FLAGS = -march=rv32im -mabi=ilp32 -mstrict-align
CFLAGS  = -Os -Wall -nostdlib -nostartfiles -ffreestanding
CFLAGS += -I. $(ARCH_FLAGS)

LDFLAGS = -Wl,-T,link.ld -Wl,-Map,firmware.map -nostdlib -static $(ARCH_FLAGS) -lgcc

SRCS = startup.S main.c trng.c sha256.c secp256k1.c keystore.c
OBJS = startup.o main.o trng.o sha256.o secp256k1.o keystore.o

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
