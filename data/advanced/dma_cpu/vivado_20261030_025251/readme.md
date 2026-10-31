# Fixed-PS-port 100MHz timing failure

Vivado 2025.2, XC7Z020CLG400-1, `cpu_dma_wrapper`, actual 10.000ns clock.
PS DDR/FIXED_IO are exported; Netlist29-160 count is zero and error/critical DRC
count is zero. Nevertheless setup fails: WNS -0.046ns, TNS -0.450ns, 12 endpoints;
hold is +0.020ns. These bit/HWH/DCP files are preserved as **failed**, not released.

Worst path: existing CPU `id_ex_u/rs1_o_reg[1]` through address addition and
distributed cache tag lookup into `u_dcache/captured_addr_reg[0]/CE`.
Delay is 9.627ns: 2.694ns logic, 6.933ns routing (72.015%), nine levels. The actual
cache index address[4] driver has 367 leaf loads. Source inspection confirms the
tag lookup/miss enable and captured-address behavior in unchanged `src/rtl/dcache.v`.

A bounded post-route experiment is preserved in
`../physopt_20261030_030502/`: explicit forced replication was rejected by Vivado
4-265 as unsupported post-route, before a mutation. The supported
`phys_opt_design -directive AggressiveExplore` completed but added/removed zero
cells and left WNS/TNS unchanged. No clock/false-path/multicycle constraint was
altered and no optimization success is claimed.

The next experiment is an independent 80MHz PS FCLK project. Its requested,
actual calculated frequency, clock-pin metadata and post-route clock period must
agree. This is a real frequency variant, not a claimed Fmax or relaxed STA-only
constraint. Original 100MHz failure evidence remains available here.
