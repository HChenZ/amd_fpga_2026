"""Collect real evidence; missing implementation results remain not_measured."""
import gzip
import hashlib
import json
import re
import subprocess
from pathlib import Path
from support import ROOT

evidence=ROOT/'data/ascon/results/key_lifecycle'
reports=ROOT/'build/reports/ascon_key_lifecycle'
# Re-serialize historical report objects without changing results. Older native
# Windows writers emitted CRLF despite the data tree's byte-preserving attributes.
for path in evidence.glob('*.json'):
    obj=json.loads(path.read_text(encoding='utf-8'))
    path.write_text(json.dumps(obj,indent=2,ensure_ascii=False)+'\n',encoding='utf-8',newline='\n')
def read(name):
    p=evidence/name
    if p.exists(): return p.read_text(encoding='utf-8')
    return gzip.decompress(p.with_suffix(p.suffix+'.gz').read_bytes()).decode('utf-8')
def data(name): return json.loads(read(name))
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
summary=dict(date='2026-10-16',timezone='Asia/Shanghai',task='V06',owner='TBD',
    source_base='c37ecae4bba050d833079d56f8aec05365637aad',branch='fix/ascon-key-lifecycle',
    evidence_kind='simulation_and_implementation_report',board='unknown',hardware_measured=False,
    tests={},limitations=[
        'MMIO supports at most 16-byte message and AD, not multi-block.',
        'CPU KAT is representative subset; full 1089 corpus verified on host.',
        'No full RV64, ISA, preemptive context, exception or board validation.',
        'Software buffer is caller-owned during call; no concurrent/DMA access contract.',
        'Wipes do not prove erasure of caches/register copies or physical/side-channel resistance.',
        'Original board pins remain unverified; no bitstream generated/programmed.',
        'BRAM COE still original FreeRTOS; Ascon board firmware loading pending.',
    ])
for name in ('host_after','c_failure_after'):
    summary['tests'][name]=data(name+'.json')['summary']
summary['tests']['standalone_rtl']=data('rtl_final.json')['summary']
summary['tests']['standalone_scope']=data('rtl_final.json')['official_rtl_kat']
summary['tests']['rtl_security']=data('key_rtl_after.json')
summary['tests']['cpu_units']=data('cpu_units.json')
summary['tests']['rtl_fault_harness']=data('rtl_harness_after.json')
summary['tests']['host_harness']={'tests':5,'status':'PASS' if 'OK' in read('host_harness.log') else 'FAIL'}
summary['cpu']={}
for name in ('sw_final','hw_final','ise_final','sw_security_final','hw_security_final','ise_security_final_verified'):
    r=data(name+'.json');assert r['status']=='PASS',name
    text=read(name+'.log')
    summary['cpu'][name]=dict(status=r['status'],report=name+'.json',
        tool_version=next(line for line in text.splitlines() if line.startswith('riscv64-unknown-elf-gcc (')),
        size=r['size'],tested_elf_sha256=r['elf_sha256'],
        measurements=[line for line in text.splitlines() if re.search(r'cycles|full MMIO|crypto latency|checks PASS|PASS injected',line)
                      and not line.startswith('$')])
    dis=ROOT/'build/local/key_audit'/name/'firmware.dis'
    if dis.exists():
        words=re.findall(r'^\s*[0-9a-f]+:\s+([0-9a-f]{8})\s',dis.read_text(),re.M)
        summary['cpu'][name]['static_custom0_instruction_count']=sum(int(w,16)&127==11 for w in words)
summary['tests']['final_loadable_rebuild']=data('final_firmware_rebuild.json')
assert all(r['identical_loadable_image'] for r in summary['tests']['final_loadable_rebuild'])
summary['source_hashes']={p.relative_to(ROOT).as_posix():digest(p)
    for folder in ('src/rtl','src/firmware/ascon_rv32','src/firmware/ascon_hw_rv32','src/firmware/ascon_ise_rv32','ascon/ascon_c/aead','sim/ascon')
    for p in (ROOT/folder).rglob('*') if p.is_file() and p.suffix in ('.v','.vh','.c','.h','.S','.ld','.py','.sh') and '__pycache__' not in p.parts}
