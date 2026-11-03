/* riscv.ld - RV64 冯诺依曼统一架构版 */
MEMORY
{

  /* 起始地址建议设为 0x10000000 */
  RAM (xrw) : ORIGIN = 0x10000000, LENGTH = 128K
}

ENTRY(_start)

SECTIONS
{
  /* 1. 代码段 - 存放到统一 RAM */
  .text : {
    . = ALIGN(8);       
    _stext = .;
    *(.text.init)       
    *(.text)
    *(.text.*)
    . = ALIGN(8);       
    _etext = .;
  } > RAM

  /* 2. 只读数据段 - 存放到统一 RAM */
  .rodata : {
    . = ALIGN(8);
    _srodata = .;
    *(.rodata)
    *(.rodata.*)
    *(.srodata)        
    *(.srodata.*)
    . = ALIGN(8);
    _erodata = .;
  } > RAM

  /* 3. 已初始化数据段 - 存放到统一 RAM */
  .data : {
    . = ALIGN(8);
    _sdata = .;
    /* 全局指针 gp 的参考点，保持不变 */
    PROVIDE( __global_pointer$ = . + 0x800 );
    *(.data)
    *(.data.*)
    *(.sdata)          
    *(.sdata.*)
    . = ALIGN(8);      
    _edata = .;
  } > RAM

  /* 4. 未初始化数据段 - 存放到统一 RAM */
  .bss : {
    . = ALIGN(8);       
    _sbss = .;
    *(.bss)
    *(.bss.*)
    *(.sbss)
    *(.sbss.*)
    *(COMMON)
    . = ALIGN(8);   
    _ebss = .;
  } > RAM
  

  _stack_top = ALIGN(ORIGIN(RAM) + LENGTH(RAM), 16);
  
  /DISCARD/ : {
    *(.eh_frame)
    *(.comment)
  }
}