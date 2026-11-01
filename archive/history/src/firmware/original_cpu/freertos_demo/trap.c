#include <stdint.h>

#include "FreeRTOS.h"
#include "task.h"

#include "demo.h"
#include "platform.h"
#include "uart.h"

#define MCAUSE_MACHINE_EXTERNAL_INTERRUPT 0x8000000bUL

static inline uint32_t read_csr_mcause(void)
{
    uint32_t value;
    __asm volatile ("csrr %0, mcause" : "=r" (value));
    return value;
}

static inline uint32_t read_csr_mepc(void)
{
    uint32_t value;
    __asm volatile ("csrr %0, mepc" : "=r" (value));
    return value;
}

static inline uint32_t read_csr_mtval(void)
{
    uint32_t value;
    __asm volatile ("csrr %0, mtval" : "=r" (value));
    return value;
}

static inline uint32_t read_csr_mstatus(void)
{
    uint32_t value;
    __asm volatile ("csrr %0, mstatus" : "=r" (value));
    return value;
}

void freertos_risc_v_application_exception_handler(void)
{
    uart_puts("exception mcause=");
    uart_put_hex32(read_csr_mcause());
    uart_puts(" mstatus=");
    uart_put_hex32(read_csr_mstatus());
    uart_puts(" mepc=");
    uart_put_hex32(read_csr_mepc());
    uart_puts(" mtval=");
    uart_put_hex32(read_csr_mtval());
    uart_puts(" btn=");
    uart_put_hex32(mmio_read32(PLATFORM_GPIO_BTN));
    uart_puts(" led=");
    uart_put_hex32(mmio_read32(PLATFORM_GPIO_LED));
    uart_puts("\n");

    for (;;)
    {
    }
}

void freertos_risc_v_application_interrupt_handler(void)
{
    uint32_t mcause = read_csr_mcause();

    if (mcause == MCAUSE_MACHINE_EXTERNAL_INTERRUPT)
    {
        uint32_t buttons = mmio_read32(PLATFORM_GPIO_BTN) & 0x3U;
        BaseType_t higher_priority_task_woken = pdFALSE;
        uint32_t notify_bits = 0;

        g_gpio_irq_count++;
        g_gpio_last_buttons = buttons;

        if ((buttons & 0x1U) != 0U)
        {
            notify_bits |= DEMO_GPIO_NOTIFY_BTN0;
        }
        if ((buttons & 0x2U) != 0U)
        {
            notify_bits |= DEMO_GPIO_NOTIFY_BTN1;
        }

        if ((notify_bits != 0U) && (g_gpio_task_handle != NULL))
        {
            (void) xTaskNotifyFromISR(g_gpio_task_handle,
                                      notify_bits,
                                      eSetBits,
                                      &higher_priority_task_woken);
        }

        portYIELD_FROM_ISR(higher_priority_task_woken);
        return;
    }

    uart_puts("unhandled interrupt mcause=");
    uart_put_hex32(mcause);
    uart_puts(" mepc=");
    uart_put_hex32(read_csr_mepc());
    uart_puts("\n");

    for (;;)
    {
    }
}
