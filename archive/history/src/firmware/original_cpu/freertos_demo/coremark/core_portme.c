/*
Copyright 2018 Embedded Microprocessor Benchmark Consortium (EEMBC)

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

Original Author: Shay Gal-on
*/

/* #include <stdio.h> */
/* #include <stdlib.h> */
#include "coremark.h"
#include "rtos_monitor.h"

volatile ee_s32 seed1_volatile = 0x3415;
volatile ee_s32 seed2_volatile = 0x3415;
volatile ee_s32 seed3_volatile = 0x66;
volatile ee_s32 seed4_volatile = ITERATIONS;
volatile ee_s32 seed5_volatile = 0;


/* Porting : Timing functions
        How to capture time and convert to seconds must be ported to whatever is
   supported by the platform. e.g. Read value from on board RTC, read value from
   cpu clock cycles performance counter etc. Sample implementation for standard
   time.h and windows.h definitions included.
*/
/* Define : TIMER_RES_DIVIDER
        Divider to trade off timer resolution and total time that can be
   measured.

        Use lower values to increase resolution, but make sure that overflow
   does not occur. If there are issues with the return value overflowing,
   increase this value.
        */


/* CSR 周期计数器编号 */
#define CSR_CYCLE_CNT       0xB00

/* ==========================================================
 * 1. 定义 HPM 寄存器物理地址 (32 位硬件)
 * ========================================================== */
 #define HPM_INST_RET    (*((volatile unsigned int*)0x60000000))
 #define HPM_STALL_LD    (*((volatile unsigned int*)0x60000008))
 #define HPM_STALL_MD    (*((volatile unsigned int*)0x60000010))
 #define HPM_FLUSH_BR    (*((volatile unsigned int*)0x60000018))

/* 读取周期数的宏 */
#define READ_CYCLE_COUNT() ({ \
    ee_u32 cycle; \
    asm volatile("csrr %0, %1" : "=r"(cycle) : "i"(CSR_CYCLE_CNT)); \
    cycle; \
})




/* 全局变量保存时间与快照 (使用 32 位 unsigned int) */
static unsigned int start_time_val, stop_time_val;
static unsigned int start_inst, start_ld, start_md, start_br;

/* 辅助打印函数 */
static void print_cpi_item(const char *name, unsigned int cpi_val) {
    unsigned int integer = cpi_val / 1000;
    unsigned int frac = cpi_val % 1000;
    ee_printf("%s: %u.", name, integer);
    if (frac < 10) ee_printf("00%u\n", frac);
    else if (frac < 100) ee_printf("0%u\n", frac);
    else ee_printf("%u\n", frac);
}

/* 
 * 【终极黑科技】：纯 32 位软件计算 (cycles * 1000) / insts
 * 完全避免使用 64 位变量，彻底绕开 libgcc 报错！
 */
static unsigned int calc_cpi(unsigned int cycles, unsigned int insts) {
    if (insts == 0) return 0;
    
    /* 1. 用 32 位乘法强行模拟 64 位高低位乘法 (cycles * 1000) */
    unsigned int p1 = (cycles & 0xFFFF) * 1000;
    unsigned int p2 = (cycles >> 16) * 1000;
    unsigned int lo = p1 + (p2 << 16);
    unsigned int hi = p2 >> 16;
    if (lo < p1) hi++; /* 处理进位 */
    
    /* 2. 手摇 64位除以32位 恢复算法 (Shift-Subtract) */
    unsigned int quot = 0;
    unsigned int rem = 0;
    
    /* 处理高 32 位 */
    for (int i = 31; i >= 0; i--) {
        unsigned int bit = (hi >> i) & 1;
        unsigned int overflow = rem >> 31;
        rem = (rem << 1) | bit;
        if (overflow || rem >= insts) rem -= insts;
    }
    /* 处理低 32 位 */
    for (int i = 31; i >= 0; i--) {
        unsigned int bit = (lo >> i) & 1;
        unsigned int overflow = rem >> 31;
        rem = (rem << 1) | bit;
        if (overflow || rem >= insts) {
            rem -= insts;
            quot |= (1U << i);
        }
    }
    return quot;
}

void start_time(void) {
    ee_printf("[CoreMark][dbg] start_time\n");
    start_time_val = READ_CYCLE_COUNT();
    start_inst = HPM_INST_RET;
    start_ld   = HPM_STALL_LD;
    start_md   = HPM_STALL_MD;
    start_br   = HPM_FLUSH_BR;
}

