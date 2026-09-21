    .section .init, "ax"
    .globl _start
    .type _start, @function

_start:
    .option push
    .option norelax
    la      gp, __global_pointer$
    .option pop

    la      sp, __stack_top
    andi    sp, sp, -16

    csrw    mie, zero
    csrci   mstatus, 8

    la      t0, freertos_risc_v_trap_handler
    csrw    mtvec, t0

    la      t0, _sidata
    la      t1, _sdata
    la      t2, _edata
1:
    beq     t1, t2, 2f
    lw      t3, 0(t0)
    sw      t3, 0(t1)
    addi    t0, t0, 4
    addi    t1, t1, 4
    j       1b

2:
    la      t0, _sbss
    la      t1, _ebss
3:
    beq     t0, t1, 4f
    sw      zero, 0(t0)
    addi    t0, t0, 4
    j       3b

4:
    call    main

5:
    j       5b

    .size _start, . - _start
