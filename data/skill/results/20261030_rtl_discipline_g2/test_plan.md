# G2 frozen counter test plan

## DUT contract

- Module: `counter8`
- State: only `count[7:0]`
- All controls and reset are synchronous to the rising edge of `clk`
- Priority: `rst_n=0`, `clear`, `load`, `enable`, hold
- Increment wraps from `ff` to `00`

## Independent oracle

- `tb_counter.v` maintains a separate reference state and computes the next value
  from the declared priority, without instantiating or copying the submitted DUT.
- Stimulus changes on the falling edge and checks one nanosecond after the rising edge.
- Unknown DUT outputs fail immediately.
- A watchdog fails the run after 200 microseconds.

## Coverage

- Synchronous reset under conflicting controls
- Every combination of reset, clear, load, and enable
- Clear versus load
- Load versus enable
- Load data `00`, `a5`, `fd`, and `ff`
- Increment and wrap at `ff`
- Repeated load and repeated enable
- 1,000 deterministic pseudo-random cycles using seed `20261030`

## Mutation gate

After the valid run, mutate a private copy so `load` has higher priority than `clear`.
The frozen testbench must exit nonzero. Restore the original and require a passing rerun.

## Commands

```text
iverilog -g2012 -s tb_counter -o test.vvp generated_counter.v tb_counter.v
vvp test.vvp
```

The compile and simulation exit codes must both be captured. PASS is valid only when
the simulation exits zero and prints `PASS tb_counter`.
