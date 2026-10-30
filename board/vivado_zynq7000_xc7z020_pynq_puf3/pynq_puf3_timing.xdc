# PUF v1 sampling-control clock: soc_top divides FCLK0 by 4 in fabric
# (ro_clk_div_reg[1] -> BUFG). Declaring it lets STA time the ro_clk FSM/vote logic and
# the clk <-> ro_clk toggle handshakes (now synchronous, related clocks), and lets the
# router fix their hold. No measurement or exception is needed for this domain.
# The 256 RO oscillator domains remain undeclared: see ro_corner_sta.tcl / readme.
# Implementation-only (USED_IN_SYNTHESIS false): the SoC is a BD module synthesized OOC.
create_generated_clock -name ro_clk -divide_by 4 \
    -source [get_pins -hier -filter {NAME =~ "*u_soc_top/ro_clk_div_reg[1]/C"}] \
    [get_pins -hier -filter {NAME =~ "*u_soc_top/ro_clk_div_reg[1]/Q"}]
