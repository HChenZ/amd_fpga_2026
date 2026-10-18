OUTPUT_ARCH(riscv)
ENTRY(_start)
SECTIONS {
    . = 0x10000000;
    .text : { *(.text.init) *(.text*) }
    . = ALIGN(64);
    .data : { *(.data*) *(.sdata*) *(.rodata*) }
    .bss : { *(.bss*) *(.sbss*) *(COMMON) }
    ASSERT(. < 0x1001fff0, "ISA image overlaps completion mailbox")
}
