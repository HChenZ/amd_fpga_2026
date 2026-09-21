APP := freertos_demo
BUILD_DIR ?= build
FREERTOS_KERNEL ?= ../FreeRTOS-Kernel-main
CC := riscv64-unknown-elf-gcc
OBJCOPY := riscv64-unknown-elf-objcopy
OBJDUMP := riscv64-unknown-elf-objdump
SIZE := riscv64-unknown-elf-size
PYTHON := python3

ARCH ?= rv32im_zicsr_zifencei
ABI ?= ilp32

ELF := $(BUILD_DIR)/$(APP).elf
BIN := $(BUILD_DIR)/$(APP).bin
RAM_TXT := $(BUILD_DIR)/RAM.txt
COE := $(BUILD_DIR)/$(APP).coe
DUMP := $(BUILD_DIR)/$(APP).dump
MAP := $(BUILD_DIR)/$(APP).map

CPPFLAGS := \
	-Iinclude \
	-Icoremark \
	-I$(FREERTOS_KERNEL)/include \
	-I$(FREERTOS_KERNEL)/portable/GCC/RISC-V \
	-I$(FREERTOS_KERNEL)/portable/GCC/RISC-V/chip_specific_extensions/RISCV_MTIME_CLINT_no_extensions

COMMON_FLAGS := \
	-march=$(ARCH) \
	-mabi=$(ABI) \
	-mcmodel=medany \
	-msmall-data-limit=8 \
	-ffreestanding \
	-fno-builtin \
	-fno-common \
	-ffunction-sections \
	-fdata-sections \
	-g3 \
	-Wall \
	-Wextra

CFLAGS := $(COMMON_FLAGS) -Os -std=c11
COREMARK_CFLAGS := $(COMMON_FLAGS) -O2 -std=gnu99 -Wno-unused-parameter -Wno-implicit-fallthrough
ASFLAGS := $(COMMON_FLAGS) -Os
LDFLAGS := \
	-march=$(ARCH) \
	-mabi=$(ABI) \
	-mcmodel=medany \
	-nostdlib \
	-nostartfiles \
	-Wl,--build-id=none \
	-T linker.ld \
	-Wl,-Map=$(MAP) \
	-Wl,--gc-sections
LIBS := -lgcc

COREMARK_SRCS := \
	coremark/core_list_join.c \
	coremark/core_main.c \
	coremark/core_matrix.c \
	coremark/core_state.c \
	coremark/core_util.c \
	coremark/core_portme.c

OBJS := \
	$(BUILD_DIR)/startup.o \
	$(BUILD_DIR)/main.o \
	$(BUILD_DIR)/rtos_monitor.o \
	$(BUILD_DIR)/uart.o \
	$(BUILD_DIR)/trap.o \
	$(BUILD_DIR)/libc_min.o \
	$(BUILD_DIR)/core_list_join.o \
	$(BUILD_DIR)/core_main.o \
	$(BUILD_DIR)/core_matrix.o \
	$(BUILD_DIR)/core_state.o \
	$(BUILD_DIR)/core_util.o \
	$(BUILD_DIR)/core_portme.o \
	$(BUILD_DIR)/tasks.o \
	$(BUILD_DIR)/queue.o \
	$(BUILD_DIR)/list.o \
	$(BUILD_DIR)/port.o \
	$(BUILD_DIR)/portASM.o \
	$(BUILD_DIR)/heap_4.o

.PHONY: all clean size install-ram

all: $(RAM_TXT) $(COE) $(DUMP) size

$(BUILD_DIR):
	mkdir -p $@

$(BUILD_DIR)/startup.o: startup.S include/FreeRTOSConfig.h include/platform.h | $(BUILD_DIR)
	$(CC) $(CPPFLAGS) $(ASFLAGS) -c $< -o $@

