# CoreMark RISC-V bare-metal build Makefile

# RV32 configuration, kept here for manual switching if needed.
# ARCH_TYPE      := rv32
# CROSS_COMPILE  ?= riscv32-unknown-elf-
# MARCH          := rv32im_zicsr
# MABI           := ilp32

ARCH_TYPE      := rv64
CROSS_COMPILE  ?= riscv64-unknown-elf-
MARCH          := rv64im_zicsr
MABI           := lp64

CC             := $(CROSS_COMPILE)gcc
OBJCOPY        := $(CROSS_COMPILE)objcopy
OBJDUMP        := $(CROSS_COMPILE)objdump
SIZE           := $(CROSS_COMPILE)size

ifeq ($(ARCH_TYPE),rv64)
    RAM_WIDTH := 64
else
    RAM_WIDTH := 32
endif

CFLAGS         := -march=$(MARCH) -mabi=$(MABI)
CFLAGS         += -O2
CFLAGS         += -ffreestanding
CFLAGS         += -nostdlib
CFLAGS         += -fno-builtin
CFLAGS         += -fno-stack-protector
CFLAGS         += -Wall -Wextra
CFLAGS         += -I.

LDFLAGS        := -T riscv.ld -nostdlib

CORE_SRC       := core_list_join.c core_main.c core_matrix.c core_state.c core_util.c
PORT_SRC       := core_portme.c uart.c
STARTUP_SRC    := crt0.S
SRCS           := $(CORE_SRC) $(PORT_SRC) $(STARTUP_SRC)

TARGET         := coremark
ELF            := $(TARGET).elf
BIN            := coremarks_cpi.bin
HEX            := coremarks_cpi.hex
COE            := coremarks_cpi.coe
DUMP           := $(TARGET).dump

.PHONY: all clean

all: $(ELF) $(HEX) $(COE) $(DUMP)
	@echo "========================================"
	@echo "Build complete for $(ARCH_TYPE) (RAM Width: $(RAM_WIDTH)bit)"
	@echo "========================================"
	@$(SIZE) $(ELF)

$(ELF): $(SRCS) riscv.ld
	@echo "Linking $(ELF)..."
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ crt0.S $(CORE_SRC) $(PORT_SRC) -lgcc

$(BIN): $(ELF)
	@echo "Generating unified binary..."
	$(OBJCOPY) -O binary $< $@

$(HEX): $(BIN)
	@echo "Generating $(RAM_WIDTH)-bit unified HEX..."
	@python3 bin2vhex.py $< $@ $(RAM_WIDTH)

$(COE): $(HEX)
	@echo "Generating COE..."
	@python3 hex2coe.py $< $@

$(DUMP): $(ELF)
	@echo "Generating disassembly dump..."
	$(OBJDUMP) -d -S -l $< > $@

clean:
	rm -f $(ELF) $(BIN) $(HEX) $(COE) $(DUMP) *.o
