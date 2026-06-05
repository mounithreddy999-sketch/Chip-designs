CC = riscv64-unknown-elf-gcc
OBJCOPY = riscv64-unknown-elf-objcopy

CFLAGS = -march=rv32imc -mabi=ilp32 -O2 -ffreestanding -nostdlib

all: firmware.hex

firmware.elf: start.S transformer_driver.c linker.ld
	$(CC) $(CFLAGS) -T linker.ld start.S transformer_driver.c -o firmware.elf

firmware.bin: firmware.elf
	$(OBJCOPY) -O binary firmware.elf firmware.bin

firmware.hex: firmware.bin bin2hex.py
	python3 bin2hex.py firmware.bin firmware.hex

clean:
	rm -f firmware.elf firmware.bin firmware.hex
