# Navigator preboard: FAIL

HEAD: `0f5d49c38597947dace3f1c99220deca8ef48e14`; branch `feat/pynq-final-integration`
Mode: regression; elapsed: 626.419 s; FPGA cycles: NOT_MEASURED

| Test | Status | Exit | Seconds | Evidence |
|---|---|---|---|---|
| local_tools | PASS | 0 | 0.278 | local_tools.log |
| host_api | PASS | 0 | 4.291 | host_api.log |
| mailbox | PASS | 0 | 0.286 | mailbox.log |
| navigator_adapter | PASS | 0 | 0.219 | navigator_adapter.log |
| firmware | FAIL | 2 | 0.099 | firmware.log |
| host_kat | PASS | 0 | 4.096 | host_kat.log |
| cpu_sw | PASS | 0 | 237.707 | cpu_sw.log |
| cpu_hw | PASS | 0 | 214.635 | cpu_hw.log |
| cpu_ise | PASS | 0 | 157.233 | cpu_ise.log |
| cpu_image_match | BLOCKED | None |  | firmware or CPU regression did not pass |
| mailbox_kat | PASS | 0 | 1.71 | mailbox_kat.log |
| dcache_compile | PASS | 0 | 0.07 | dcache_compile.log |
| dcache | PASS | 0 | 0.029 | dcache.log |
| cpu_interrupt | FAIL | 2 | 0.125 | cpu_interrupt.log |
| fpga_uart_overlay | NOT_RUN | None |  | no board/overlay; hardware cycles NOT_MEASURED |
| protected_evidence | PASS | None |  | snapshot hash guard |

Tool commands, versions, source hashes and exact test commands are in summary.json.
PASS denotes only the stated host/build/simulation scope. BLOCKED is never silently successful.
