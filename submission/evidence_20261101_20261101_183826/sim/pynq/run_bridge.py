import subprocess
from pathlib import Path
out=Path('build/local/pynq_final');out.mkdir(parents=True,exist_ok=True)
for i,c in enumerate([['iverilog','-g2012','-s','tb_pynq_bridge','-o',str(out/'bridge.vvp'),'src/rtl/pynq/pynq_ctl.v','src/rtl/pynq/pynq_mbox.v','src/rtl/uart_rx.v','src/rtl/uart_tx.v','sim/pynq/tb_pynq_bridge.v'],['vvp',str(out/'bridge.vvp')]]):
 p=subprocess.run(c,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=120)
 (out/('bridge_%d.log'%i)).write_bytes(p.stdout)
 print(p.stdout.decode(errors='replace'))
 if p.returncode: raise SystemExit(p.returncode)
