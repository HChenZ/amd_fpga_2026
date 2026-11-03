#include <stdint.h>

#include "FreeRTOS.h"
#include "task.h"

#include "coremark_runner.h"
#include "demo.h"
#include "platform.h"
#include "rtos_monitor.h"
#include "uart.h"

TaskHandle_t g_gpio_task_handle;
TaskHandle_t g_coremark_task_handle;
TaskHandle_t g_led_task_handle;

volatile uint32_t g_led_mode = DEMO_LED_MODE_BOTH;
volatile uint32_t g_led_power = 1U;
volatile uint32_t g_led_speed = 2U;
volatile uint32_t g_gpio_irq_count;
volatile uint32_t g_gpio_last_buttons;
volatile uint32_t g_coremark_busy;
volatile uint32_t g_coremark_pending;
volatile uint32_t g_coremark_runs;
volatile uint32_t g_demo_debug;
volatile uint32_t g_demo_boot_ready = 0U;

static int streq(const char *lhs, const char *rhs)
{
    while ((*lhs != '\0') && (*rhs != '\0') && (*lhs == *rhs))
    {
        lhs++;
        rhs++;
    }

    return (*lhs == '\0') && (*rhs == '\0');
}

const char *demo_led_mode_name(uint32_t mode)
{
    switch (mode)
    {
        case DEMO_LED_MODE_OFF:
            return "OFF";
        case DEMO_LED_MODE_LED0:
            return "LED0";
        case DEMO_LED_MODE_LED1:
            return "LED1";
        case DEMO_LED_MODE_BOTH:
            return "BOTH";
        default:
            return "?";
    }
}

void demo_set_led_mode(uint32_t mode)
{
    if (mode > DEMO_LED_MODE_BOTH)
    {
        mode = DEMO_LED_MODE_BOTH;
    }

    g_led_mode = mode;
}

void demo_cycle_led_mode(void)
{
    uint32_t next;

    if (g_led_mode == DEMO_LED_MODE_LED0)
    {
        next = DEMO_LED_MODE_LED1;
    }
    else if (g_led_mode == DEMO_LED_MODE_LED1)
    {
        next = DEMO_LED_MODE_BOTH;
    }
    else
    {
        next = DEMO_LED_MODE_LED0;
    }

    demo_set_led_mode(next);
}

void demo_toggle_led_power(void)
{
    g_led_power ^= 1U;
}

void demo_set_led_speed(uint32_t speed)
{
    if (speed < 1U)
    {
        speed = 1U;
    }
    else if (speed > 3U)
    {
        speed = 3U;
    }

    g_led_speed = speed;
}

void demo_request_coremark(const char *source)
{
    uint32_t should_notify = 0;

    if (g_demo_debug != 0U)
    {
        console_lock();
        console_puts("[CoreMark][dbg] request from ");
        console_puts(source != 0 ? source : "unknown");
        console_puts(" boot=");
        console_puts(g_demo_boot_ready ? "ready" : "wait");
        console_puts(" busy=");
        console_puts(g_coremark_busy ? "1" : "0");
        console_puts(" pending=");
        console_puts(g_coremark_pending ? "1" : "0");
        console_puts("\n");
        console_unlock();
    }

    if (g_coremark_task_handle == NULL)
    {
        console_lock();
        console_puts("[CoreMark] disabled");
        if (source != 0)
        {
            console_puts(" from ");
            console_puts(source);
        }
        console_puts("\n");
        console_unlock();
        return;
    }

    if (g_demo_boot_ready == 0U)
    {
        console_lock();
        console_puts("[CoreMark] boot not ready");
        if (source != 0)
        {
            console_puts(" from ");
            console_puts(source);
        }
        console_puts("\n");
        console_unlock();
        return;
    }

    taskENTER_CRITICAL();
    if ((g_coremark_busy != 0U) || (g_coremark_pending != 0U))
    {
        taskEXIT_CRITICAL();

        console_lock();
        console_puts("[CoreMark] busy");
        if (source != 0)
        {
            console_puts(" from ");
            console_puts(source);
        }
        console_puts("\n");
        console_unlock();
        return;
    }

    g_coremark_pending = 1U;
    should_notify = (g_coremark_task_handle != NULL) ? 1U : 0U;
    taskEXIT_CRITICAL();

    if (should_notify != 0U)
    {
        (void) xTaskNotify(g_coremark_task_handle, DEMO_CORE_NOTIFY_START, eSetBits);
    }
}