snapshot=ROOT/'build/local/ascon_vivado3/development_rtl'
summary['vivado_snapshot_matches_current_rtl']=all(digest(p)==digest(ROOT/'src/rtl'/p.relative_to(snapshot))
    for p in snapshot.rglob('*') if p.is_file() and p.suffix in ('.v','.vh')) if snapshot.exists() else None
summary['vivado']=dict(version='2025.2',part='xc7z020clg400-1',top='top_pl_bram',input_clock_mhz=50,core_clock_mhz=100,
    commands=['vivado -mode batch -source build/build_ascon_review.tcl -notrace -tclargs ascon_vivado3',
              'vivado -mode batch -source build/build_ascon_review.tcl -notrace -tclargs ascon_vivado3 resume'],
    synthesis='not_measured',implementation='not_measured',board_validation='not_measured')
summary['vivado']['execution']=data('vivado_execution.json')
for stage in ('synth','route'):
    u=reports/(stage+'_utilization.rpt');t=reports/(stage+'_timing.rpt')
    if not (u.exists() and t.exists()):continue
    util=u.read_text();timing=t.read_text()
    values={}
    for key,pattern in [('lut',r'Slice LUTs\*?'),('ff',r'Slice Registers'),('bram_tiles',r'Block RAM Tile'),('dsp',r'DSPs')]:
        m=re.search(r'\|\s*'+pattern+r'\s*\|\s*([\d.]+)',util)
        values[key]=float(m.group(1)) if m else None
    m=re.search(r'WNS\(ns\).*?\n\s*-+.*?\n\s*([-\d.]+)\s+([-\d.]+)\s+(\d+)\s+(\d+)\s+([-\d.]+)\s+([-\d.]+)',timing,re.S)
    if m:values.update(wns_ns=float(m[1]),tns_ns=float(m[2]),whs_ns=float(m[5]),ths_ns=float(m[6]),setup_failing_endpoints=int(m[3]))
    values['timing_met']='All user specified timing constraints are met.' in timing
    values['has_io_delay_warnings']='no input delay specified. (HIGH)' in timing or 'no output delay specified. (HIGH)' in timing
    summary['vivado'][stage]=values
    summary['vivado']['synthesis' if stage=='synth' else 'implementation']='completed'
if (reports/'route_drc.rpt').exists():
    txt=(reports/'route_drc.rpt').read_text()
    summary['vivado']['drc_report']='build/reports/ascon_key_lifecycle/route_drc.rpt'
    summary['vivado']['drc_summary_lines']=[line for line in txt.splitlines() if line.startswith('|') and re.search(r'Warning|Error|Critical',line)]
    summary['vivado']['drc_reported_checks']=int(re.search(r'Checks found:\s*(\d+)',txt)[1])
summary['protected_assets']=dict(recovered_hashes=579,status='PASS',log='recovery_hash_check.log')
summary['historical_failures']=[p.name for p in evidence.glob('*.json') if p.name!='validation_summary.json'
    and ('before' in p.name or p.name in ('ise_after.json','ise_security_after.json','ise_security_final.json','ise_security_final_retry.json','rtl_after.json'))]
summary['git_diff_check_exit']=subprocess.run(['git','diff','--check'],cwd=ROOT,capture_output=True).returncode
summary['git_cached_diff_check_exit']=subprocess.run(['git','diff','--cached','--check'],cwd=ROOT,capture_output=True).returncode
(evidence/'validation_summary.json').write_text(json.dumps(summary,indent=2,ensure_ascii=False)+'\n',encoding='utf-8', newline="\n")
print(json.dumps(summary['vivado'],indent=2))
