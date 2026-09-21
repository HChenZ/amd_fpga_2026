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
#include "uart.h"
#include "coremark.h"

/* 裸机环境下，使用 GCC 内置的 va 宏 */
/* 即使没有 <stdarg.h>，__builtin_va_* 也能工作 */
#ifndef __GNUC__
#error "This port requires GCC for __builtin_va_* macros"
#endif
/* Function: get_seed
        Get a values that cannot be determined at compile time.

        Since different embedded systems and compilers are used, 3 different
   methods are provided: 1 - Using a volatile variable. This method is only
   valid if the compiler is forced to generate code that reads the value of a
   volatile variable from memory at run time. Please note, if using this method,
   you would need to modify core_portme.c to generate training profile. 2 -
   Command line arguments. This is the preferred method if command line
   arguments are supported. 3 - System function. If none of the first 2 methods
   is available on the platform, a system function which is not a stub can be
   used.

        e.g. read the value on GPIO pins connected to switches, or invoke
   special simulator functions.
*/
#if (SEED_METHOD == SEED_VOLATILE)
extern volatile ee_s32 seed1_volatile;
extern volatile ee_s32 seed2_volatile;
extern volatile ee_s32 seed3_volatile;
extern volatile ee_s32 seed4_volatile;
extern volatile ee_s32 seed5_volatile;
ee_s32
get_seed_32(int i)
{
    ee_s32 retval;
    switch (i)
    {
        case 1:
            retval = seed1_volatile;
            break;
        case 2:
            retval = seed2_volatile;
            break;
        case 3:
            retval = seed3_volatile;
            break;
        case 4:
            retval = seed4_volatile;
            break;
        case 5:
            retval = seed5_volatile;
            break;
        default:
            retval = 0;
            break;
    }
    return retval;
}
#elif (SEED_METHOD == SEED_ARG)
ee_s32
parseval(char *valstring)
{
    ee_s32 retval  = 0;
    ee_s32 neg     = 1;
    int    hexmode = 0;
    if (*valstring == '-')
    {
        neg = -1;
        valstring++;
    }
    if ((valstring[0] == '0') && (valstring[1] == 'x'))
    {
        hexmode = 1;
        valstring += 2;
    }
    /* first look for digits */
    if (hexmode)
    {
        while (((*valstring >= '0') && (*valstring <= '9'))
               || ((*valstring >= 'a') && (*valstring <= 'f')))
        {
            ee_s32 digit = *valstring - '0';
            if (digit > 9)
                digit = 10 + *valstring - 'a';
            retval *= 16;
            retval += digit;
            valstring++;
        }
    }
    else
    {
        while ((*valstring >= '0') && (*valstring <= '9'))
        {
            ee_s32 digit = *valstring - '0';
            retval *= 10;
            retval += digit;
            valstring++;
        }
    }
    /* now add qualifiers */
    if (*valstring == 'K')
        retval *= 1024;
    if (*valstring == 'M')
        retval *= 1024 * 1024;

    retval *= neg;
    return retval;
}

ee_s32
get_seed_args(int i, int argc, char *argv[])
{
    if (argc > i)
        return parseval(argv[i]);
    return 0;
}

#elif (SEED_METHOD == SEED_FUNC)
/* If using OS based function, you must define and implement the functions below
 * in core_portme.h and core_portme.c ! */
ee_s32
get_seed_32(int i)
{
    ee_s32 retval;
    switch (i)
    {
        case 1:
            retval = portme_sys1();
            break;
        case 2:
            retval = portme_sys2();
            break;
        case 3:
            retval = portme_sys3();
            break;
        case 4:
            retval = portme_sys4();
            break;
        case 5:
            retval = portme_sys5();
            break;
        default:
            retval = 0;
            break;
    }
    return retval;
}
#endif

/* Function: crc*
        Service functions to calculate 16b CRC code.

*/
ee_u16
crcu8(ee_u8 data, ee_u16 crc)
{
    ee_u8 i = 0, x16 = 0, carry = 0;

    for (i = 0; i < 8; i++)
    {
        x16 = (ee_u8)((data & 1) ^ ((ee_u8)crc & 1));
        data >>= 1;

        if (x16 == 1)
        {
            crc ^= 0x4002;
            carry = 1;
        }
        else
            carry = 0;
        crc >>= 1;
        if (carry)
            crc |= 0x8000;
        else
            crc &= 0x7fff;
    }
    return crc;
}
ee_u16
crcu16(ee_u16 newval, ee_u16 crc)
{
    crc = crcu8((ee_u8)(newval), crc);
    crc = crcu8((ee_u8)((newval) >> 8), crc);
    return crc;
}
ee_u16
crcu32(ee_u32 newval, ee_u16 crc)
{
    crc = crc16((ee_s16)newval, crc);
    crc = crc16((ee_s16)(newval >> 16), crc);
    return crc;
}
ee_u16
crc16(ee_s16 newval, ee_u16 crc)
{
    return crcu16((ee_u16)newval, crc);
}

ee_u8
check_data_types()
{
    ee_u8 retval = 0;
    if (sizeof(ee_u8) != 1)
    {
        ee_printf("ERROR: ee_u8 is not an 8b datatype!\n");
        retval++;
    }
    if (sizeof(ee_u16) != 2)
    {
        ee_printf("ERROR: ee_u16 is not a 16b datatype!\n");
        retval++;
    }
    if (sizeof(ee_s16) != 2)
    {
        ee_printf("ERROR: ee_s16 is not a 16b datatype!\n");
        retval++;
    }
    if (sizeof(ee_s32) != 4)
    {
        ee_printf("ERROR: ee_s32 is not a 32b datatype!\n");
        retval++;
    }
    if (sizeof(ee_u32) != 4)
    {
        ee_printf("ERROR: ee_u32 is not a 32b datatype!\n");
        retval++;
    }
    if (sizeof(ee_ptr_int) != sizeof(int *))
    {
        ee_printf(
            "ERROR: ee_ptr_int is not a datatype that holds an int pointer!\n");
        retval++;
    }
    if (retval > 0)
    {
        ee_printf("ERROR: Please modify the datatypes in core_portme.h!\n");
    }
    return retval;
}




