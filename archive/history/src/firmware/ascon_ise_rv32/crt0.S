# crt0.S - RV32 bare-metal startup for Ascon-AEAD128 software
# Flat binary loaded into BRAM at 0x10000000: .text/.rodata/.data initializers
# are already at their run addresses, so only .bss needs zeroing.

.section .text.init
.global _start

_start:
    la sp, _stack_top

    .option push
    .option norelax
    la gp, __global_pointer$
    .option pop

    # zero .bss
    la t0, _sbss
    la t1, _ebss
1:  bgeu t0, t1, 2f
    sw zero, 0(t0)
    addi t0, t0, 4
    j 1b
2:
    jal ra, main

3:  j 3b
