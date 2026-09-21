#include <stdint.h>

#include "FreeRTOS.h"
#include "task.h"

#include "demo.h"
#include "rtos_monitor.h"
#include "uart.h"

static volatile uint32_t g_top_active;
static volatile uint32_t g_top_showcase;
static volatile uint32_t g_coremark_monitored;
static TickType_t g_next_refresh;
static uint32_t g_prev_valid;

static TaskStatus_t g_prev_tasks[RTOS_MONITOR_MAX_TASKS];
static TaskStatus_t g_curr_tasks[RTOS_MONITOR_MAX_TASKS];
static uint32_t g_prev_total;
static uint32_t g_prev_count;

static uint32_t mcycle_read_scaled(void)
{
    uint32_t high_before;
    uint32_t low;
    uint32_t high_after;

    do
    {
        __asm volatile("csrr %0, 0xB80" : "=r"(high_before));
        __asm volatile("csrr %0, 0xB00" : "=r"(low));
        __asm volatile("csrr %0, 0xB80" : "=r"(high_after));
    } while (high_before != high_after);

    /* (high:low) >> 10 without a 64-bit helper on RV32. */
    return (low >> 10) | (high_after << 22);
}

uint32_t rtos_monitor_get_run_time_counter(void)
{
    return mcycle_read_scaled();
}

static void put_u32_width(uint32_t value, uint32_t width)
{
    char buf[10];
    uint32_t pos = 0U;

    do
    {
        buf[pos++] = (char)('0' + (value % 10U));
        value /= 10U;
    } while (value != 0U);

    while (pos < width)
    {
        uart_putchar(' ');
        width--;
    }
    while (pos != 0U)
    {
        uart_putchar(buf[--pos]);
    }
}

static void put_percent10(uint32_t value)
{
    if (value > 1000U)
    {
        value = 1000U;
    }
    put_u32_width(value / 10U, 1U);
    uart_putchar('.');
    uart_putchar((char)('0' + (value % 10U)));
}

static void put_two_digits(uint32_t value)
{
    uart_putchar((char)('0' + ((value / 10U) % 10U)));
    uart_putchar((char)('0' + (value % 10U)));
}

static void put_uptime(void)
{
    uint32_t seconds = (uint32_t)(xTaskGetTickCount() / configTICK_RATE_HZ);
    uint32_t hours = seconds / 3600U;
    uint32_t minutes;

    seconds %= 3600U;
    minutes = seconds / 60U;
    seconds %= 60U;
    if (hours < 100U)
    {
        put_two_digits(hours);
    }
    else
    {
        put_u32_width(hours, 1U);
    }
    uart_putchar(':');
    put_two_digits(minutes);
    uart_putchar(':');
    put_two_digits(seconds);
}

static void put_text_width(const char *text, uint32_t width)
{
    uint32_t length = 0U;

    while ((text[length] != '\0') && (length < width))
    {
        uart_putchar(text[length]);
        length++;
    }
    while (length < width)
    {
        uart_putchar(' ');
        length++;
    }
}

static const char *state_name(eTaskState state)
{
    switch (state)
    {
        case eRunning: return "RUN";
        case eReady: return "READY";
        case eBlocked: return "BLOCK";
        case eSuspended: return "SUSP";
        case eDeleted: return "DEL";
        default: return "?";
    }
}

static uint32_t streq_name(const char *lhs, const char *rhs)
{
    while ((*lhs != '\0') && (*rhs != '\0') && (*lhs == *rhs))
    {
        lhs++;
        rhs++;
    }
    return (uint32_t)((*lhs == '\0') && (*rhs == '\0'));
}

static uint32_t monitor_task_name(const char *name)
{
    return streq_name(name, "led") || streq_name(name, "coremark");
}

static uint32_t task_delta(const TaskStatus_t *task)
{
    uint32_t i;
    for (i = 0U; i < g_prev_count; i++)
    {
        if (g_prev_tasks[i].xHandle == task->xHandle)
        {
            return (uint32_t)(task->ulRunTimeCounter - g_prev_tasks[i].ulRunTimeCounter);
        }
    }
    return 0U;
}

static void print_task_row(const TaskStatus_t *task, uint32_t total_delta)
{
    uint32_t delta = task_delta(task);
    uint32_t cpu10 = (total_delta != 0U) ? (delta * 1000U) / total_delta : 0U;

    put_text_width(task->pcTaskName != NULL ? task->pcTaskName : "?", 11U);
    put_text_width(state_name(task->eCurrentState), 8U);
    put_percent10(cpu10);
    console_puts("%");
    console_puts("\n");
}

static void capture_baseline(void)
{
    configRUN_TIME_COUNTER_TYPE total_runtime = 0U;
    UBaseType_t count;
    uint32_t i;

    count = uxTaskGetSystemState(g_curr_tasks, RTOS_MONITOR_MAX_TASKS, &total_runtime);
    if (count == 0U)
    {
        g_prev_valid = 0U;
        g_prev_count = 0U;
        return;
    }

    for (i = 0U; i < (uint32_t)count; i++)
    {
        g_prev_tasks[i] = g_curr_tasks[i];
    }
    g_prev_count = (uint32_t)count;
    g_prev_total = (uint32_t)total_runtime;
    g_prev_valid = 1U;
}

