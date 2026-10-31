"""Hash the actual CPU experiment's inputs/artifacts without touching originals."""
import argparse
import hashlib
import json
from pathlib import Path
import xml.etree.ElementTree as ET
import re

p=argparse.ArgumentParser()
p.add_argument('directory',type=Path)
p.add_argument('--source-list',type=Path)
a=p.parse_args()
root=Path(__file__).resolve().parents[2]
files=set(a.directory.rglob('*'))
files.update((root/'board/vivado_zynq7000_xc7z020_pynq_dma_cpu').glob('*'))
files.update((root/'build/advanced').glob('cpu_dma*.tcl'))
files.add(Path(__file__).resolve())
if a.source_list:
    files.update(Path(line.strip()) for line in a.source_list.read_text().splitlines() if line.strip())
hashes={str(f.resolve()):hashlib.sha256(f.read_bytes()).hexdigest() for f in sorted(files)
        if f.is_file() and f.name!='sha256.json' and f.suffix.lower() in ('.v','.sv','.vh','.vhd','.xdc','.xci','.bd','.coe','.mif',
                                               '.bit','.hwh','.bin','.tcl','.py','.rpt','.txt','.log','.json')}
out=a.directory/'sha256.json'
out.write_text(json.dumps(hashes,indent=2),encoding='utf-8')
print('HASHED',len(hashes),'files:',out)
candidate=a.directory/'candidate'
if candidate.exists():
    tree=ET.parse(candidate/'dma_cpu.hwh')
    external=[p.attrib['NAME'] for p in tree.findall('./EXTERNALPORTS/PORT')]
    assert any(n.startswith('DDR') for n in external),'PS DDR interface not exported'
    assert any(n.startswith('FIXED_IO') for n in external),'PS fixed IO interface not exported'
    modules={m.attrib['INSTANCE']:m for m in tree.findall('.//MODULE')
             if m.attrib.get('FULLNAME') in ('/engine','/dma','/ps7','/private_bram')}
    params={name:{p.attrib['NAME']:p.attrib['VALUE'] for p in module.findall('./PARAMETERS/PARAMETER') if 'VALUE' in p.attrib}
            for name,module in modules.items()}
    expected={'c_include_sg':'0','c_micro_dma':'0','c_include_mm2s':'1','c_include_s2mm':'1',
              'c_m_axi_mm2s_data_width':'32','c_m_axi_s2mm_data_width':'32',
              'c_m_axis_mm2s_tdata_width':'32','c_s_axis_s2mm_tdata_width':'32','c_sg_length_width':'14'}
    for key,value in expected.items():assert params['dma'][key]==value,(key,params['dma'].get(key))
    assert params['ps7']['PCW_S_AXI_HP0_DATA_WIDTH']=='64'
    requested_mhz=float(params['ps7']['PCW_FPGA0_PERIPHERAL_FREQMHZ'])
    actual_mhz=float(params['ps7']['PCW_ACT_FPGA0_PERIPHERAL_FREQMHZ'])
    assert abs(requested_mhz-actual_mhz)<0.000001,'requested/actual PS clock mismatch'
    timing_result=(a.directory/'result.txt').read_text()
    period=float(re.search(r'clock=clk_fpga_0 period_ns=([0-9.]+)',timing_result).group(1))
    assert abs(1000/period-actual_mhz)<0.001,'STA period differs from implemented PS frequency configuration'
    ps_ranges={r.attrib['INSTANCE']:r.attrib for r in modules['ps7'].findall('.//MEMRANGE')}
    cpu_ranges={r.attrib['INSTANCE']:r.attrib for r in modules['engine'].findall('.//MEMRANGE')}
    assert int(ps_ranges['engine']['BASEVALUE'],16)==0x40000000
    assert int(ps_ranges['dma']['BASEVALUE'],16)==0x40400000
    assert int(cpu_ranges['private_bram']['BASEVALUE'],16)==0x10000000
    assert int(cpu_ranges['private_bram']['HIGHVALUE'],16)==0x1001ffff
    firmware=json.loads((candidate/'firmware_build.json').read_text())
    assert hashlib.sha256((candidate/'dma_svc.bin').read_bytes()).hexdigest()==firmware['sha256']['dma_svc.bin']
    audit={'passed':True,'clock_mhz_configured':requested_mhz,'clock_mhz_actual_ip':actual_mhz,'sta_period_ns':period,
           'dma':expected,'ps_ranges':ps_ranges,'cpu_ranges':cpu_ranges,'external_ports':external,'board':'NOT_RUN',
           'artifacts':{f.name:hashlib.sha256(f.read_bytes()).hexdigest() for f in candidate.iterdir() if f.is_file()}}
    (a.directory/'candidate_audit.json').write_text(json.dumps(audit,indent=2),encoding='utf-8')
    print('CANDIDATE_HWH_IDENTITY_PASS')
