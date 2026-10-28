"""Real RV32 service + bridge cosimulation; behavioral AXI memory, no crypto stubs."""
import sys, subprocess, json
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from src.pynq.mailbox_protocol import Request,Response,Mode,Operation,Status
from src.pynq.golden_checker import parse_kat
from src.pynq.pynq_transport import epoch_frame
out=Path('build/local/pynq_final');out.mkdir(parents=True,exist_ok=True)
requests=[epoch_frame(1)];responses=[];sizes=[20];counts=[0];rid=0
for mode in Mode:
 for size,alen in [(0,0),(1,0),(16,0),(16,16)]:
  case=next(c for c in parse_kat() if len(c['PT'])==size and len(c['AD'])==alen)
  key,nonce,ad,pt=(case[k] for k in ('Key','Nonce','AD','PT'))
  ct,tag=case['CT'][:-16],case['CT'][-16:]
  for op,data,t,st,payload in [(Operation.ENCRYPT,pt,b'',Status.OK,ct+tag),(Operation.DECRYPT,ct,tag,Status.OK,pt),(Operation.DECRYPT,ct,bytes([tag[0]^1])+tag[1:],Status.AUTH_FAILED,b'')]:
   rid+=1
   q=Request(1,rid,op,mode,key,nonce,ad,data,size+16,t).encode()
   r=Response(1,rid,op,mode,st,payload,1 if st==Status.OK else None,False).encode()
   requests.append(q);responses.append(r);sizes.append(len(q));counts.append(len(r))
for name,items,width in [('requests',b''.join(requests),2),('expected',b''.join(responses),2),('sizes',sizes,8),('counts',counts,8)]:
 (out/(name+'.hex')).write_text(''.join(format(x,'0%dx'%width)+'\n' for x in items))
rtl=[str(p) for p in Path('src/rtl').glob('*.v') if p.name not in ('top_pl_bram.v','soc_top.v')]
rtl += [str(p) for p in Path('src/rtl/ascon').glob('*.v') if p.name not in ('ascon_mmio.v','ascon_aead_2_tb.v')]
rtl += [str(p) for p in Path('board/vivado_zynq7000_xc7z020_pynq/rtl_p0').glob('*.v')]
rtl += ['src/rtl/pynq/pynq_ctl.v','src/rtl/pynq/pynq_mbox.v','sim/ascon/axi_slave_bram.v','sim/pynq/tb_pynq_svc.v']
commands=[['iverilog','-g2012','-I','src/rtl','-I','src/rtl/ascon','-s','tb_pynq_svc','-o',str(out/'svc.vvp')]+rtl,['vvp',str(out/'svc.vvp'),'+HEX=build/local/pynq_svc/pynq_svc.hex']]
results=[]
for i,cmd in enumerate(commands):
 with (out/('service_%d.log'%i)).open('wb') as log:
  p=subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT,timeout=1200)
 results.append(dict(command=cmd,exit_code=p.returncode))
 print((out/('service_%d.log'%i)).read_text(errors='replace')[-3000:],flush=True)
 if p.returncode: break
(out/'service.json').write_text(json.dumps(results,indent=2))
if p.returncode==0:
 log=(out/'service_1.log').read_text()
 assert 'PYNQ_SVC_COSIM PASS' in log and 'RESET_DURING_FRAME PASS' in log and log.count('PASS (real RV32')==36
sys.exit(p.returncode)
