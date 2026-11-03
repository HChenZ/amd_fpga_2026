#ifndef FREERTOS_CONFIG_H
#define FREERTOS_CONFIG_H

#include "platform.h"

#define configCPU_CLOCK_HZ                         PLATFORM_CPU_CLOCK_HZ
#define configTICK_RATE_HZ                         1000UL
#define configMTIME_BASE_ADDRESS                   PLATFORM_CLINT_MTIME
#define configMTIMECMP_BASE_ADDRESS                PLATFORM_CLINT_MTIMECMP

#define configUSE_PREEMPTION                       1
#define configUSE_TIME_SLICING                     1
#define configUSE_PORT_OPTIMISED_TASK_SELECTION    0
#define configUSE_TICKLESS_IDLE                    0
#define configMAX_PRIORITIES                       5
#define configMINIMAL_STACK_SIZE                   256
#define configMAX_TASK_NAME_LEN                    12
#define configTICK_TYPE_WIDTH_IN_BITS              TICK_TYPE_WIDTH_32_BITS
#define configIDLE_SHOULD_YIELD                    1
#define configNUMBER_OF_CORES                      1

#define configSUPPORT_STATIC_ALLOCATION            0
#define configSUPPORT_DYNAMIC_ALLOCATION           1
#define configTOTAL_HEAP_SIZE                      (48UL * 1024UL)
#define configAPPLICATION_ALLOCATED_HEAP           0

#define configUSE_MUTEXES                          1
#define configUSE_RECURSIVE_MUTEXES                0
#define configUSE_COUNTING_SEMAPHORES              0
#define configUSE_QUEUE_SETS                       0
#define configUSE_TASK_NOTIFICATIONS               1
#define configUSE_TIMERS                           0
#define configUSE_EVENT_GROUPS                     0
#define configUSE_STREAM_BUFFERS                   0
#define configUSE_CO_ROUTINES                      0
#define configQUEUE_REGISTRY_SIZE                  0
#define configUSE_NEWLIB_REENTRANT                 0
#define configENABLE_BACKWARD_COMPATIBILITY        0
#define configNUM_THREAD_LOCAL_STORAGE_POINTERS    0

#define configUSE_IDLE_HOOK                        0
#define configUSE_TICK_HOOK                        0
#define configUSE_MALLOC_FAILED_HOOK               1
#define configCHECK_FOR_STACK_OVERFLOW             2
#define configUSE_DAEMON_TASK_STARTUP_HOOK         0

#define configGENERATE_RUN_TIME_STATS              1
#define configUSE_TRACE_FACILITY                   1
#define configUSE_STATS_FORMATTING_FUNCTIONS       0

#ifndef __ASSEMBLER__
uint32_t rtos_monitor_get_run_time_counter(void);
#endif
#define portCONFIGURE_TIMER_FOR_RUN_TIME_STATS()  do { } while (0)
#define portGET_RUN_TIME_COUNTER_VALUE()          rtos_monitor_get_run_time_counter()

#define configISR_STACK_SIZE_WORDS                 256
#define configENABLE_FPU                           0
#define configENABLE_VPU                           0

#ifndef __ASSEMBLER__
void vAssertCalled(const char *file, unsigned long line);
#endif

#define configASSERT(x)                            \
    do                                             \
    {                                              \
        if ((x) == 0)                              \
        {                                          \
            vAssertCalled(__FILE__, __LINE__);     \
        }                                          \
    } while (0)

#define INCLUDE_vTaskPrioritySet                   0
#define INCLUDE_uxTaskPriorityGet                  0
#define INCLUDE_vTaskDelete                        0
#define INCLUDE_vTaskSuspend                       1
#define INCLUDE_xTaskDelayUntil                    1
#define INCLUDE_vTaskDelay                         1
#define INCLUDE_xTaskGetSchedulerState             1
#define INCLUDE_xTaskGetCurrentTaskHandle          0
#define INCLUDE_uxTaskGetStackHighWaterMark        1
#define INCLUDE_uxTaskGetNumberOfTasks             1
#define INCLUDE_xTaskGetIdleTaskHandle             0
#define INCLUDE_eTaskGetState                      0
#define INCLUDE_xTimerPendFunctionCall             0
#define INCLUDE_xTaskAbortDelay                    0
#define INCLUDE_xTaskGetHandle                     0
#define INCLUDE_xTaskResumeFromISR                 0

#endif
