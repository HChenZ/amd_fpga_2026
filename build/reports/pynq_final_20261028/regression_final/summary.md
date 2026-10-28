# Navigator preboard: PASS

HEAD: `0f5d49c38597947dace3f1c99220deca8ef48e14`; branch `feat/pynq-final-integration`
Mode: regression; elapsed: 400.168 s; FPGA cycles: NOT_MEASURED

| Test | Status | Exit | Seconds | Evidence |
|---|---|---|---|---|
| local_tools | PASS | 0 | 0.238 | local_tools.log |
| host_api | PASS | 0 | 4.09 | host_api.log |
| mailbox | PASS | 0 | 0.308 | mailbox.log |
| navigator_adapter | PASS | 0 | 0.206 | navigator_adapter.log |
| firmware | PASS | 0 | 5.731 | firmware.log |
| host_kat | PASS | 0 | 3.915 | host_kat.log |
| cpu_sw | PASS | 0 | 173.842 | cpu_sw.log |
| cpu_hw | PASS | 0 | 105.517 | cpu_hw.log |
| cpu_ise | PASS | 0 | 86.831 | cpu_ise.log |
| cpu_image_match | PASS | 0 | 0.165 | cpu_image_match.log |
| mailbox_kat | PASS | 0 | 1.695 | mailbox_kat.log |
| dcache_compile | PASS | 0 | 0.071 | dcache_compile.log |
| dcache | PASS | 0 | 0.026 | dcache.log |
| cpu_interrupt | PASS | 0 | 12.152 | cpu_interrupt.log |
| fpga_uart_overlay | NOT_RUN | None |  | no board/overlay; hardware cycles NOT_MEASURED |
| protected_evidence | PASS | None |  | snapshot hash guard |

Tool commands, versions, source hashes and exact test commands are in summary.json.
PASS denotes only the stated host/build/simulation scope. BLOCKED is never silently successful.
