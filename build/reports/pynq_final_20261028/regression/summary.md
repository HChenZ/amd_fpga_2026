# Navigator preboard: FAIL

HEAD: `0f5d49c38597947dace3f1c99220deca8ef48e14`; branch `feat/pynq-final-integration`
Mode: regression; elapsed: 36.472 s; FPGA cycles: NOT_MEASURED

| Test | Status | Exit | Seconds | Evidence |
|---|---|---|---|---|
| local_tools | PASS | 0 | 0.32 | local_tools.log |
| host_api | PASS | 0 | 4.338 | host_api.log |
| mailbox | PASS | 0 | 0.297 | mailbox.log |
| navigator_adapter | PASS | 0 | 0.222 | navigator_adapter.log |
| firmware | PASS | 0 | 6.343 | firmware.log |
| host_kat | PASS | 0 | 4.686 | host_kat.log |
| cpu_sw | FAIL | 1 | 2.007 | cpu_sw.log |
| cpu_hw | FAIL | 1 | 1.197 | cpu_hw.log |
| cpu_ise | FAIL | 1 | 1.248 | cpu_ise.log |
| cpu_image_match | BLOCKED | None |  | firmware or CPU regression did not pass |
| mailbox_kat | PASS | 0 | 1.461 | mailbox_kat.log |
| dcache_compile | PASS | 0 | 0.069 | dcache_compile.log |
| dcache | PASS | 0 | 0.043 | dcache.log |
| cpu_interrupt | PASS | 0 | 6.046 | cpu_interrupt.log |
| fpga_uart_overlay | NOT_RUN | None |  | no board/overlay; hardware cycles NOT_MEASURED |
| protected_evidence | PASS | None |  | snapshot hash guard |

Tool commands, versions, source hashes and exact test commands are in summary.json.
PASS denotes only the stated host/build/simulation scope. BLOCKED is never silently successful.
