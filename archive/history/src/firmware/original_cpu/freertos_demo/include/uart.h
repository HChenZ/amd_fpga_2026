#ifndef FREERTOS_DEMO_UART_H
#define FREERTOS_DEMO_UART_H

#include <stdint.h>

void uart_init(void);
void uart_putchar(char ch);
void uart_putc(char ch);
void uart_puts(const char *s);
void uart_put_hex32(uint32_t value);
void uart_put_dec32(uint32_t value);
int uart_getchar_nonblock(void);

void console_init(void);
void console_lock(void);
void console_unlock(void);
void console_puts(const char *s);
void console_put_hex32(uint32_t value);
void console_put_hex64(uint32_t hi, uint32_t lo);
void console_put_dec32(uint32_t value);

#endif
