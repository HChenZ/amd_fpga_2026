"""Publish the gated pynq_puf3 candidate (three-mode service + PUF v1).

Run from the repository root after:
  python -X utf8 src/firmware/pynq_svc_puf/build.py
  python -X utf8 sim/pynq_puf3/run.py
  vivado -mode batch -source board/vivado_zynq7000_xc7z020_pynq_puf3/build.tcl -notrace
  vivado -mode batch -source board/vivado_zynq7000_xc7z020_pynq_puf3/ro_corner_sta.tcl -tclargs <final dcp> build/local/pynq_puf3/ro_sta
Refuses to publish unless the Vivado gate, the cosimulation (normal + autolock mutant) and
the firmware image hashes agree. Writes board/vivado_zynq7000_xc7z020_pynq_puf3/candidate/.
"""
from pathlib import Path
import hashlib
import json
import re
import shutil
import subprocess

root = Path(__file__).resolve().parents[2]
board = root / 'board/vivado_zynq7000_xc7z020_pynq_puf3'
work = root / 'build/local/pynq_puf3/vivado'
rep = work / 'reports'
cand = board / 'candidate'
fw = root / 'build/local/pynq_svc_puf'


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


gate = (rep / 'gate.txt').read_text()
g = dict(kv.split('=', 1) for kv in gate.split())
assert float(g['wns']) >= 0 and float(g['whs']) >= 0, 'timing gate'
assert g['drc_error_or_critical'] == '0' and g['netlist_29_160'] == '0', 'DRC / PS pin gate'
assert g['ro_luts'] == '1280' and g['ro_luts_assigned_pblock'] == '1280', 'RO structure gate'
assert not re.search(r'\|\s*(?:Error|Critical Warning)\s*\|', (rep / 'drc.rpt').read_text()), 'DRC report'
sim = json.loads((root / 'build/local/pynq_puf3/sim/summary.json').read_text())
assert sim['result'] == 'PASS' and sim['normal_pass'] and sim['mutant_autolock_detected'], 'cosimulation gate'
assert sim['firmware_bin_sha256'] == sha(fw / 'pynq_svc_puf.bin'), 'cosimulation used a different firmware'
assert sim['variant_sha256'] == {p.name: sha(p) for p in sorted((board / 'rtl').glob('*.v'))}, 'variant RTL changed after cosim'
context = (work / 'context.txt').read_text()
assert 'pynq_svc_puf.coe' in context, 'bitstream was not built with pynq_svc_puf.coe'
# The BRAM init that Vivado consumed must be the same image as the cosimulated binary.
built_coe = fw / 'pynq_svc_puf.coe'
coe_words = [w.lower() for w in re.split(r'[,;\s]+', built_coe.read_text().split('memory_initialization_vector=')[1]) if w]
mifs = sorted(work.rglob('blk_mem_gen_0.mif'))
assert mifs, 'generated blk_mem_gen_0.mif not found'
for mif in mifs:
    bits = [l.strip() for l in mif.read_text().splitlines() if l.strip()]
    assert ['%08x' % int(b, 2) for b in bits] == coe_words, 'BRAM init %s != pynq_svc_puf.coe' % mif
mif_check = '%d generated .mif file(s) equal pynq_svc_puf.coe word for word (%d words)' % (len(mifs), len(coe_words))

if cand.exists():
    shutil.rmtree(cand)
(cand / 'reports').mkdir(parents=True)
shutil.copy2(work / 'pynq_puf3.bit', cand / 'pynq_puf3.bit')
shutil.copy2(work / 'pynq_puf3.hwh', cand / 'pynq_puf3.hwh')
shutil.copy2(built_coe, cand / 'pynq_svc_puf.coe')
shutil.copy2(fw / 'pynq_svc_puf.bin', cand / 'pynq_svc_puf.bin')
shutil.copy2(fw / 'pynq_svc_puf.elf', cand / 'pynq_svc_puf.elf')
ct = [l for l in (rep / 'check_timing.rpt').read_text().splitlines() if l.strip().startswith('There ')]
(cand / 'reports/check_timing_counts.txt').write_text('\n'.join(ct) + '\n', encoding='utf-8')
for name in ('gate.txt', 'timing_summary.rpt', 'drc.rpt', 'methodology.rpt', 'utilization.rpt',
             'pblock_utilization.rpt', 'clock_interaction.rpt', 'route_status.rpt'):
    shutil.copy2(rep / name, cand / 'reports' / name)
shutil.copy2(work / 'context.txt', cand / 'reports/context.txt')
# RO-domain corner analysis (ro_corner_sta.tcl, analysis only) must belong to the checkpoint of this bit.
ro_sta = root / 'build/local/pynq_puf3/ro_sta/ro_corner_sta.txt'
first = ro_sta.read_text().splitlines()[0]
run_dir = work / 'pynq_puf3.runs' / g['run']
final_dcp = run_dir / 'pynq_puf3_wrapper_postroute_physopt.dcp'
if not final_dcp.exists():
    final_dcp = run_dir / 'pynq_puf3_wrapper_routed.dcp'
