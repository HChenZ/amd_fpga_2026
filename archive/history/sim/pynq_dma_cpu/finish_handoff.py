"""Assemble final non-board closure only from completed, independently checked evidence."""
import hashlib
import json
from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[2]
DATA=ROOT/'data/advanced/dma_cpu'
def read(path):return json.loads(path.read_text(encoding='utf-8'))

physical=DATA/'vivado_20261030_040257'
audit=read(physical/'candidate_audit.json')
assert audit['passed'] and audit['clock_mhz_actual_ip']==80 and audit['sta_period_ns']==12.5
for name,value in audit['artifacts'].items():
    assert hashlib.sha256((physical/'candidate'/name).read_bytes()).hexdigest()==value
timing=(physical/'result.txt').read_text()
setup=float(re.search(r'setup=([-0-9.]+)',timing).group(1))
hold=float(re.search(r'hold=([-0-9.]+)',timing).group(1))
assert setup>=0 and hold>=0 and 'critical_drc=0' in timing
assert 'ps_external_ports=1 invalid_pin_constraints=0' in timing
for file in (physical/'run_logs').glob('*.log'):
    assert not re.search(r'^\s*(?:ERROR:|CRITICAL WARNING:)',file.read_text(errors='replace'),re.M),str(file)

icarus=read(DATA/'full_20261030_002958_293520/verified_full.json')
assert icarus['passed'] and icarus['crypto_transactions']==7401
full=DATA/'xsim_20261030_014606_238543'
assert read(full/'verified.json')['passed']
assert read(full/'verified.json')['cases']==7418
compile_evidence=DATA/'xsim_20261030_013758_403545'
stages=read(compile_evidence/'result.json')['stages']
assert all(s['passed'] and s['exit_code']==0 for s in stages[:2])
assert [s['stage'] for s in stages[:2]]==['compile','elaborate']
# The initial runtime argument-parsing failure did not change the compiled DUT.
first=read(compile_evidence/'source_sha256.json');last=read(full/'source_sha256.json')
for name,value in first.items():
    if Path(name).suffix.lower() in ('.v','.sv','.vhd','.vh','.mif','.coe'):
        assert last[name]==value,'compiled DUT differs from successful runtime'
system=read(DATA/'xsim_20261030_030042_215364/verified.json')
assert system['passed'] and system['cases']==95
for directory in ('xsim_20261030_020522_037685','xsim_20261030_020527_060098','xsim_20261030_020531_854284'):
    assert read(DATA/directory/'verified.json')['passed']
units=DATA/'unit_20261030_043721_118939'
assert all(r['passed'] and r['exit_code']==0 for r in read(units/'result.json'))
for name,value in read(units/'source_sha256.json').items():
    assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==value,'unit input changed: '+name

result={
 'task':'advanced_dma_cpu','owner':'TBD','non_board_complete':True,'board':'NOT_RUN',
 'vivado_session':'vivado-20261030-010908-1cbde35d',
 'project':'build/local/dma_cpu/fclk80/cpu_dma.xpr','top':'cpu_dma_wrapper','part':'xc7z020clg400-1',
 'configured_clock_mhz':80,'sta_period_ns':12.5,'setup_slack_ns':setup,'hold_slack_ns':hold,
 'error_critical_drc':0,'netlist29_160':0,'remaining_methodology':'5 LUTAR-1 warnings; no waivers',
 'artifacts':audit['artifacts'],'candidate_directory':str((physical/'candidate').relative_to(ROOT)),
 'icarus_official_vectors':{'sw':1089,'hw_supported':289,'ise':1089},'icarus_crypto_transactions':7401,
 'xsim_unsharded_packets':7418,'xsim_vendor_dma_cpu_packets':95,
 'xsim_units':['endpoint','control','reset'],'host_tests':32,'cli_tests':10,
 'xsim_full_evidence':str(full.relative_to(ROOT)),
 'xsim_full_runtime_s':read(full/'result.json')['stages'][0]['elapsed_s'],
 'native_dma_ddr_model':'32-bit aligned INCR, single outstanding read/write BFM; not PS/DDR silicon or HP upsizer',
 'failures_preserved':['vivado_20261030_015408','vivado_20261030_025251','physopt_20261030_030502',
                       'xsim_20261030_013758_403545','xsim_20261030_025656_039012'],
 'not_claimed':['physical board validation','Fmax','post-route SDF simulation','board stability/performance']
}
out=DATA/'handoff_summary.json'
out.write_text(json.dumps(result,indent=2),encoding='utf-8')
print('CPU_DMA_NON_BOARD_CLOSURE_PASS',out)
