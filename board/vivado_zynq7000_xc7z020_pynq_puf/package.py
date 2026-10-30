"""Publish the gated PYNQ + PUF v1 candidate; run from repository root after build.tcl and sim/pynq_puf/run.py."""
from pathlib import Path
import hashlib, json, re, shutil, subprocess

root = Path(__file__).resolve().parents[2]
board = root / 'board/vivado_zynq7000_xc7z020_pynq_puf'
work = root / 'build/local/pynq_puf/vivado'
rep = work / 'reports'
cand = board / 'candidate'
coe = root / ('board/vivado_zynq7000_xc7z020_ascon/riscv_vivado_project/'
              'riscv_vivado_project.srcs/sources_1/imports/bin_file/ascon_keys.coe')


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


gate = (rep / 'gate.txt').read_text()
g = dict(kv.split('=') for kv in gate.split())
assert float(g['wns']) >= 0 and float(g['whs']) >= 0, 'timing gate'
assert g['drc_error_or_critical'] == '0' and g['netlist_29_160'] == '0', 'DRC / PS pin gate'
assert g['ro_luts'] == '1280' and g['ro_luts_assigned_pblock'] == '1280', 'RO structure gate'
assert not re.search(r'\|\s*(?:Error|Critical Warning)\s*\|', (rep / 'drc.rpt').read_text()), 'DRC report'
sim = json.loads((root / 'build/local/pynq_puf/sim/summary.json').read_text())
assert sim['result'] == 'PASS' and sim['normal_pass'] and sim['mutant_detected'], 'cosimulation gate'
assert sim['coe_sha256'] == sha(coe), 'cosimulation used a different COE'

cand.mkdir(exist_ok=True)
(cand / 'reports').mkdir(exist_ok=True)
shutil.copy2(work / 'pynq_puf.bit', cand / 'pynq_puf.bit')
shutil.copy2(work / 'pynq_puf.hwh', cand / 'pynq_puf.hwh')
shutil.copy2(coe, cand / 'ascon_keys.coe')
# check_timing -verbose lists every pin (~3.6 MB); keep only its count lines in the candidate.
ct = [l for l in (rep / 'check_timing.rpt').read_text().splitlines() if l.strip().startswith('There ')]
(cand / 'reports').mkdir(parents=True, exist_ok=True)
(cand / 'reports/check_timing_counts.txt').write_text('\n'.join(ct) + '\n', encoding='utf-8')
(cand / 'reports/check_timing.rpt').unlink(missing_ok=True)
for name in ('gate.txt', 'timing_summary.rpt', 'drc.rpt', 'methodology.rpt',
             'utilization.rpt', 'pblock_utilization.rpt', 'clock_interaction.rpt', 'route_status.rpt'):
    shutil.copy2(rep / name, cand / 'reports' / name)
shutil.copy2(work / 'context.txt', cand / 'reports/context.txt')
# RO-domain corner analysis must belong to the routed design that produced this bit.
ro_sta = root / 'build/local/pynq_puf/ro_sta/ro_corner_sta.txt'
first = ro_sta.read_text().splitlines()[0]
run_dir = work / 'pynq_puf.runs' / g['run']
final_dcp = run_dir / 'pynq_puf_wrapper_postroute_physopt.dcp'
if not final_dcp.exists():
    final_dcp = run_dir / 'pynq_puf_wrapper_routed.dcp'
expected_dcp = final_dcp.resolve().as_posix()
assert first.startswith('dcp=') and Path(first[4:].split(' tool=')[0]).resolve().as_posix() == expected_dcp, \
    'ro_corner_sta.txt was produced from a different checkpoint'
shutil.copy2(ro_sta, cand / 'reports/ro_corner_sta.txt')
shutil.copy2(root / 'build/local/pynq_puf/sim/normal_step1.log', cand / 'reports/cosim_normal.log')
shutil.copy2(root / 'build/local/pynq_puf/sim/mutant_no_puf_step1.log', cand / 'reports/cosim_mutant_no_puf.log')
shutil.copy2(root / 'build/local/pynq_puf/vivado/reports/explore_impl.txt', cand / 'reports/explore_impl.txt')

artifacts = {p.name: {'bytes': p.stat().st_size, 'sha256': sha(p)}
             for p in sorted(cand.iterdir()) if p.suffix in ('.bit', '.hwh', '.coe')}
sources = (list((root / 'src/rtl').glob('*.v')) + list((root / 'src/rtl/ascon').glob('*.v'))
           + list((root / 'src/rtl/ascon').glob('*.vh')) + list((root / 'src/rtl/keys').glob('*.v'))
           + list((root / 'src/rtl/pynq').glob('*.v')) + list((root / 'src/firmware/keys_rv32').glob('*.*'))
           + [board / 'build.tcl', board / 'puf_opt_pre.tcl', board / 'finalize_run.tcl',
              board / 'pynq_puf_timing.xdc', board / 'ro_corner_sta.tcl',
              root / 'build/keys_ro_allow_loops.tcl'])
git = lambda *a: subprocess.check_output(['git', *a], cwd=root, text=True).strip()
manifest = {
    'schema': 'pynq_puf_v1_candidate',
    'source_commit': git('rev-parse', 'HEAD'),
    'source_dirty': bool(git('status', '--porcelain')),
    'source_sha256': {p.relative_to(root).as_posix(): sha(p) for p in sorted(sources) if p.is_file()},
    'part': 'xc7z020clg400-1', 'top': 'pynq_puf_wrapper', 'vivado': '2025.2',
    'strategy': 'Vivado Synthesis Defaults + ' + g.get('strategy', 'unknown'),
    'timing_history': 'see reports/explore_impl.txt (every strategy tried, same netlist and constraints; '
                      'only implementation strategy differs)',
    'constraints': 'PS7 generated + pynq_puf_timing.xdc (ro_clk = FCLK0/4 generated clock); '
                   'RO oscillator clocks undeclared (analysis in reports/ro_corner_sta.txt)',
    'source_set': 'src/rtl soc_top.v + ascon/ascon_mmio.v with PUF v1 (src/rtl/keys); not rtl_p0',
    'firmware': 'keys_rv32 v3 (commit a4ae769), same COE as the 2026-10-27 JTAG board PASS',
    'control_id': '0x31554650', 'control_version': 1, 'fclk0_mhz': 100,
    'gate': g, 'cosimulation': sim,
    'not_signed_off': 'RO sampling domain has unclocked/unconstrained endpoints (see check_timing_counts.txt)',
    'pblock_note': 'pb_ro_puf became soft (Place 30-640, CARRY4 demand 1687 > 1470 sites); '
                   'only ro_luts_placed_in_pblock_region of the 1280 ring LUTs are physically inside it. '
                   'Corrected 2026-10-30: the first package counted pblock assignment as placement.',
    'hardware_validation': 'NOT_RUN',
    'artifacts': artifacts,
}
(cand / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
lines = [info['sha256'] + '  ' + name for name, info in artifacts.items()]
lines.append(sha(cand / 'manifest.json') + '  manifest.json')
(cand / 'sha256sums.txt').write_bytes(('\n'.join(lines) + '\n').encode('ascii'))
print(json.dumps({'gate': g, 'artifacts': artifacts}, indent=2))
