#ifndef FREERTOS_DEMO_H
#define FREERTOS_DEMO_H

#include <stdint.h>

#include "FreeRTOS.h"
#include "task.h"

#define DEMO_LED_MODE_OFF       0UL
#define DEMO_LED_MODE_LED0      1UL
#define DEMO_LED_MODE_LED1      2UL
#define DEMO_LED_MODE_BOTH      3UL

#define DEMO_CORE_NOTIFY_START  (1UL << 0)
#define DEMO_GPIO_NOTIFY_BTN0   (1UL << 0)
#define DEMO_GPIO_NOTIFY_BTN1   (1UL << 1)

extern TaskHandle_t g_gpio_task_handle;
extern TaskHandle_t g_coremark_task_handle;
extern TaskHandle_t g_led_task_handle;

extern volatile uint32_t g_led_mode;
extern volatile uint32_t g_led_power;
extern volatile uint32_t g_led_speed;
extern volatile uint32_t g_gpio_irq_count;
extern volatile uint32_t g_gpio_last_buttons;
extern volatile uint32_t g_coremark_busy;
extern volatile uint32_t g_coremark_runs;
extern volatile uint32_t g_demo_debug;
extern volatile uint32_t g_demo_boot_ready;

const char *demo_led_mode_name(uint32_t mode);
void demo_set_led_mode(uint32_t mode);
void demo_cycle_led_mode(void);
void demo_toggle_led_power(void);
void demo_set_led_speed(uint32_t speed);
void demo_request_coremark(const char *source);
void demo_print_stats(void);

#endif
