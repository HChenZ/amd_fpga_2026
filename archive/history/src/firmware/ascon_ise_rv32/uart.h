#ifndef UART_H
#define UART_H

#include <stdint.h>

/* UART MMIO registers (see src/rtl/bus_interconnect.v decode) */
#define UART_STATUS  (*(volatile uint32_t*)0x20000000)  /* bit0 = tx busy/pending */
#define UART_DATA    (*(volatile uint32_t*)0x20000004)  /* write = TX byte */

void uart_putc(char c);
void uart_puts(const char *s);
void uart_puthex8(uint8_t v);
void uart_puthex32(uint32_t v);
void uart_puthex64(uint64_t v);
void uart_putdec_u32(uint32_t v);
void uart_putdec_u64(uint64_t v);

#endif
