OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    RAM (rwx) : ORIGIN = 0x10000000, LENGTH = 128K
}

PROVIDE(__stack_size = 8K);

SECTIONS
{
    . = ORIGIN(RAM);

    .text : ALIGN(4)
    {
        KEEP(*(.init))
        *(.text .text.*)
        *(.rodata .rodata.*)
        . = ALIGN(4);
    } > RAM

    .data : ALIGN(4)
    {
        . = ALIGN(4);
        PROVIDE(__global_pointer$ = . + 0x800);
        _sdata = .;
        *(.sdata .sdata.*)
        *(.data .data.*)
        . = ALIGN(4);
        _edata = .;
    } > RAM

    _sidata = LOADADDR(.data);

    .bss (NOLOAD) : ALIGN(4)
    {
        _sbss = .;
        *(.sbss .sbss.*)
        *(.bss .bss.*)
        *(COMMON)
        . = ALIGN(16);
        _ebss = .;
    } > RAM

    . = ALIGN(16);
    __heap_end = ORIGIN(RAM) + LENGTH(RAM) - __stack_size;
    __stack_top = ORIGIN(RAM) + LENGTH(RAM);

    ASSERT(_ebss <= __heap_end, "RAM overflow: reduce heap, stacks, or code size")
}
