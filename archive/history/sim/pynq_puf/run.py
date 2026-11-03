"""Icarus cosimulation of the PYNQ + PUF v1 overlay path (see tb_pynq_puf.v).

Run from the repository root:  python -X utf8 sim/pynq_puf/run.py
The firmware is taken from the same COE that build.tcl puts into the bitstream.
Two cases:
  normal - must print TB_PYNQ_PUF: PASS and exit 0;
  mutant - same TB with KEY_USE_PUF=0 (DNA-only fallback forced); the firmware must
           report "FAIL dna-only fallback" and the TB must exit non-zero.
Exit code 0 only if both cases behave as required.
"""
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[2]
out = root / 'build/local/pynq_puf/sim'
out.mkdir(parents=True, exist_ok=True)
coe = root / ('board/vivado_zynq7000_xc7z020_ascon/riscv_vivado_project/'
              'riscv_vivado_project.srcs/sources_1/imports/bin_file/ascon_keys.coe')
text = coe.read_text()
words = [w for w in re.split(r'[,;\s]+', text.split('memory_initialization_vector=')[1]) if w]
hexfile = out / 'keys_from_coe.hex'
hexfile.write_text(''.join(w.lower() + '\n' for w in words))

tb = root / 'sim/pynq_puf/tb_pynq_puf.v'
anchor = 'defparam u_top.u_soc_top.KEY_WINDOW = 256;'
assert anchor in tb.read_text()
mutant_tb = out / 'tb_mutant_no_puf.v'
mutant_tb.write_text(tb.read_text().replace(anchor, anchor + ' defparam u_top.u_soc_top.KEY_USE_PUF = 0;'))

rtl = sorted(str(p) for p in (root / 'src/rtl').glob('*.v') if p.name != 'top_pl_bram.v')
rtl += sorted(str(p) for p in (root / 'src/rtl/ascon').glob('*.v') if not p.name.endswith('_tb.v'))
rtl += sorted(str(p) for p in (root / 'src/rtl/keys').glob('*.v'))
rtl += [str(root / p) for p in ('src/rtl/pynq/pynq_ctl.v', 'src/rtl/pynq/pynq_mbox.v',
                                'sim/ascon/axi_slave_bram.v', 'sim/keys/DNA_PORT_sim.v',
                                'sim/keys/BUFG_sim.v', 'sim/keys/LUT_sim.v')]


def run_case(name, tb_file):
    vvp = out / (name + '.vvp')
    vvp.unlink(missing_ok=True)  # never run a stale binary after a failed compile
    steps = []
    cmds = [['iverilog', '-g2012', '-I', str(root / 'src/rtl'), '-I', str(root / 'src/rtl/ascon'),
             '-s', 'tb_pynq_puf', '-o', str(vvp)] + rtl + [str(tb_file)],
            ['vvp', '-n', str(vvp), '+HEX=' + str(hexfile)]]
    for i, cmd in enumerate(cmds):
        log = out / ('%s_step%d.log' % (name, i))
        with log.open('wb') as f:
            p = subprocess.run(cmd, cwd=root, stdout=f, stderr=subprocess.STDOUT, timeout=3600)
        body = log.read_text(errors='replace')
        steps.append({'command': cmd, 'exit_code': p.returncode, 'log': log.relative_to(root).as_posix()})
        print('==== %s step %d exit %d\n%s' % (name, i, p.returncode, body[-2500:]), flush=True)
        if i == 0 and (p.returncode or 'error' in body.lower() or not vvp.exists()):
            return steps, None
    return steps, (out / ('%s_step1.log' % name)).read_text(errors='replace')


normal_steps, normal_log = run_case('normal', tb)
normal_ok = (normal_log is not None and normal_steps[-1]['exit_code'] == 0
             and 'TB_PYNQ_PUF: PASS' in normal_log)
mutant_steps, mutant_log = run_case('mutant_no_puf', mutant_tb)
mutant_ok = (mutant_log is not None and mutant_steps[-1]['exit_code'] != 0
             and 'FAIL dna-only fallback' in mutant_log and 'TB_PYNQ_PUF: FAIL' in mutant_log)
code = 0 if normal_ok and mutant_ok else 1
summary = {'result': 'PASS' if code == 0 else 'FAIL', 'exit_code': code,
           'normal_pass': normal_ok, 'mutant_detected': mutant_ok,
           'coe_sha256': hashlib.sha256(coe.read_bytes()).hexdigest(),
           'simulation_only': 'behavioral RO/DNA/BUFG and AXI BRAM; KEY_WINDOW=256 via defparam',
           'normal': normal_steps, 'mutant_no_puf': mutant_steps}
(out / 'summary.json').write_text(json.dumps(summary, indent=2), encoding='utf-8')
print(summary['result'], 'normal_pass=%s mutant_detected=%s' % (normal_ok, mutant_ok))
sys.exit(code)
