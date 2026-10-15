/* riscv.ld - Ascon software, flat image at reset PC 0x10000000 */
MEMORY
{
  RAM (xrw) : ORIGIN = 0x10000000, LENGTH = 128K
}

SECTIONS
{
  .text : {
    . = ALIGN(4);
    *(.text.init)
    *(.text)
    *(.text.*)
  } > RAM

  .rodata : {
    . = ALIGN(8);
    *(.rodata)
    *(.rodata.*)
    *(.srodata)
    *(.srodata.*)
  } > RAM

  .data : {
    . = ALIGN(8);
    _sdata = .;
    __global_pointer$ = . + 0x800;
    *(.data)
    *(.data.*)
    *(.sdata)
    *(.sdata.*)
    _edata = .;
  } > RAM

  .bss : {
    . = ALIGN(8);
    _sbss = .;
    *(.bss)
    *(.bss.*)
    *(COMMON)
    _ebss = .;
  } > RAM

  _stack_top = ALIGN(ORIGIN(RAM) + LENGTH(RAM) - 16, 16);
}