void stop_time(void) {
    ee_printf("[CoreMark][dbg] stop_time\n");
    stop_time_val = READ_CYCLE_COUNT();
    
    /* 32位无符号减法，天然处理计数器回绕溢出 */
    unsigned int diff_inst = HPM_INST_RET - start_inst;
    unsigned int diff_ld   = HPM_STALL_LD - start_ld;
    unsigned int diff_md   = HPM_STALL_MD - start_md;
    unsigned int diff_br   = HPM_FLUSH_BR - start_br;
    
    if (diff_inst == 0) diff_inst = 1;

    unsigned int br_penalty = diff_br * 2; 
    unsigned int total_cycles = stop_time_val - start_time_val;
    
    /* 【完美避开报错】直接调用我们手搓的函数！ */
    unsigned int cpi_total  = calc_cpi(total_cycles, diff_inst);
    unsigned int cpi_ld     = calc_cpi(diff_ld, diff_inst);
    unsigned int cpi_md     = calc_cpi(diff_md, diff_inst);
    unsigned int cpi_br     = calc_cpi(br_penalty, diff_inst);
    
    unsigned int cpi_others = 0;
    unsigned int known_penalties = 1000 + cpi_ld + cpi_md + cpi_br;
    if (cpi_total > known_penalties) cpi_others = cpi_total - known_penalties;

    /* Stop ANSI monitor refresh before formal CPI/CRC output. */
    rtos_monitor_coremark_measurement_stopped();

    /* 打印结果 */
    ee_printf("\n==========================================\n");
    ee_printf("  RV32 Micro-Architecture CPI Breakdown   \n");
    ee_printf("==========================================\n");
    ee_printf("Total Instructions : %u\n", diff_inst);
    print_cpi_item("Actual Total CPI   ", cpi_total);
    ee_printf("------------------------------------------\n");
    print_cpi_item("[+] Ideal Base CPI ", 1000);
    print_cpi_item("[+] Load-Use Penalty", cpi_ld);
    print_cpi_item("[+] Mul/Div Penalty ", cpi_md);
    print_cpi_item("[+] Branch Penalty  ", cpi_br);
    print_cpi_item("[+] Other Stalls    ", cpi_others);
    ee_printf("==========================================\n\n");
}
/* Function : get_time
        Return an abstract "ticks" number that signifies time on the system.

        Actual value returned may be cpu cycles, milliseconds or any other
   value, as long as it can be converted to seconds by <time_in_secs>. This
   methodology is taken to accommodate any hardware or simulated platform. The
   sample implementation returns millisecs by default, and the resolution is
   controlled by <TIMER_RES_DIVIDER>
*/
CORE_TICKS
get_time(void)
{
    return (stop_time_val - start_time_val);
}
/* Function : time_in_secs
        Convert the value returned by get_time to seconds.

        The <secs_ret> type is used to accommodate systems with no support for
   floating point. Default implementation implemented by the EE_TICKS_PER_SEC
   macro above.
*/
secs_ret
time_in_secs(CORE_TICKS ticks)
{
    #define CPU_FREQ_HZ 100000000
    secs_ret retval = ((secs_ret)ticks) / (secs_ret)CPU_FREQ_HZ;
    return retval;
}

ee_u32 default_num_contexts = 1;

/* Function : portable_init
        Target specific initialization code
        Test for some common mistakes.
*/

/* 在 portable_init 之前添加 */

/* UART 字符发送函数 */


/* 重定向 ee_printf - CoreMark 使用 ee_printf 而非 printf */
/* 需要在 coremark.h 中找到 ee_printf 的定义并修改 */

void
portable_init(core_portable *p, int *argc, char *argv[])
{
    (void)argc;
    (void)argv;

    ee_printf("[CoreMark][dbg] portable_init\n");
    ee_printf("[CoreMark][dbg] seeds v1=%d v2=%d v3=%d v4=%d v5=%d\n",
              (int)seed1_volatile,
              (int)seed2_volatile,
              (int)seed3_volatile,
              (int)seed4_volatile,
              (int)seed5_volatile);


    if (sizeof(ee_ptr_int) != sizeof(ee_u8 *))
    {
        console_puts("ERROR! Please define ee_ptr_int to a type that holds a pointer!\n");
    }
    if (sizeof(ee_u32) != 4)
    {
        console_puts("ERROR! Please define ee_u32 to a 32b unsigned type!\n");
    }
    p->portable_id = 1;
}
/* Function : portable_fini
        Target specific final code
*/
void
portable_fini(core_portable *p)
{
    p->portable_id = 0;
}
