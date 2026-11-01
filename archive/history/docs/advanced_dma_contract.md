# Advanced DMA ABI v2 (implementation contract)

> 2026-11-01 scope: independent CPU-DMA/HW_DIRECT D01/ABI v2, not PUF3 UART Y01.
> Capacities, modes, cycles and deadlines below apply only to those experiments. No protocol defaults are changed.

2026-10-29; owner TBD. Independent experimental variants; original UART v1 release stays unchanged.
All integers little-endian; 32-bit AXI-Stream, contiguous low TKEEP, full TKEEP except last beat,
exactly one TLAST at the complete packet boundary. One request in flight. MAX_AD/MAX_MSG=1024
for HW_DIRECT; CPU SW/ISE initially 32, original HW 16. No silent fallback.

Request: same 48-byte field layout as mailbox v1, but magic `D01Q`, version=2, flags=0.
offset 8 epoch u64, 16 id u64, 24 operation u32 (1 encrypt/2 decrypt), 28 mode u32
(1 SW/2 original HW/3 ISE/4 HW_DIRECT), 32 ad_bytes, 36 data_bytes, 40 output_capacity,
44 tag_bytes (0 encrypt/16 decrypt). Body key16||nonce16||AD||data||decrypt_tag16.
Response magic `D01R`, version=2, 48-byte layout as v1: flags bit0 cycles_valid, bit1 simulated;
epoch/id/op/mode echoed, status offset24, output_bytes offset36, cycles64 offset40.
Status 0 OK,1 AUTH_FAILED,2 LENGTH,3 UNSUPPORTED,4 INTERNAL,5 FRAME,6 SESSION.
Failure always header only, cycles=0 and flags=0, no payload. Encrypt success CT||tag; decrypt PT.
For HW_DIRECT cycles are PL computation cycles (start through authenticated completion), not CPU mcycle.

Epoch is externally configured through control registers and must be nonzero. Requests require exact epoch
and strictly increasing nonzero id. Epoch change/reset aborts active work without a stale result.
Malformed packets fail or latch a fault requiring recovery; unbounded/incomplete input has a finite watchdog.
Packet storage is bounded. Candidate plaintext private until authentication. Invalid read of core result returns zero.

Planned direct engine ports: clk,rst_n,session_epoch[63:0], s_axis_tdata[31:0],s_axis_tkeep[3:0],
s_axis_tvalid,s_axis_tready,s_axis_tlast; m_axis_tdata[31:0],m_axis_tkeep[3:0],m_axis_tvalid,
m_axis_tready,m_axis_tlast; fault. Active-low reset flushes transport and computation.
Control map (shared CPU/direct): ID0=0x32414d44, version4=2, reset8 bit0 hold,
epoch0xc/0x10 writable only in reset, global maxima0x14/0x18, mode mask0x1c bit(mode-1),
status0x20 bit0 idle-ready/bit1 busy/bit2 fault; per-mode message/AD maxima at0x30+8*(mode-1).
Direct fault blocks new input until reset/epoch recovery; stalled output stays stable.
Partial-frame watchdog bounds total reception time, including active incoming beats.
Core result reads have synchronous data AND address-valid qualification; first input LOAD revokes old output.
No transfer buffer is released until DMA quiescence is verified; receive is armed before send.
No board results are implied by this specification.