static void print_top_frame(void)
{
    UBaseType_t count;
    configRUN_TIME_COUNTER_TYPE total_runtime = 0U;
    uint32_t total_delta;
    uint32_t idle_delta = 0U;
    uint32_t i;

    count = uxTaskGetSystemState(g_curr_tasks, RTOS_MONITOR_MAX_TASKS, &total_runtime);
    if (count == 0U)
    {
        return;
    }

    total_delta = g_prev_valid ? (uint32_t)((uint32_t)total_runtime - g_prev_total) : 0U;
    for (i = 0U; i < (uint32_t)count; i++)
    {
        if ((g_curr_tasks[i].pcTaskName != NULL) &&
            ((g_curr_tasks[i].pcTaskName[0] == 'I') ||
             (g_curr_tasks[i].pcTaskName[0] == 'i')))
        {
            idle_delta = task_delta(&g_curr_tasks[i]);
            break;
        }
    }

    console_lock();
    console_puts("\n");
    console_puts("FreeRTOS TOP | ");
    console_puts(tskKERNEL_VERSION_NUMBER);
    console_puts(" | uptime ");
    put_uptime();
    console_puts("\nCPU: ");
    {
        uint32_t idle10 = total_delta != 0U ? (idle_delta * 1000U) / total_delta : 0U;
        put_percent10(idle10 > 1000U ? 0U : 1000U - idle10);
    }
    console_puts("%  IDLE: ");
    put_percent10(total_delta != 0U ? (idle_delta * 1000U) / total_delta : 0U);
    console_puts("%\n\n");
    console_puts("TASK       STATE   CPU%\n");

    for (uint32_t priority = configMAX_PRIORITIES; priority > 0U; priority--)
    {
        for (i = 0U; i < (uint32_t)count; i++)
        {
            if ((uint32_t)g_curr_tasks[i].uxCurrentPriority == priority &&
                g_curr_tasks[i].pcTaskName != NULL &&
                monitor_task_name(g_curr_tasks[i].pcTaskName))
            {
                print_task_row(&g_curr_tasks[i], total_delta);
            }
        }
    }
    if (g_top_showcase != 0U)
    {
        console_puts("\nkeys: c CoreMark | q quit\n");
    }
    console_unlock();

    for (i = 0U; i < (uint32_t)count; i++)
    {
        g_prev_tasks[i] = g_curr_tasks[i];
    }
    g_prev_count = (uint32_t)count;
    g_prev_total = (uint32_t)total_runtime;
    g_prev_valid = 1U;
}

void rtos_monitor_enter_top(uint32_t showcase)
{
    g_top_showcase = showcase;
    g_top_active = 1U;
    capture_baseline();
    g_next_refresh = xTaskGetTickCount() + pdMS_TO_TICKS(3000UL);
}

void rtos_monitor_leave_top(void)
{
    if (g_top_active != 0U)
    {
        g_top_active = 0U;
        g_top_showcase = 0U;
    }
}

uint32_t rtos_monitor_is_active(void)
{
    return g_top_active;
}

uint32_t rtos_monitor_is_showcase(void)
{
    return g_top_showcase;
}

void rtos_monitor_refresh_if_due(void)
{
    if ((g_top_active != 0U) && ((int32_t)(xTaskGetTickCount() - g_next_refresh) >= 0))
    {
        print_top_frame();
        g_next_refresh = xTaskGetTickCount() + pdMS_TO_TICKS(3000UL);
    }
}

uint32_t rtos_monitor_service_key(int ch)
{
    if (g_top_active == 0U)
    {
        return 0U;
    }
    switch (ch)
    {
        case 'q': case 'Q':
            rtos_monitor_leave_top();
            console_lock();
            console_puts("demo> ");
            console_unlock();
            return 1U;
        case 'c': case 'C': demo_request_coremark("top"); return 1U;
        default: return 1U;
    }
}

void rtos_monitor_top_once(void)
{
    g_top_active = 0U;
    g_top_showcase = 0U;
    capture_baseline();
    vTaskDelay(pdMS_TO_TICKS(500UL));
    print_top_frame();
}

void rtos_monitor_coremark_start(void)
{
    g_coremark_monitored = g_top_active;
    if (g_coremark_monitored != 0U)
    {
        console_lock();
        console_puts("[demo] monitored CoreMark; top overhead is included\n");
        console_unlock();
    }
}

void rtos_monitor_coremark_measurement_stopped(void)
{
    if (g_coremark_monitored != 0U)
    {
        rtos_monitor_leave_top();
    }
}

uint32_t rtos_monitor_coremark_completed(void)
{
    uint32_t was_monitored = g_coremark_monitored;
    g_coremark_monitored = 0U;
    return was_monitored;
}