/* ============================================================
 * ee_printf 
 * ============================================================ */
 static void ee_itoa(unsigned int val, char *buf, int base, int is_signed)
 {
     char *p = buf;
     int neg = 0;
     
     /* 只有当明确是有符号数、十进制且值为负时，才处理负号 */
     if (is_signed && (int)val < 0 && base == 10) { 
         neg = 1; 
         val = (unsigned int)(-(int)val); 
     }
     
     do {
         unsigned int rem = val % base;
         *p++ = (rem < 10) ? '0' + rem : 'a' + rem - 10;
         val /= base;
     } while (val > 0);
     
     if (neg) *p++ = '-';
     
     /* 字符串反转 */
     for (char *start = buf, *end = p - 1; start < end; start++, end--) {
         char tmp = *start; *start = *end; *end = tmp;
     }
     *p = '\0';
 }
  
 void ee_printf(const char *fmt, ...)
 {
     char buf[32];
     __builtin_va_list args;
     __builtin_va_start(args, fmt);
     
     while (*fmt) {
         if (*fmt == '%') {
             fmt++;
             
             /* 解析并跳过宽度和填充控制 (例如 %04x) */
             int pad_zero = 0;
             int width = 0;
             if (*fmt == '0') { pad_zero = 1; fmt++; }
             while (*fmt >= '0' && *fmt <= '9') {
                 width = width * 10 + (*fmt - '0');
                 fmt++;
             }
             /* 跳过长度修饰符 (例如 %lu 中的 l) */
             if (*fmt == 'l' || *fmt == 'L') { fmt++; }
             
             if (*fmt == '\0') break; /* 防止尾部独立的 % 导致越界 */
             
             if (*fmt == 'd') {
                 ee_itoa(__builtin_va_arg(args, int), buf, 10, 1);
                 uart_puts(buf);
             } else if (*fmt == 'u') {
                 ee_itoa(__builtin_va_arg(args, unsigned int), buf, 10, 0);
                 uart_puts(buf);
             } else if (*fmt == 'x' || *fmt == 'X') {
                 ee_itoa(__builtin_va_arg(args, unsigned int), buf, 16, 0);
                 /* 处理 %04x 的补零对齐 */
                 int len = 0; 
                 while(buf[len]) len++;
                 while(len < width) { 
                     uart_putc(pad_zero ? '0' : ' '); 
                     len++; 
                 }
                 uart_puts(buf);
             } else if (*fmt == 's') {
                 const char *s = __builtin_va_arg(args, const char *);
                 uart_puts(s ? s : "(null)");
             } else if (*fmt == 'c') {
                 uart_putc((char)__builtin_va_arg(args, int));
             } else if (*fmt == '%') {
                 uart_putc('%');
             }
             fmt++;
         } else {
             uart_putc(*fmt++);
         }
     }
     __builtin_va_end(args);
 }
 



 /* ============================================================
  * 软件乘除法实现
  * ============================================================ */
 
  
//  /* 32 位无符号乘法 */
//  unsigned int __mulsi3(unsigned int a, unsigned int b)
//  {
//      unsigned int result = 0;
//      while (b > 0) {
//          if (b & 1) { result += a; }
//          a <<= 1;
//          b >>= 1;
//      }
//      return result;
//  }
 
//  /* 32 位无符号除法 */
//  unsigned int __udivsi3(unsigned int dividend, unsigned int divisor)
//  {
//      if (divisor == 0) {
//          return 0;  /* 除零保护 */
//      }
     
//      unsigned int quotient = 0;
//      unsigned int remainder = 0;
     
//      for (int i = 31; i >= 0; i--) {
//          unsigned int bit = (dividend >> i) & 1;
//          unsigned int overflow = remainder >> 31;
         
//          remainder = (remainder << 1) | bit;
         
//          if (overflow || remainder >= divisor) {
//              remainder -= divisor;
//              quotient |= (1U << i);
//          }
//      }
     
//      return quotient;
//  }
 
//  /* 32 位有符号除法 */
//  int __divsi3(int dividend, int divisor)
//  {
//      if (divisor == 0) return 0;
     
//      int negative = 0;
//      unsigned int a = dividend;
//      unsigned int b = divisor;
     
//      if (dividend < 0) { negative = !negative; a = -dividend; }
//      if (divisor < 0) { negative = !negative; b = -divisor; }
     
//      unsigned int result = __udivsi3(a, b);
//      return negative ? -(int)result : (int)result;
//  }
 
//  /* 32 位有符号取模 */
//  int __modsi3(int dividend, int divisor)
//  {
//      if (divisor == 0) return 0;
//      int quotient = __divsi3(dividend, divisor);
//      return dividend - (quotient * divisor);
//  }
 
//  /* 32 位无符号取模 */
//  unsigned int __umodsi3(unsigned int dividend, unsigned int divisor)
//  {
//      if (divisor == 0) return 0;
//      unsigned int quotient = __udivsi3(dividend, divisor);
//      return dividend - (quotient * divisor);
//  }

 