/* svc_io.c —— pynq_svc 的阻塞串口 I/O（RV32 UART MMIO 0x20000000）
 *
 * 与 P0 固件（ascon_*_rv32/uart.c）相同的寄存器语义，但这里提供阻塞收字节，
 * 因为 pynq_svc 是"服务端"：它按帧读取驱动发来的请求。
 * TX：等待 STATUS.bit0（tx_busy_or_pending）清零再写 DATA。
 * RX：等待 STATUS.bit3（!rx_empty）置位再读 DATA（读即弹出一个字节）。
 */
#include "svc.h"

uint8_t svc_getc(void)
{
    while (!(UART_STATUS & 0x08u)) { }
    return (uint8_t)(UART_DATA & 0xFFu);
}

void svc_putc(uint8_t c)
{
    while (UART_STATUS & 0x01u) { }
    UART_DATA = (uint32_t)c;
}

void svc_puts(const char *s)
{
    while (*s) {
        if (*s == '\n') {
            while (UART_STATUS & 0x01u) { }
            UART_DATA = (uint32_t)'\r';
        }
        while (UART_STATUS & 0x01u) { }
        UART_DATA = (uint32_t)(uint8_t)(*s++);
    }
}

void svc_puthex32(uint32_t v)
{
    static const char hex[] = "0123456789abcdef";
    int i;
    for (i = 28; i >= 0; i -= 4)
        svc_putc((uint8_t)hex[(v >> i) & 0xFu]);
}

void svc_putdec(uint64_t v)
{
    char buf[24];
    int n = 0;
    if (v == 0) { svc_putc((uint8_t)'0'); return; }
    while (v) { buf[n++] = (char)('0' + (char)(v % 10u)); v /= 10u; }
    while (n) svc_putc((uint8_t)buf[--n]);
}
