"""Build unchanged real RV32 self-test and seal the independent source manifest."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'data/advanced/puf_soc/firmware'
OUT.mkdir(parents=True, exist_ok=True)
subprocess.run([sys.executable, str(ROOT/'src/firmware/keys_v2/build.py'), '--out', str(OUT)], check=True, cwd=ROOT)
words = (OUT/'puf_v2.hex').read_text().split()
assert len(words) == 32768
(OUT/'puf_v2.coe').write_text('memory_initialization_radix=16;\nmemory_initialization_vector=\n' + ',\n'.join(words) + ';\n')
cpu = json.loads((ROOT/'sim/keys_v2/cpu_sources.json').read_text())['sources']
puf = json.loads((ROOT/'sim/keys_v2/sources.json').read_text())['sources']
sources = list(dict.fromkeys(cpu + puf + [
    'src/rtl/axi_full_master.v', 'src/rtl/cpu_axi_bridge.v', 'src/rtl/clint.v',
    'src/rtl/cpi_cnt.v', 'src/rtl/gpio.v', 'src/rtl/uart_ctrl.v', 'src/rtl/uart_rx.v', 'src/rtl/uart_tx.v',
    'src/rtl/ascon/ascon_aead_core.v', 'src/rtl/ascon/ascon_aead_2.v',
    'src/rtl/ascon/ascon_permutation.v', 'src/rtl/ascon/ascon_round.v', 'src/rtl/ascon/ascon_word.v',
    'board/vivado_zynq7000_xc7z020_pynq/rtl_p0/ascon_mmio.v',
    'src/rtl/keys_v2/puf_mmio_physical_v2.v', 'src/rtl/keys_v2/ro_array_v2.v',
    'src/rtl/pynq/pynq_ctl.v', 'src/rtl/pynq/pynq_mbox.v',
    'src/rtl/puf_soc_v2/bus_interconnect_puf_v2.v', 'src/rtl/puf_soc_v2/soc_top_puf_v2.v',
    'src/rtl/puf_soc_v2/top_puf_v2.v', 'src/rtl/puf_soc_v2/pynq_puf_soc_v2.v']))
manifest = ROOT/'board/vivado_zynq7000_xc7z020_puf_v2/sources.txt'
manifest.write_text('\n'.join(sources)+'\n')
paths = sources + ['src/rtl/defines.v', 'src/rtl/ascon/ascon_constants.vh']
(OUT.parent/'source_snapshot.json').write_text(json.dumps({
    'sources': sources, 'sha256': {p: hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths},
    'firmware': {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in OUT.iterdir() if p.is_file()},
    'firmware_address': '0x10000000', 'firmware_bytes': 131072,
    'puf_address': '0x30010000..0x300100ff', 'board': 'not_measured'}, indent=2)+'\n')
print('PUF_SOC_PREPARED', OUT)