assert first.startswith('dcp=') and Path(first[4:].split(' tool=')[0]).resolve() == final_dcp.resolve(), \
    'ro_corner_sta.txt was produced from a different checkpoint'
shutil.copy2(ro_sta, cand / 'reports/ro_corner_sta.txt')
explore = rep / 'explore_impl.txt'
timing_history = explore.read_text().strip().splitlines() if explore.exists() else []
if explore.exists():
    shutil.copy2(explore, cand / 'reports/explore_impl.txt')
shutil.copy2(fw / 'build.json', cand / 'reports/firmware_build.json')
shutil.copy2(root / 'build/local/pynq_puf3/sim/summary.json', cand / 'reports/cosim_summary.json')
shutil.copy2(root / 'build/local/pynq_puf3/sim/normal_step1.log', cand / 'reports/cosim_normal.log')
shutil.copy2(root / 'build/local/pynq_puf3/sim/mutant_autolock_step1.log', cand / 'reports/cosim_mutant_autolock.log')

artifacts = {p.name: {'bytes': p.stat().st_size, 'sha256': sha(p)}
             for p in sorted(cand.iterdir()) if p.suffix in ('.bit', '.hwh', '.coe', '.bin', '.elf')}
sources = (list((root / 'src/rtl').glob('*.v')) + list((root / 'src/rtl/ascon').glob('*.v'))
           + list((root / 'src/rtl/ascon').glob('*.vh')) + list((root / 'src/rtl/keys').glob('*.v'))
           + list((root / 'src/rtl/pynq').glob('*.v')) + list((board / 'rtl').glob('*.v'))
           + list((root / 'src/firmware/pynq_svc_puf').glob('*.*')) + list((root / 'src/firmware/pynq_svc').glob('*.*'))
           + [board / 'build.tcl', board / 'explore_impl.tcl', board / 'finalize_run.tcl', board / 'ro_corner_sta.tcl', board / 'puf_opt_pre.tcl', board / 'pynq_puf3_timing.xdc',
              root / 'build/keys_ro_allow_loops.tcl', root / 'src/pynq/pynq_puf3.py'])
excluded = ['src/rtl/soc_top.v', 'src/rtl/keys/key_mmio.v', 'src/rtl/top_pl_bram.v']
git = lambda *a: subprocess.check_output(['git', *a], cwd=root, text=True).strip()
manifest = {
    'schema': 'pynq_puf3_candidate',
    'source_commit': git('rev-parse', 'HEAD'),
    'source_dirty': bool(git('status', '--porcelain')),
    'source_sha256': {p.relative_to(root).as_posix(): sha(p) for p in sorted(set(sources)) if p.is_file()},
    'excluded_from_build': excluded,
    'part': 'xc7z020clg400-1', 'top': 'pynq_puf3_wrapper', 'vivado': '2025.2',
    'strategy': 'Vivado Synthesis Defaults + ' + g.get('strategy', 'unknown'),
    'source_set': 'src/rtl (+ascon, keys, pynq) with variant rtl/soc_top.v and rtl/key_mmio.v '
                  '(no automatic hardware-key latch; HWKEY via key CTRL[3]/[4], reset off)',
    'firmware': 'pynq_svc_puf (pynq_svc three-mode service + Y01P/Y01K PUF frames), id pynq-svc-puf3',
    'control_id': '0x33465150', 'control_version': 1, 'fclk0_mhz': 100,
    'timing_history': timing_history,
    'bram_init_check': mif_check,
    'gate': g, 'cosimulation': {k: sim[k] for k in ('result', 'steps', 'normal_pass', 'mutant_autolock_detected',
                                                   'firmware_bin_sha256', 'variant_sha256', 'simulation_only')},
    'constraints': 'PS7 generated + pynq_puf3_timing.xdc (ro_clk = FCLK0/4 generated clock, implementation only, '
                   'no exception); RO oscillator clocks undeclared (analysis in reports/ro_corner_sta.txt)',
    'signoff': {'clk_fpga_0 (CPU/Ascon/bus, 100 MHz)': 'signed off by gate wns/whs',
                'ro_clk (PUF sampling control, 25 MHz) and clk<->ro_clk': 'signed off (declared generated clock)',
                'RO counters (256 x 20 bit)': 'NOT signed off: ro_corner_sta.txt shows negative counter setup/hold; '
                                              'needs a PUF RTL change'},
    'not_signed_off': 'RO oscillator counter domain (see check_timing_counts.txt and ro_corner_sta.txt)',
    'pblock_note': 'pb_ro_puf became soft; only ro_luts_placed_in_pblock_region of the 1280 ring LUTs are '
                   'physically inside it (assignment is gated, placement is reported)',
    'hardware_validation': 'NOT_RUN',
    'artifacts': artifacts,
}
(cand / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
lines = [info['sha256'] + '  ' + name for name, info in artifacts.items()]
lines.append(sha(cand / 'manifest.json') + '  manifest.json')
(cand / 'sha256sums.txt').write_bytes(('\n'.join(lines) + '\n').encode('ascii'))
print(json.dumps({'gate': g, 'artifacts': artifacts}, indent=2))
print('PYNQ_PUF3_PACKAGE_PASS', cand)
