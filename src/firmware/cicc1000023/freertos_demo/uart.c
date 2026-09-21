#include "uart.h"

#include "FreeRTOS.h"
#include "semphr.h"
#include "task.h"

#include "platform.h"

static SemaphoreHandle_t console_mutex;

void uart_init(void)
{
    mmio_write32(PLATFORM_UART_CTRL, 0);
}

void uart_putchar(char ch)
{
    if (ch == '\n')
    {
        uart_putchar('\r');
    }

    while ((mmio_read32(PLATFORM_UART_STATUS) & UART_STATUS_TX_FULL) != 0U)
    {
    }

    mmio_write32(PLATFORM_UART_DATA, (uint32_t) (uint8_t) ch);
}

void uart_putc(char ch)
{
    uart_putchar(ch);
}

void uart_puts(const char *s)
{
    while (*s != '\0')
    {
        uart_putchar(*s++);
    }
}

void uart_put_hex32(uint32_t value)
{
    static const char hex[] = "0123456789abcdef";

    uart_puts("0x");
    for (int shift = 28; shift >= 0; shift -= 4)
    {
        uart_putchar(hex[(value >> shift) & 0xfU]);
    }
}

void uart_put_dec32(uint32_t value)
{
    char buf[10];
    int pos = 0;

    do
    {
        buf[pos++] = (char) ('0' + (value % 10UL));
        value /= 10UL;
    } while (value != 0UL);

    while (pos > 0)
    {
        uart_putchar(buf[--pos]);
    }
}

int uart_getchar_nonblock(void)
{
    if ((mmio_read32(PLATFORM_UART_STATUS) & UART_STATUS_RX_NOT_EMPTY) == 0U)
    {
        return -1;
    }

    return (int) (mmio_read32(PLATFORM_UART_DATA) & 0xffU);
}

void console_init(void)
{
    console_mutex = xSemaphoreCreateMutex();
}

void console_lock(void)
{
    if ((console_mutex != NULL) && (xTaskGetSchedulerState() != taskSCHEDULER_NOT_STARTED))
    {
        (void) xSemaphoreTake(console_mutex, portMAX_DELAY);
    }
    else
    {
        taskENTER_CRITICAL();
    }
}

void console_unlock(void)
{
    if ((console_mutex != NULL) && (xTaskGetSchedulerState() != taskSCHEDULER_NOT_STARTED))
    {
        (void) xSemaphoreGive(console_mutex);
    }
    else
    {
        taskEXIT_CRITICAL();
    }
}

void console_puts(const char *s)
{
    uart_puts(s);
}

void console_put_hex32(uint32_t value)
{
    uart_put_hex32(value);
}

void console_put_hex64(uint32_t hi, uint32_t lo)
{
    static const char hex[] = "0123456789abcdef";

    uart_puts("0x");
    for (int shift = 28; shift >= 0; shift -= 4)
    {
        uart_putchar(hex[(hi >> shift) & 0xfU]);
    }
    for (int shift = 28; shift >= 0; shift -= 4)
    {
        uart_putchar(hex[(lo >> shift) & 0xfU]);
    }
}

void console_put_dec32(uint32_t value)
{
    uart_put_dec32(value);
}
