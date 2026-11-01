# crt0.S - RV32 哈佛架构版
.section .text
.global _start
.global main

_start:
    # 1. 设置栈指针 (利用 LD 脚本传来的 _stack_top)
    la sp, _stack_top
    
    # 2. 初始化全局指针 gp (极其重要！)
    .option push
    .option norelax
    la gp, __global_pointer$
    .option pop

    # 3. 清零 .bss 段 (使用链接器符号)
    la t0, _sbss          
    la t1, _ebss          
    
bss_loop:
    bge t0, t1, bss_done  
    sw zero, 0(t0)        # RV32 使用 sw
    addi t0, t0, 4        
    j bss_loop

bss_done:
    # 4. 跳转到 main
    jal ra, main
    
stop:
    j stop