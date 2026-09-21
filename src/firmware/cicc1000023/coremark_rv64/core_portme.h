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

#ifndef CORE_PORTME_H
#define CORE_PORTME_H

/* ============================================================
 * 1. 先定义基本数据类型（必须在最前面！）
 * ============================================================ */
typedef signed short   ee_s16;
typedef unsigned short ee_u16;
typedef signed int     ee_s32;
typedef unsigned int   ee_u32;
typedef unsigned char  ee_u8;

typedef unsigned long  ee_ptr_int;  
typedef unsigned long  ee_size_t;   

/* 浮点类型（虽然不使用，但结构体中可能需要）*/
typedef ee_u32         ee_f32;

/* ============================================================
 * 2. 定义裸机必需的宏
 * ============================================================ */
#ifndef NULL
#define NULL ((void*)0)
#endif

#ifndef ITERATIONS
#define ITERATIONS 3000  /* CoreMark 迭代次数，可调整 */
#endif

/* ============================================================
 * 3. 配置项（全部设为 0，裸机环境）
 * ============================================================ */
#ifndef HAS_FLOAT
#define HAS_FLOAT 0
#endif
#ifndef HAS_TIME_H
#define HAS_TIME_H 0
#endif
#ifndef USE_CLOCK
#define USE_CLOCK 0
#endif
#ifndef HAS_STDIO
#define HAS_STDIO 0
#endif
#ifndef HAS_PRINTF
#define HAS_PRINTF 0
#endif

/* ============================================================
 * 4. CORE_TICKS 类型（现在 ee_u32 已定义，不会报错）
 * ============================================================ */
typedef ee_u32 CORE_TICKS;

/* ============================================================
 * 5. 编译器信息
 * ============================================================ */
#ifndef COMPILER_VERSION
#define COMPILER_VERSION "GCC-RV64I"
#endif
#ifndef COMPILER_FLAGS
#define COMPILER_FLAGS "-O2 -march=rv64im_zicsr"
#endif
#ifndef MEM_LOCATION
#define MEM_LOCATION "STATIC"
#endif

/* ============================================================
 * 6. 对齐宏
 * ============================================================ */
#define align_mem(x) (void *)(4 + (((ee_ptr_int)(x)-1) & ~3))

/* ============================================================
 * 7. 种子获取方法
 * ============================================================ */
#ifndef SEED_METHOD
#define SEED_METHOD SEED_VOLATILE
#endif

/* ============================================================
 * 8. 内存分配方法（改为 STATIC，避免栈溢出）
 * ============================================================ */
#ifndef MEM_METHOD
#define MEM_METHOD MEM_STATIC
#endif

/* ============================================================
 * 9. 多线程配置（禁用）
 * ============================================================ */
#ifndef MULTITHREAD
#define MULTITHREAD 1
#define USE_PTHREAD 0
#define USE_FORK    0
#define USE_SOCKET  0
#endif

/* ============================================================
 * 10. main 函数配置
 * ============================================================ */
#ifndef MAIN_HAS_NOARGC
#define MAIN_HAS_NOARGC 0
#endif
#ifndef MAIN_HAS_NORETURN
#define MAIN_HAS_NORETURN 0
#endif

/* ============================================================
 * 11. 外部变量声明
 * ============================================================ */
extern ee_u32 default_num_contexts;

/* ============================================================
 * 12. core_portable 结构体
 * ============================================================ */
typedef struct CORE_PORTABLE_S
{
    ee_u8 portable_id;
} core_portable;

/* ============================================================
 * 13. 函数声明
 * ============================================================ */
void portable_init(core_portable *p, int *argc, char *argv[]);
void portable_fini(core_portable *p);

/* ee_printf 声明（解决隐式声明错误）*/
void ee_printf(const char *fmt, ...);

/* ============================================================
 * 14. 自动选择运行模式
 * ============================================================ */
#if !defined(PROFILE_RUN) && !defined(PERFORMANCE_RUN) && !defined(VALIDATION_RUN)
#if (TOTAL_DATA_SIZE == 1200)
#define PROFILE_RUN 1
#elif (TOTAL_DATA_SIZE == 2000)
#define PERFORMANCE_RUN 1
#else
#define VALIDATION_RUN 1
#endif
#endif

/* ============================================================
 * 15. 引入 UART 头文件
 * ============================================================ */
#include "uart.h"

#endif /* CORE_PORTME_H */