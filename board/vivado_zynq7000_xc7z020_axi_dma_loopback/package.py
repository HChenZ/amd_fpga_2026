"""Publish the gated AXI DMA loopback overlay (non-Ascon, for the pynq-overlay-workflow Skill L3 test).

Run from the repository root after build.tcl:
    python -X utf8 board/vivado_zynq7000_xc7z020_axi_dma_loopback/package.py
Checks the gate of THIS implementation run, the hwh structure (simple-mode DMA, GP0 control,
HP0 memory with a 1 GiB aperture, MM2S->S2MM stream loopback incl. TLAST, FCLK0 config) and that
the Skill's own L1 tools accept the artifacts. Writes candidate/{axi_dma_loopback.bit,.hwh,
manifest.json,sha256sums.txt,reports/}.
"""
from pathlib import Path
import hashlib
import json
import re
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parents[2]
board = root / 'board/vivado_zynq7000_xc7z020_axi_dma_loopback'
work = root / 'build/local/axi_dma_loopback/vivado'
rep = work / 'reports'
cand = board / 'candidate'
bit, hwh = work / 'axi_dma_loopback.bit', work / 'axi_dma_loopback.hwh'
sys.path.insert(0, str(root / 'skill/pynq-overlay-workflow/scripts'))
from pynq_skill import artifacts, dma, hwh as skill_hwh  # noqa: E402


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


g = dict(kv.split('=', 1) for kv in (rep / 'gate.txt').read_text().split())
assert float(g['wns']) >= 0 and float(g['whs']) >= 0, 'timing gate'
assert g['drc_error_or_critical'] == '0' and g['netlist_29_160'] == '0' and g['unrouted_or_conflict_nets'] == '0', g
assert not re.search(r'\|\s*(?:Error|Critical Warning)\s*\|', (rep / 'drc.rpt').read_text()), 'DRC report'
dcp = work / 'dma_loop.runs/impl_1' / g['dcp']
# bit/hwh must come from this run: written after the gate in the same Vivado session.
assert bit.stat().st_mtime >= (rep / 'gate.txt').stat().st_mtime >= dcp.stat().st_mtime, 'bit/gate/dcp order'

text = hwh.read_text(encoding='utf-8', errors='replace')


def param(name, scope=text):
    m = re.search(r'NAME="%s" VALUE="([^"]*)"' % name, scope)
    assert m, 'hwh lacks ' + name
    return m.group(1)


dma_mod = re.search(r'<MODULE[^>]*FULLNAME="/axi_dma_0"[^>]*>.*?</MODULE>', text, re.S).group(0)
expect_dma = {'c_include_sg': '0', 'c_include_mm2s': '1', 'c_include_s2mm': '1', 'c_addr_width': '32',
              'c_sg_length_width': '14', 'c_m_axi_mm2s_data_width': '32', 'c_m_axi_s2mm_data_width': '32',
              'c_include_mm2s_dre': '0', 'c_include_s2mm_dre': '0'}
for k, v in expect_dma.items():
    assert param(k, dma_mod) == v, (k, param(k, dma_mod))
ps_mod = re.search(r'<MODULE[^>]*FULLNAME="/ps7"[^>]*>.*?</MODULE>', text, re.S).group(0)
ps_clock = {k: param(k, ps_mod) for k in ('PCW_CRYSTAL_PERIPHERAL_FREQMHZ', 'PCW_IOPLL_CTRL_FBDIV',
                                          'PCW_FCLK0_PERIPHERAL_CLKSRC', 'PCW_FCLK0_PERIPHERAL_DIVISOR0',
                                          'PCW_FCLK0_PERIPHERAL_DIVISOR1', 'PCW_ACT_FPGA0_PERIPHERAL_FREQMHZ',
                                          'PCW_USE_M_AXI_GP0', 'PCW_USE_S_AXI_HP0', 'PCW_UIPARAM_DDR_PARTNO')}
assert (ps_clock['PCW_IOPLL_CTRL_FBDIV'], ps_clock['PCW_FCLK0_PERIPHERAL_DIVISOR0'],
        ps_clock['PCW_FCLK0_PERIPHERAL_DIVISOR1'], ps_clock['PCW_USE_M_AXI_GP0'],
        ps_clock['PCW_USE_S_AXI_HP0']) == ('30', '10', '1', '1', '1'), ps_clock
