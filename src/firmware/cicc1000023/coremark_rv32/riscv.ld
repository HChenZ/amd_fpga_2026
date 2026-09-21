/* riscv.ld 冯诺依曼统一版 */
MEMORY
{
  /* 假设 64K 统一空间 */
  RAM (xrw) : ORIGIN = 0x10001000, LENGTH = 124K
}

SECTIONS
{
  .text : {
    . = ALIGN(8);  /* 统一用 8 字节对齐 */
    _stext = .;
    *(.text.init) 
    *(.text)
    *(.text.*)
    _etext = .;
  } > RAM

  .rodata : {
    . = ALIGN(8);
    _srodata = .;
    *(.rodata)
    *(.rodata.*)
    *(.srodata)
    *(.srodata.*)
    _erodata = .;
  } > RAM

  .data : {
    . = ALIGN(8);
    _sdata = .;
    PROVIDE( __global_pointer$ = . + 0x800 );
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