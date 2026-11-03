#ifndef FREERTOS_DEMO_RTOS_MONITOR_H
#define FREERTOS_DEMO_RTOS_MONITOR_H

#include <stdint.h>

#include "FreeRTOS.h"
#include "task.h"

#define RTOS_MONITOR_MAX_TASKS 8

uint32_t rtos_monitor_get_run_time_counter(void);

void rtos_monitor_enter_top(uint32_t showcase);
void rtos_monitor_leave_top(void);
uint32_t rtos_monitor_is_active(void);
uint32_t rtos_monitor_is_showcase(void);
uint32_t rtos_monitor_service_key(int ch);
void rtos_monitor_refresh_if_due(void);
void rtos_monitor_top_once(void);

void rtos_monitor_coremark_start(void);
void rtos_monitor_coremark_measurement_stopped(void);
uint32_t rtos_monitor_coremark_completed(void);

#endif
