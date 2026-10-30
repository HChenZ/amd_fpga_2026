# G7 conformance review

## Functional result

The Skill-guided `counter8` and the no-Skill `counter8` both pass the same frozen
testbench for 1,046 cycles with seed `20261030`.

## Skill constraints

| Check | Skill group | No-Skill group |
|---|---|---|
| Single synchronous process | PASS | PASS |
| Only `count[7:0]` is state | PASS | PASS |
| No extra pipeline/state | PASS | PASS |
| `rst_n > clear > load > enable > hold` | PASS | PASS |
| Synchronous active-low reset | PASS | PASS |
| Syntactically compilable | PASS | PASS |
| Independent functional test | PASS | PASS |

The Skill group writes an explicit final `count <= count;`. The no-Skill group
relies on the implicit sequential hold. The two source texts differ, but the
declared behavior, state count, and simulation result are equivalent. This single
example does not show a measurable improvement in LUT, FF, latency, or code size.

## Mutation sensitivity

Changing the frozen Skill-group output so `load` outranks `clear` caused 353
failures and simulation exit code 1. The first failure was:

```text
tag=214 cycle=33 expected=00 actual=a5
```

After the mutation run, the original generated RTL still matched its frozen hash
and passed the testbench again.

## Evidence boundary

- This is one non-cryptographic counter task.
- The Skill content was explicitly provided; automatic discovery was not tested.
- The A/B result is one pair and is exploratory only.
- Synthesis/resource comparison is `NOT_MEASURED`.