void demo_print_stats(void)
{
    console_lock();
    console_puts("[stats] tick=");
    console_put_dec32((uint32_t) xTaskGetTickCount());
    console_puts(" led=");
    console_puts(g_led_power ? demo_led_mode_name(g_led_mode) : "off");
    console_puts(" power=");
    console_puts(g_led_power ? "on" : "off");
    console_puts(" speed=");
    console_put_dec32(g_led_speed);
    console_puts(" core=");
    if (g_coremark_task_handle == NULL)
    {
        console_puts("disabled");
    }
    else
    {
        console_puts((g_coremark_busy != 0U) ? "running" :
                     (g_coremark_pending != 0U) ? "pending" : "idle");
    }
    console_puts(" runs=");
    console_put_dec32(g_coremark_runs);
    console_puts(" gpio_irq=");
    console_put_dec32(g_gpio_irq_count);
    console_puts(" btn=");
    console_put_hex32(g_gpio_last_buttons);
    console_puts(" boot=");
    console_puts(g_demo_boot_ready ? "ready" : "wait");
    console_puts("\n");
    console_unlock();
}

static void print_prompt(void)
{
    console_lock();
    console_puts("demo> ");
    console_unlock();
}

static void print_help(void)
{
    console_lock();
    console_puts("\ncommands:\n");
    console_puts("  help\n");
    console_puts("  showcase\n");
    console_puts("  top\n");
    console_puts("  top once\n");
    console_puts("  led\n");
    console_puts("  speed 1|2|3 (slow/normal/fast)\n");
    console_puts("  coremark\n");
    console_puts("  stats\n");
    console_unlock();
}

static void print_boot_banner(void)
{
    console_lock();
    console_puts("\nRTOS start\n");
    console_puts("[boot] BTN0: power ON/OFF\n");
    console_puts("[boot] BTN1: LED mode LED0/LED1/BOTH\n");
    console_puts("[boot] coremark=manual\n");
    console_puts("type 'help' for commands\n");
    console_unlock();
}

static void handle_led_start(void)
{
    g_led_power = 1U;

    console_lock();
    console_puts("[led] started mode=");
    console_puts(demo_led_mode_name(g_led_mode));
    console_puts("\n");
    console_unlock();
}

static void handle_command(const char *cmd)
{
    if (cmd[0] == '\0')
    {
        return;
    }

    if (streq(cmd, "help"))
    {
        print_help();
    }
    else if (streq(cmd, "showcase"))
    {
        rtos_monitor_enter_top(1U);
    }
    else if (streq(cmd, "top"))
    {
        rtos_monitor_enter_top(0U);
    }
    else if (streq(cmd, "top once"))
    {
        rtos_monitor_top_once();
    }
    else if (streq(cmd, "led"))
    {
        handle_led_start();
    }
    else if (streq(cmd, "coremark"))
    {
        demo_request_coremark("uart");
    }
    else if (streq(cmd, "debug on"))
    {
        g_demo_debug = 1U;
        console_puts("[debug] on\n");
    }
    else if (streq(cmd, "debug off"))
    {
        g_demo_debug = 0U;
        console_puts("[debug] off\n");
    }
    else if (streq(cmd, "speed 1"))
    {
        demo_set_led_speed(1U);
    }
    else if (streq(cmd, "speed 2"))
    {
        demo_set_led_speed(2U);
    }
    else if (streq(cmd, "speed 3"))
    {
        demo_set_led_speed(3U);
    }
    else if (streq(cmd, "stats"))
    {
        demo_print_stats();
    }
    else
    {
        console_lock();
        console_puts("[shell] unknown command: ");
        console_puts(cmd);
        console_puts("\n");
        console_unlock();
    }
}

static void demo_write_led_pwm(uint32_t led_mask, uint32_t duty)
{
    /* Keep every envelope update in the same hardware PWM mode. The GPIO
     * block applies this register at a frame boundary, so zero/full duty do
     * not cause an asynchronous direct-drive transition. */
    mmio_write32(PLATFORM_GPIO_LED,
                 PLATFORM_GPIO_LED_PWM_ENABLE |
                 ((duty > 255U ? 255U : duty) << PLATFORM_GPIO_LED_PWM_DUTY_SHIFT) |
                 (led_mask & 0x3U));
}

