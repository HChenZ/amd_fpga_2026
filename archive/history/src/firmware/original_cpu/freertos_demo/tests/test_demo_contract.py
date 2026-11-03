import pathlib
import re
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
MAIN = (ROOT / "main.c").read_text(encoding="utf-8")
DEMO_H = (ROOT / "include" / "demo.h").read_text(encoding="utf-8")
MAKEFILE = (ROOT / "Makefile").read_text(encoding="utf-8")
PORTME = (ROOT / "coremark" / "core_portme.h").read_text(encoding="utf-8")
PORTME_C = (ROOT / "coremark" / "core_portme.c").read_text(encoding="utf-8")
TRAP = (ROOT / "trap.c").read_text(encoding="utf-8")
FREERTOS_CONFIG = (ROOT / "include" / "FreeRTOSConfig.h").read_text(encoding="utf-8")
PLATFORM = (ROOT / "include" / "platform.h").read_text(encoding="utf-8")
MONITOR_C_PATH = ROOT / "rtos_monitor.c"
MONITOR_H_PATH = ROOT / "include" / "rtos_monitor.h"
MONITOR_C = MONITOR_C_PATH.read_text(encoding="utf-8") if MONITOR_C_PATH.exists() else ""
MONITOR_H = MONITOR_H_PATH.read_text(encoding="utf-8") if MONITOR_H_PATH.exists() else ""
SIM_ROOT = ROOT.parents[2] / "rtl_repro_full"
TB = (SIM_ROOT / "tb" / "tb_freertos_soc.sv").read_text(encoding="utf-8")
RUN_PS1 = (SIM_ROOT / "run_freertos.ps1").read_text(encoding="utf-8")
RTL_GPIO = (ROOT.parents[1] / "rtl" / "gpio.v").read_text(encoding="utf-8")
SIM_GPIO = (SIM_ROOT / "rtl" / "gpio.v").read_text(encoding="utf-8")


