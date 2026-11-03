#ifndef UART_H
#define UART_H





/* 函数声明 */
void uart_init(void);
void uart_putc(char c);
void uart_puts(const char *s);

#endif