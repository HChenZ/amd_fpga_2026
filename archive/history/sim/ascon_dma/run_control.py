from pathlib import Path
import datetime,hashlib,json,subprocess
ROOT=Path(__file__).resolve().parents[2]
out=ROOT/'data/advanced/dma_direct'/('control_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S'));out.mkdir(parents=True)
work=ROOT/'build/local/advanced_dma';work.mkdir(exist_ok=True)
sources=[ROOT/'src/rtl/ascon/ascon_round.v',*sorted((ROOT/'src/rtl/ascon_dma').glob('*.v')),ROOT/'sim/ascon_dma/tb_dma_control.sv']
report={'backend':'iverilog/vvp','kind':'rtl_simulation','sources':{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources},'commands':[]}
try:
 for label,cmd in [('compile',['iverilog','-g2012','-s','tb_dma_control','-o',str(work/'control.vvp'),*map(str,sources)]),('run',['vvp',str(work/'control.vvp')])]:
  p=subprocess.run(cmd,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=90)
  text=p.stdout+p.stderr;(out/(label+'.log')).write_text(text,encoding='utf-8');report['commands'].append({'command':cmd,'exit_code':p.returncode});print(label,p.returncode,text[-1000:])
  if p.returncode or (label=='run' and 'TEST_PASS' not in text):raise RuntimeError(label)
 report['status']='PASS'
finally:
 report.setdefault('status','FAIL');(out/'summary.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
