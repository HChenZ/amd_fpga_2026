# Standalone PYNQ overlay workflow Skill

This directory is the complete installable Skill, independent of the PUF3 project runtime.
Copy it into the Skill directory supported by your agent; keep SKILL.md, scripts, references and examples together.

```sh
python -m pytest tests -q
python scripts/pynq_skill_cli.py --help
```

The tool code uses the Python standard library; tests need pytest. Optional repository-artifact tests skip
when the separate FPGA project is absent. A standalone run is not a new board or L2/L3 verification.
Existing L3 Ascon used the historical v1 overlay, not PUF3. The controlled experiments and old results are
isolated under archive/history and archive/evidence in the full repository, not required for installation.

The package includes the project LICENSE. Preserve file-level third-party notices. No real key or private credential
is needed. The Skill stays parameterized; it is not hardcoded to PUF3 and is not the board firmware.
