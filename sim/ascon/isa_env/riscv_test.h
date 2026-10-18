/* Bare-metal RV32I/M test adapter for this M-mode-only SoC.
 * Upstream test bodies/macros remain unchanged. This is NOT the privileged
 * riscv-tests p/v environment and does not certify U/S-mode execution.
 */
#ifndef SOC_RISCV_TEST_H
#define SOC_RISCV_TEST_H
#define RVTEST_RV32U
#define RVTEST_RV64U
#define TESTNUM gp
#define RVTEST_CODE_BEGIN .section .text.init; .globl _start; _start:; \
    li gp,0; la t0,unexpected_trap; csrw mtvec,t0;
#define RVTEST_CODE_END unexpected_trap:; li gp,0xdead; RVTEST_FAIL
#define RVTEST_PASS li gp,1; li t0,0x1001fff0; sw gp,0(t0); 1: j 1b
#define RVTEST_FAIL slli gp,gp,1; ori gp,gp,1; li t0,0x1001fff0; sw gp,0(t0); 1: j 1b
#define RVTEST_DATA_BEGIN .align 4; .global begin_signature; begin_signature:
#define RVTEST_DATA_END .align 4; .global end_signature; end_signature:
#endif