# Stream loopback: MM2S initiator and S2MM target share one bus; TLAST is wired through it.
assert re.search(r'BUSNAME="axi_dma_0_M_AXIS_MM2S"[^>]*NAME="S_AXIS_S2MM"', text), 'MM2S->S2MM loopback'
assert re.search(r'NAME="s_axis_s2mm_tlast" SIGIS="[^"]*" SIGNAME="axi_dma_0_m_axis_mm2s_tlast"', text), 'TLAST'
for m in ('M_AXI_MM2S', 'M_AXI_S2MM'):
    r = re.search(r'<MEMRANGE[^>]*BASEVALUE="(0x[0-9A-F]+)" [^>]*HIGHVALUE="(0x[0-9A-F]+)"[^>]*'
                  r'MASTERBUSINTERFACE="%s"[^>]*SLAVEBUSINTERFACE="S_AXI_HP0"' % m, text)
    assert r and (r.group(1), r.group(2)) == ('0x00000000', '0x3FFFFFFF'), (m, r and r.groups())

# The Skill's own tools must accept these artifacts (L1 compatibility, no hardware).
info = skill_hwh.parse_hwh(str(hwh))
ip = info['ips']['axi_dma_0']
assert (ip['phys_addr'], ip['addr_range']) == (0x40400000, 0x10000), ip
cfg = dma.config_from_hwh(ip['parameters'])
assert cfg['max_transfer'] == 16383 and cfg['align'] == {dma.MM2S: 4, dma.S2MM: 4}, cfg

if cand.exists():
    shutil.rmtree(cand)
(cand / 'reports').mkdir(parents=True)
shutil.copy2(bit, cand / bit.name)
shutil.copy2(hwh, cand / hwh.name)
for name in ('gate.txt', 'timing_summary.rpt', 'drc.rpt', 'methodology.rpt', 'utilization.rpt',
             'clock_interaction.rpt', 'route_status.rpt'):
    shutil.copy2(rep / name, cand / 'reports' / name)
ct = [l for l in (rep / 'check_timing.rpt').read_text().splitlines() if l.strip().startswith('There ')]
(cand / 'reports/check_timing_counts.txt').write_text('\n'.join(ct) + '\n', encoding='utf-8')
shutil.copy2(work / 'context.txt', cand / 'reports/context.txt')

git = lambda *a: subprocess.check_output(['git', *a], cwd=root, text=True).strip()
meta = {
    'schema': 'axi_dma_loopback_candidate',
    'purpose': 'non-Ascon overlay for pynq-overlay-workflow Skill L3 (stages C/D: register map + bounded DMA)',
    'source_commit': git('rev-parse', 'HEAD'),
    'source_dirty': bool(git('status', '--porcelain')),
    'source_sha256': {p.relative_to(root).as_posix(): sha(p) for p in sorted(board.glob('*.*')) if p.is_file()},
    'part': 'xc7z020clg400-1', 'top': 'dma_loop_wrapper', 'vivado': '2025.2',
    'strategy': 'Vivado Synthesis Defaults + ' + g['strategy'] + ' + post-route phys_opt',
    'implementation_run': {'run': g['run'], 'checkpoint': g['dcp']},
    'gate': g,
    'design': {'axi_dma_0': dict(expect_dma, vlnv='xilinx.com:ip:axi_dma:7.1', base='0x40400000', range='64K',
                                 control='PS7 M_AXI_GP0 -> axi_interconnect -> S_AXI_LITE',
                                 memory='M_AXI_MM2S + M_AXI_S2MM -> axi_interconnect -> PS7 S_AXI_HP0 (64-bit), '
                                        'aperture 0x00000000-0x3FFFFFFF',
                                 stream='M_AXIS_MM2S -> S_AXIS_S2MM direct (TDATA/TKEEP/TLAST)'),
               'clock_reset': 'all on FCLK0; proc_sys_reset from FCLK_RESET0_N (interconnect_aresetn to '
                              'interconnect cores, peripheral_aresetn to ports and DMA)',
               'interrupts': 'not connected (polling only)'},
    'ps_clock': dict(ps_clock, note='IO PLL pinned to the board boot image (33.333333 MHz x 30 = 1000 MHz); '
                     'stock PYNQ 2.7 Clocks.fclk0_mhz assumes a 50 MHz reference and shows 150 MHz'),
    'skill_l1_check': {'hwh_parse': 'axi_dma_0 @0x40400000 +0x10000', 'dma_config_from_hwh': {
        'max_transfer': cfg['max_transfer'], 'align_bytes': 4}},
    'hardware_validation': 'NOT_RUN',
}
manifest = artifacts.write_manifest([cand / bit.name, cand / hwh.name], cand / 'manifest.json', **meta)
artifacts.check_artifacts(str(cand / bit.name), manifest=str(cand / 'manifest.json'))
lines = ['%s  %s' % (v['sha256'], k) for k, v in sorted(manifest['artifacts'].items())]
lines.append('%s  manifest.json' % sha(cand / 'manifest.json'))
(cand / 'sha256sums.txt').write_bytes(('\n'.join(lines) + '\n').encode('ascii'))
print(json.dumps({'gate': g, 'artifacts': manifest['artifacts']}, indent=2))
print('AXI_DMA_LOOPBACK_PACKAGE_PASS', cand)