class DemoContractTests(unittest.TestCase):
    def test_led_task_uses_periodic_envelope_and_hardware_pwm(self):
        self.assertIn("pdMS_TO_TICKS(1UL)", MAIN)
        self.assertIn("xTaskDelayUntil", MAIN)
        self.assertIn("demo_write_led_pwm", MAIN)
        self.assertIn("breath_phase", MAIN)
        self.assertIn("gamma_duty", MAIN)
        self.assertIn("g_coremark_busy", MAIN)
        self.assertNotIn("pwm_phase", MAIN)
        self.assertNotIn("pdm_accum", MAIN)
        self.assertRegex(MAIN, r'xTaskCreate\(led_task,\s*"led",\s*256,\s*NULL,\s*2,')
        self.assertIn("PLATFORM_GPIO_LED_PWM_ENABLE", PLATFORM)
        self.assertIn("PLATFORM_GPIO_LED_PWM_DUTY_SHIFT", PLATFORM)
        self.assertIn("#define INCLUDE_xTaskDelayUntil                    1", FREERTOS_CONFIG)

    def test_startup_and_button_mode_contract(self):
        main_body = MAIN[MAIN.index("int main(void)"):]
        self.assertRegex(main_body, r"g_led_mode\s*=\s*DEMO_LED_MODE_BOTH")
        cycle_body = MAIN[MAIN.index("void demo_cycle_led_mode"):MAIN.index("void demo_toggle_led_power")]
        self.assertNotIn("DEMO_LED_MODE_OFF", cycle_body)
        self.assertIn('return "LED0"', MAIN)

    def test_debug_switch_and_concise_coremark_messages_exist(self):
        self.assertIn('"debug on"', MAIN)
        self.assertIn('"debug off"', MAIN)
        self.assertIn("g_demo_debug", DEMO_H)
        self.assertIn("CoreMark performance test started", MAIN)
        self.assertIn("CoreMark complete; LED breathing resumed", MAIN)

    def test_redundant_hex_cpi_summary_is_not_printed(self):
        self.assertNotIn("[coremark][cpi]", MAIN)
        self.assertNotIn("print_cpi_stats", MAIN)

    def test_gpio_reports_active_low_latched_button_events(self):
        for gpio in (RTL_GPIO, SIM_GPIO):
            self.assertIn("~key_out & btn_clean_d1", gpio)
            self.assertIn("BTN: rdata_reg <= {30'b0, btn_latched}", gpio)
            self.assertRegex(gpio, r"cnt1\s*<=\s*21'd0")
            self.assertIn("PWM_DIV_MAX", gpio)
            self.assertIn("led_control", gpio)
            self.assertIn("led_control_active", gpio)
            self.assertIn("pwm_phase", gpio)
        self.assertIn("DEMO_GPIO_NOTIFY_BTN0", TRAP)
        self.assertIn("DEMO_GPIO_NOTIFY_BTN1", TRAP)
        self.assertNotIn("g_gpio_boot_ignore_once", MAIN)

    def test_coremark_uses_both_leds_as_the_running_indicator(self):
        task_body = MAIN[MAIN.index("static void coremark_task"):MAIN.index("int main(void)")]
        self.assertIn("g_led_power ? 0x3U : 0U", task_body)

    def test_simulation_can_verify_coremark_completion_and_led_resume(self):
        self.assertIn("COREMARK_ITERATIONS_OVERRIDE", TB)
        self.assertIn("COREMARK_RUNS_WORD_PARAM", TB)
        self.assertIn("COREMARK_BUSY_WORD_PARAM", TB)
        self.assertIn("RESULT: FW COREMARK COMPLETE PASS", TB)
        self.assertIn("REPRO_FW_COREMARK_ITERATIONS", RUN_PS1)
        self.assertIn("REPRO_FW_CHECK_COREMARK_COMPLETION", RUN_PS1)
        self.assertIn("Get-MapWordIndex", RUN_PS1)
        self.assertIn("seed4_volatile", RUN_PS1)
        self.assertIn("g_coremark_runs", RUN_PS1)
        self.assertIn("g_coremark_busy", RUN_PS1)
        self.assertIn("$defaultButtonValue = if ($demoImageEnabled) { '3' } else { '0' }", RUN_PS1)

    def test_coremark_build_is_o2_but_common_rtos_build_is_os(self):
        common = re.search(r"COMMON_FLAGS\s*:=([\s\S]*?)\n\n", MAKEFILE)
        coremark = re.search(r"COREMARK_CFLAGS\s*:=([^\n]+)", MAKEFILE)
        self.assertIsNotNone(common)
        self.assertIsNotNone(coremark)
        self.assertNotIn("-Os", common.group(1))
        self.assertIn("-Os", MAKEFILE[MAKEFILE.index("CFLAGS :="):MAKEFILE.index("ASFLAGS :=")])
        self.assertIn("-O2", coremark.group(1))
        self.assertIn('-O2 -march=rv32im_zicsr_zifencei -mabi=ilp32', PORTME)

    def test_runtime_stats_use_atomic_mcycle_snapshot(self):
        self.assertTrue(MONITOR_C_PATH.exists())
        self.assertTrue(MONITOR_H_PATH.exists())
        self.assertIn("configGENERATE_RUN_TIME_STATS              1", FREERTOS_CONFIG)
        self.assertIn("configUSE_TRACE_FACILITY                   1", FREERTOS_CONFIG)
        self.assertIn("configUSE_STATS_FORMATTING_FUNCTIONS       0", FREERTOS_CONFIG)
        self.assertIn("portCONFIGURE_TIMER_FOR_RUN_TIME_STATS", FREERTOS_CONFIG)
        self.assertIn("portGET_RUN_TIME_COUNTER_VALUE", FREERTOS_CONFIG)
        self.assertIn("0xB00", MONITOR_C)
        self.assertIn("0xB80", MONITOR_C)
        self.assertRegex(MONITOR_C, r"high_before[\s\S]*low[\s\S]*high_after")
        self.assertIn(">> 10", MONITOR_C)

    def test_monitor_uses_bounded_official_task_snapshots(self):
        self.assertIn("RTOS_MONITOR_MAX_TASKS 8", MONITOR_H)
        self.assertIn("uxTaskGetSystemState", MONITOR_C)
        self.assertIn("TaskStatus_t", MONITOR_C)
        self.assertNotIn("usStackHighWaterMark", MONITOR_C)
        self.assertNotIn("pvPortMalloc", MONITOR_C)
        self.assertNotIn("vTaskList", MONITOR_C)
        self.assertNotIn("vTaskGetRunTimeStats", MONITOR_C)

    def test_shell_exposes_top_and_showcase_controls(self):
        for command in ('"showcase"', '"top"', '"top once"'):
            self.assertIn(command, MAIN)
        self.assertIn("keys: c CoreMark | q quit", MONITOR_C)
        for shortcut in ("case 'c':", "case 'q':"):
            self.assertIn(shortcut, MONITOR_C)
        self.assertIn("FreeRTOS TOP", MONITOR_C)
        self.assertIn("tskKERNEL_VERSION_NUMBER", MONITOR_C)

    def test_dynamic_top_is_slow_plain_cpu_snapshot(self):
        self.assertIn("pdMS_TO_TICKS(3000UL)", MONITOR_C)
        self.assertNotIn('console_puts("\\033[2J\\033[H")', MONITOR_C)
        self.assertIn('console_puts("TASK       STATE   CPU%\\n")', MONITOR_C)
        self.assertNotIn('console_puts("%  heap: ")', MONITOR_C)
        self.assertNotIn('console_puts(" KiB\\nLED: ")', MONITOR_C)
        self.assertNotIn('console_puts("     ")', MONITOR_C)

        enter_body = MONITOR_C[
            MONITOR_C.index("void rtos_monitor_enter_top"):
            MONITOR_C.index("void rtos_monitor_leave_top")
        ]
        self.assertIn("capture_baseline", enter_body)
        self.assertNotIn("print_top_frame", enter_body)

    def test_led_shell_command_is_single_start_command(self):
        self.assertIn('streq(cmd, "led")', MAIN)
        self.assertIn('console_puts("  led\\n")', MAIN)
        self.assertNotIn('console_puts("  led 0|1|both\\n")', MAIN)
        self.assertNotIn('starts_with(cmd, "led ")', MAIN)

    def test_coremark_coordination_contract(self):
        request_body = MAIN[MAIN.index("void demo_request_coremark"):MAIN.index("void demo_print_stats")]
        self.assertNotIn("rtos_monitor_set_load", request_body)
        self.assertIn("monitored CoreMark; top overhead is included", MONITOR_C)

    def test_showcase_has_no_synthetic_load_feature(self):
        self.assertNotIn('console_puts("  load ', MAIN)
        self.assertNotIn('starts_with(cmd, "load ")', MAIN)
        self.assertNotIn('xTaskCreate(rtos_monitor_load_task', MAIN)
        self.assertNotIn('"load"', MONITOR_C)
        self.assertNotIn("rtos_monitor_set_load", MONITOR_C)
        self.assertNotIn("rtos_monitor_load_task", MONITOR_H)
        self.assertNotIn("g_load_task_handle", DEMO_H)
        for shortcut in ("case '0':", "case '2':", "case '5':", "case '7':", "case '9':"):
            self.assertNotIn(shortcut, MONITOR_C)

    def test_top_lists_only_led_and_coremark_demo_tasks(self):
        self.assertIn("monitor_task_name", MONITOR_C)
        self.assertIn('streq_name(name, "led")', MONITOR_C)
        self.assertIn('streq_name(name, "coremark")', MONITOR_C)

    def test_coremark_stops_dynamic_top_before_result_output(self):
        stop_body = PORTME_C[PORTME_C.index("void stop_time"):PORTME_C.index("CORE_TICKS")]
        callback_pos = stop_body.index("rtos_monitor_coremark_measurement_stopped")
        cpi_pos = stop_body.index("RV32 Micro-Architecture CPI Breakdown")
        self.assertLess(callback_pos, cpi_pos)
        self.assertIn("rtos_monitor_coremark_completed", MAIN)

    def test_makefile_builds_monitor_without_extra_kernel_components(self):
        self.assertIn("$(BUILD_DIR)/rtos_monitor.o", MAKEFILE)
        self.assertIn("rtos_monitor.c", MAKEFILE)
        self.assertNotIn("timers.o", MAKEFILE)
        self.assertNotIn("event_groups.o", MAKEFILE)
        self.assertNotIn("stream_buffer.o", MAKEFILE)


if __name__ == "__main__":
    unittest.main()
