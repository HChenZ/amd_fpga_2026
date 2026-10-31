# Intermediate CPU build — superseded, not the final candidate

This first build met 100MHz setup/hold (+0.144ns/+0.017ns) and reported zero
error/critical **DRC violations**, but its PS DDR/FIXED_IO interfaces were internal.
The implementation log contains `Netlist 29-160` critical warnings because PS pin
constraints were applied to internal pins instead of top ports. A zero DRC count
did not cover that integration failure.

The parent identified this issue on the sibling design. It was independently
confirmed in this directory's `run_logs/impl_1.log`; the CPU setup now explicitly
exports both PS interfaces. This bit/HWH and all reports remain preserved as
intermediate evidence. Do not deploy these files as the final CPU DMA candidate.

`candidate_audit.json` is the original limited width/address/firmware audit; its
PASS does not qualify PS pin export. The final audit now requires both external
interfaces, and collect.tcl rejects Netlist29-160 warnings before promotion.