static void led_task(void *arg)
{
    (void) arg;

    TickType_t last_wake = xTaskGetTickCount();
    uint32_t breath_phase = 0U;
    uint32_t breath_accum = 0U;
    int32_t breath_dir = 1;
    static const uint16_t gamma_lut[33] = {
        0U, 0U, 1U, 1U, 3U, 4U, 6U, 9U, 12U, 16U, 20U,
        24U, 30U, 35U, 42U, 48U, 56U, 64U, 72U, 81U, 91U,
        101U, 112U, 124U, 136U, 149U, 162U, 176U, 191U, 206U,
        222U, 239U, 256U
    };

    for (;;)
    {
        uint32_t mode = g_led_mode;
        uint32_t led_mask = (mode == DEMO_LED_MODE_LED0) ? 0x1U :
                            (mode == DEMO_LED_MODE_LED1) ? 0x2U : 0x3U;
        uint32_t step_q8 = (g_led_speed == 1U) ? 26U :
                           (g_led_speed == 2U) ? 43U : 85U;
        uint32_t gamma_duty;
        TickType_t now = xTaskGetTickCount();

        if ((TickType_t) (now - last_wake) > pdMS_TO_TICKS(2UL))
        {
            last_wake = now;
        }

        if (g_coremark_busy != 0U)
        {
            mmio_write32(PLATFORM_GPIO_LED,
                         (g_coremark_busy != 0U && g_led_power) ? 0x3U : 0U);
            (void) xTaskDelayUntil(&last_wake, pdMS_TO_TICKS(1UL));
            continue;
        }

        if (!g_led_power || (mode == DEMO_LED_MODE_OFF))
        {
            mmio_write32(PLATFORM_GPIO_LED, 0U);
            breath_phase = 0U;
            breath_accum = 0U;
            breath_dir = 1;
        }
        else
        {
            breath_accum += step_q8;
            if (breath_accum >= 256U)
            {
                breath_accum -= 256U;
                if (breath_dir > 0)
                {
                    if (breath_phase < 255U)
                        breath_phase++;
                    if (breath_phase >= 255U)
                        breath_dir = -1;
                }
                else
                {
                    if (breath_phase > 0U)
                        breath_phase--;
                    if (breath_phase == 0U)
                        breath_dir = 1;
                }
            }

            {
                uint32_t gamma_index = breath_phase >> 3;
                uint32_t gamma_frac = breath_phase & 0x7U;
                uint32_t gamma_lo = gamma_lut[gamma_index];
                uint32_t gamma_hi = gamma_lut[gamma_index + 1U];

                gamma_duty = gamma_lo +
                             (((gamma_hi - gamma_lo) * gamma_frac + 4U) >> 3);
                demo_write_led_pwm(led_mask, gamma_duty);
            }
        }

        (void) xTaskDelayUntil(&last_wake, pdMS_TO_TICKS(1UL));
    }
}

static void uart_cmd_task(void *arg)
{
    (void) arg;

    char line[48];
    uint32_t pos = 0;

    print_prompt();

    for (;;)
    {
        int ch = uart_getchar_nonblock();

        if (rtos_monitor_is_active() != 0U)
        {
            while (ch >= 0)
            {
                (void)rtos_monitor_service_key(ch);
                ch = uart_getchar_nonblock();
            }
            rtos_monitor_refresh_if_due();
            vTaskDelay(pdMS_TO_TICKS(10UL));
            continue;
        }

        while (ch >= 0)
        {
            if ((ch == '\r') || (ch == '\n'))
            {
                line[pos] = '\0';
                console_lock();
                console_puts("\n");
                console_unlock();
                handle_command(line);
                pos = 0;
                if (rtos_monitor_is_active() == 0U)
                {
                    print_prompt();
                }
            }
            else if ((ch == 0x08) || (ch == 0x7f))
            {
                if (pos > 0U)
                {
                    pos--;
                    console_lock();
                    console_puts("\b \b");
                    console_unlock();
                }
            }
            else if ((ch >= 0x20) && (ch <= 0x7e))
            {
                if (pos + 1U < sizeof(line))
                {
                    line[pos++] = (char) ch;
                    console_lock();
                    uart_putchar((char) ch);
                    console_unlock();
                }
            }

            ch = uart_getchar_nonblock();
        }

        vTaskDelay(pdMS_TO_TICKS(5UL));
    }
}

static void gpio_event_task(void *arg)
{
    (void) arg;

    for (;;)
    {
        uint32_t bits = 0;

        (void) xTaskNotifyWait(0, UINT32_MAX, &bits, portMAX_DELAY);

        if (rtos_monitor_is_active() == 0U)
        {
            console_lock();
            console_puts("[IRQ] GPIO btn=");
            console_put_hex32(g_gpio_last_buttons);
            console_puts(" count=");
            console_put_dec32(g_gpio_irq_count);
            console_puts("\n");
            console_unlock();
        }

        if ((bits & DEMO_GPIO_NOTIFY_BTN0) != 0U)
        {
            demo_toggle_led_power();
            if (rtos_monitor_is_active() == 0U)
            {
                console_lock();
                console_puts("[BTN0] power=");
                console_puts(g_led_power ? "ON" : "OFF");
                console_puts("\n");
                console_unlock();
            }
        }

        if ((bits & DEMO_GPIO_NOTIFY_BTN1) != 0U)
        {
            demo_cycle_led_mode();
            if (rtos_monitor_is_active() == 0U)
            {
                console_lock();
                console_puts("[BTN1] mode=");
                console_puts(demo_led_mode_name(g_led_mode));
                console_puts("\n");
                console_unlock();
            }
        }
    }
}