$(BUILD_DIR)/main.o: main.c include/FreeRTOSConfig.h include/platform.h include/uart.h include/demo.h include/rtos_monitor.h coremark/coremark_runner.h | $(BUILD_DIR)
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/rtos_monitor.o: rtos_monitor.c include/FreeRTOSConfig.h include/demo.h include/rtos_monitor.h include/uart.h | $(BUILD_DIR)
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/uart.o: uart.c include/platform.h include/uart.h include/FreeRTOSConfig.h | $(BUILD_DIR)
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/trap.o: trap.c include/FreeRTOSConfig.h include/platform.h include/uart.h include/demo.h | $(BUILD_DIR)
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/libc_min.o: libc_min.c include/uart.h include/string.h include/stdio.h | $(BUILD_DIR)
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/core_list_join.o: coremark/core_list_join.c coremark/coremark.h coremark/core_portme.h include/uart.h | $(BUILD_DIR)
	$(CC) $(CPPFLAGS) $(COREMARK_CFLAGS) -c $< -o $@

$(BUILD_DIR)/core_main.o: coremark/core_main.c coremark/coremark.h coremark/core_portme.h coremark/coremark_runner.h include/uart.h | $(BUILD_DIR)
	$(CC) $(CPPFLAGS) $(COREMARK_CFLAGS) -c $< -o $@

$(BUILD_DIR)/core_matrix.o: coremark/core_matrix.c coremark/coremark.h coremark/core_portme.h include/uart.h | $(BUILD_DIR)
	$(CC) $(CPPFLAGS) $(COREMARK_CFLAGS) -c $< -o $@

$(BUILD_DIR)/core_state.o: coremark/core_state.c coremark/coremark.h coremark/core_portme.h include/uart.h | $(BUILD_DIR)
	$(CC) $(CPPFLAGS) $(COREMARK_CFLAGS) -c $< -o $@

$(BUILD_DIR)/core_util.o: coremark/core_util.c coremark/coremark.h coremark/core_portme.h include/uart.h | $(BUILD_DIR)
	$(CC) $(CPPFLAGS) $(COREMARK_CFLAGS) -c $< -o $@

$(BUILD_DIR)/core_portme.o: coremark/core_portme.c coremark/coremark.h coremark/core_portme.h include/uart.h include/platform.h include/rtos_monitor.h | $(BUILD_DIR)
	$(CC) $(CPPFLAGS) $(COREMARK_CFLAGS) -c $< -o $@

$(BUILD_DIR)/tasks.o: $(FREERTOS_KERNEL)/tasks.c include/FreeRTOSConfig.h include/platform.h | $(BUILD_DIR)
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/queue.o: $(FREERTOS_KERNEL)/queue.c include/FreeRTOSConfig.h include/platform.h | $(BUILD_DIR)
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/list.o: $(FREERTOS_KERNEL)/list.c include/FreeRTOSConfig.h include/platform.h | $(BUILD_DIR)
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/port.o: $(FREERTOS_KERNEL)/portable/GCC/RISC-V/port.c include/FreeRTOSConfig.h include/platform.h | $(BUILD_DIR)
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/portASM.o: $(FREERTOS_KERNEL)/portable/GCC/RISC-V/portASM.S include/FreeRTOSConfig.h include/platform.h | $(BUILD_DIR)
	$(CC) $(CPPFLAGS) $(ASFLAGS) -c $< -o $@

$(BUILD_DIR)/heap_4.o: $(FREERTOS_KERNEL)/portable/MemMang/heap_4.c include/FreeRTOSConfig.h include/platform.h | $(BUILD_DIR)
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@

$(ELF): $(OBJS) linker.ld
	$(CC) $(LDFLAGS) $(OBJS) $(LIBS) -o $@

$(BIN): $(ELF)
	$(OBJCOPY) -O binary $< $@

$(RAM_TXT): $(BIN) tools/bin_to_ramtxt.py
	$(PYTHON) tools/bin_to_ramtxt.py $< $@

$(COE): $(RAM_TXT) tools/hex_to_coe.py
	$(PYTHON) tools/hex_to_coe.py $< $@ --width 32

$(DUMP): $(ELF)
	$(OBJDUMP) -d -S $< > $@

size: $(ELF)
	$(SIZE) $<

install-ram: $(RAM_TXT)
	cp $(RAM_TXT) /mnt/c/Users/Y/Desktop/risc-v/riscv-tests/RAM.txt

clean:
	rm -rf $(BUILD_DIR)
