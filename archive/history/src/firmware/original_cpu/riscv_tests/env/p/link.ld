OUTPUT_ARCH( "riscv" )
ENTRY(_start)

SECTIONS
{
  . = 0x10000000;

  .text.init : { *(.text.init) }


  . = ALIGN(8);
  .tohost : { *(.tohost) }

  . = ALIGN(8);
  .text : { *(.text) }

  . = ALIGN(8);
  .data : { *(.data) }
  
  . = ALIGN(8);
  .data.string : { *(.data.string)}

  . = ALIGN(8);
  .bss : { *(.bss) }

  _end = .;
}