// Public deterministic processor test, no production firmware changes.
.option norvc
.option norelax
.section .text.init
.global _start,irq_handler,irq_loop,irq_div,irq_load,irq_branch
_start:
    li s0,0
    li s1,0
    li s2,0
    li s3,0
    li s11,0
    li s5,21
    li s6,3
    li s7,0x10001000
    la t0,irq_handler
    csrw mtvec,t0
    li t0,128
    csrw mie,t0
    csrsi mstatus,8
.balign 32
irq_loop:
    addi s0,s0,1
irq_div:
    div s2,s5,s6
    addi s1,s1,1
irq_load:
    lw s3,0(s7)
irq_branch:
    jal zero,irq_loop
.balign 64
irq_handler:
    csrr s8,mepc
    csrr s9,mcause
    csrr s10,mstatus
    addi s11,s11,1
#ifdef BROKEN_MRET
    jal zero,.
#else
    mret
#endif
