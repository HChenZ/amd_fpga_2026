#ifndef UART_H
#define UART_H

#include "coremark.h"

/* UART 寄存器地址 */
#define UART_DATA_ADDR      (*(volatile ee_u32*)0x20000004)
#define UART_STATUS_ADDR    (*(volatile ee_u32*)0x20000000)

/* 函数声明 */
void uart_init(void);
void uart_putc(char c);
void uart_puts(const char *s);

#endif