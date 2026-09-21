#include "uart.h"

/* UART 寄存器地址 */
#define UART_DATA_ADDR      (*(volatile unsigned int*)0x20000004)
#define UART_STATUS_ADDR    (*(volatile unsigned int*)0x20000000)

void uart_init(void)
{
    
}

// void uart_putc(char c)
// {
//     /* 等待 UART 空闲：状态=1 表示忙，0 表示空闲 */
//     while (UART_STATUS_ADDR & 0x1);
//     UART_DATA_ADDR = (ee_u32)c;
// }

// void uart_puts(const char *s)
// {
//     while (*s) {
//         if (*s == '\n') uart_putc('\r');  /* 补回车 */
//         uart_putc(*s++);
//     }
// }

void uart_putc(char c)
{
    /* 1. 核心拦截：只要发的是 \n，就先强制发一个 \r */
    if (c == '\n') {
        while (UART_STATUS_ADDR & 0x1);
        UART_DATA_ADDR = (unsigned int)'\r';
    }

    /* 2. 发送原本的字符（如果是 \n 这里会接着发 \n） */
    while (UART_STATUS_ADDR & 0x1);
    UART_DATA_ADDR = (unsigned int)c;
}

void uart_puts(const char *s)
{
    /* 这里变干净了，不需要再判断，直接调 putc 就行 */
    while (*s) {
        uart_putc(*s++);
    }
}