#if !defined(DEMO_LED_ONLY)
static void coremark_task(void *arg)
{
    (void) arg;

    uint32_t notification = 0;

    for (;;)
    {
        (void) xTaskNotifyWait(0, UINT32_MAX, &notification, portMAX_DELAY);

        if ((notification & DEMO_CORE_NOTIFY_START) == 0U)
        {
            continue;
        }

        if (g_demo_debug != 0U)
        {
            console_lock();
            console_puts("[CoreMark][dbg] task notified\n");
            console_unlock();
        }

        taskENTER_CRITICAL();
        g_coremark_pending = 0U;
        g_coremark_busy = 1U;
        taskEXIT_CRITICAL();

        rtos_monitor_coremark_start();

        if (g_led_task_handle != NULL)
        {
            mmio_write32(PLATFORM_GPIO_LED, g_led_power ? 0x3U : 0U);
            vTaskSuspend(g_led_task_handle);
        }

        console_lock();
        console_puts("[demo] CoreMark performance test started\n");
        console_unlock();

        if (g_demo_debug != 0U)
        {
            console_lock();
            console_puts("[CoreMark][dbg] enter coremark_run_once\n");
            console_unlock();
        }
        (void) coremark_run_once();
        if (g_demo_debug != 0U)
        {
            console_lock();
            console_puts("[CoreMark][dbg] leave coremark_run_once\n");
            console_unlock();
        }

        taskENTER_CRITICAL();
        g_coremark_busy = 0U;
        g_coremark_runs++;
        taskEXIT_CRITICAL();
        uint32_t was_monitored = rtos_monitor_coremark_completed();

        if (g_led_task_handle != NULL)
        {
            vTaskResume(g_led_task_handle);
        }

        console_lock();
        console_puts("[demo] CoreMark complete; LED breathing resumed, runs=");
        console_put_dec32(g_coremark_runs);
        console_puts("\n");
        if (was_monitored != 0U)
        {
            console_puts("demo> ");
        }
        console_unlock();

    }
}
#endif

int main(void)
{
    mmio_write32(PLATFORM_GPIO_LED, 0U);
    g_led_mode = DEMO_LED_MODE_BOTH;
    g_led_power = 1U;
    g_led_speed = 2U;
    g_gpio_irq_count = 0U;
    g_gpio_last_buttons = 0U;
    g_coremark_busy = 0U;
    g_coremark_pending = 0U;
    g_coremark_runs = 0U;
    g_demo_boot_ready = 0U;
    g_demo_debug = 0U;

    BaseType_t ok = pdPASS;

    if (xTaskCreate(led_task, "led", 256, NULL, 2, &g_led_task_handle) != pdPASS)
    {
        ok = pdFAIL;
    }
#if !defined(DEMO_LED_ONLY)
    uart_init();
    console_init();

    print_boot_banner();

    if (xTaskCreate(uart_cmd_task, "uart", 512, NULL, 3, NULL) != pdPASS)
    {
        ok = pdFAIL;
    }
    if (xTaskCreate(gpio_event_task, "gpio", 384, NULL, 4, &g_gpio_task_handle) != pdPASS)
    {
        ok = pdFAIL;
    }
#if !defined(DEMO_LED_ONLY)
    if (xTaskCreate(coremark_task, "coremark", 2048, NULL, 1, &g_coremark_task_handle) != pdPASS)
    {
        ok = pdFAIL;
    }
#endif
    /* Keep the shell quiet during long benchmarks; stats remain available
     * through the existing helper if a diagnostic task is needed later. */

    console_lock();
    console_puts("[boot] uart task ready\n");
    console_puts("[boot] coremark is manual only\n");
    console_unlock();
#endif

    if (ok != pdPASS)
    {
        uart_puts("task create failed\n");
        for (;;)
        {
        }
    }

    g_demo_boot_ready = 1U;

    console_lock();
    console_puts("[boot] scheduler start\n");
    console_unlock();

    vTaskStartScheduler();

    uart_puts("scheduler returned\n");
    for (;;)
    {
    }
}

void vApplicationMallocFailedHook(void)
{
    uart_puts("malloc failed\n");
    taskDISABLE_INTERRUPTS();
    for (;;)
    {
    }
}

void vApplicationStackOverflowHook(TaskHandle_t task, char *task_name)
{
    (void) task;

    uart_puts("stack overflow: ");
    uart_puts(task_name);
    uart_puts("\n");
    taskDISABLE_INTERRUPTS();
    for (;;)
    {
    }
}

void vAssertCalled(const char *file, unsigned long line)
{
    uart_puts("assert: ");
    uart_puts(file);
    uart_puts(":");
    uart_put_hex32((uint32_t) line);
    uart_puts("\n");
    taskDISABLE_INTERRUPTS();
    for (;;)
    {
    }
}
