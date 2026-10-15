#include "uart.h"

void uart_putc(char c)
{
    if (c == '\n') {
        while (UART_STATUS & 0x1) ;
        UART_DATA = (uint32_t)'\r';
    }
    while (UART_STATUS & 0x1) ;
    UART_DATA = (uint32_t)(unsigned char)c;
}

void uart_puts(const char *s)
{
    while (*s) uart_putc(*s++);
}

static const char hexdig[] = "0123456789abcdef";

void uart_puthex8(uint8_t v)
{
    uart_putc(hexdig[(v >> 4) & 0xf]);
    uart_putc(hexdig[v & 0xf]);
}

void uart_puthex32(uint32_t v)
{
    int i;
    for (i = 28; i >= 0; i -= 4)
        uart_putc(hexdig[(v >> i) & 0xf]);
}

void uart_puthex64(uint64_t v)
{
    uart_puthex32((uint32_t)(v >> 32));
    uart_puthex32((uint32_t)v);
}

void uart_putdec_u32(uint32_t v)
{
    char buf[12];
    int n = 0;
    if (v == 0) { uart_putc('0'); return; }
    while (v) { buf[n++] = '0' + (char)(v % 10); v /= 10; }
    while (n) uart_putc(buf[--n]);
}

void uart_putdec_u64(uint64_t v)
{
    char buf[24];
    int n = 0;
    if (v == 0) { uart_putc('0'); return; }
    while (v) { buf[n++] = '0' + (char)(v % 10); v /= 10; }
    while (n) uart_putc(buf[--n]);
}
