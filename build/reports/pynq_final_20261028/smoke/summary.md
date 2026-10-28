# Navigator preboard: PASS

HEAD: `0f5d49c38597947dace3f1c99220deca8ef48e14`; branch `feat/pynq-final-integration`
Mode: smoke; elapsed: 18.739 s; FPGA cycles: NOT_MEASURED

| Test | Status | Exit | Seconds | Evidence |
|---|---|---|---|---|
| local_tools | PASS | 0 | 0.252 | local_tools.log |
| host_api | PASS | 0 | 5.408 | host_api.log |
| mailbox | PASS | 0 | 0.326 | mailbox.log |
| navigator_adapter | PASS | 0 | 0.216 | navigator_adapter.log |
| firmware | PASS | 0 | 6.258 | firmware.log |
| host_kat | NOT_RUN | None |  | requires --mode regression |
| cpu_sw | NOT_RUN | None |  | requires --mode regression |
| cpu_hw | NOT_RUN | None |  | requires --mode regression |
| cpu_ise | NOT_RUN | None |  | requires --mode regression |
| cpu_image_match | NOT_RUN | None |  | requires --mode regression |
| mailbox_kat | NOT_RUN | None |  | requires --mode regression |
| dcache | NOT_RUN | None |  | requires --mode regression |
| cpu_interrupt | NOT_RUN | None |  | requires --mode regression |
| fpga_uart_overlay | NOT_RUN | None |  | no board/overlay; hardware cycles NOT_MEASURED |
| protected_evidence | PASS | None |  | snapshot hash guard |

Tool commands, versions, source hashes and exact test commands are in summary.json.
PASS denotes only the stated host/build/simulation scope. BLOCKED is never silently successful.
