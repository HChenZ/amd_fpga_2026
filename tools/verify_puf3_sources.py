"""Check PUF3 production inputs (LF/CRLF-equivalent); optional elaboration, not a new functional or board run."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[1]


def digest(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def eol_digests(b):
    # The candidate recorded Windows (CRLF) working copies; Linux checkouts and Git blobs use LF.
    lf=b.replace(b'\r\n',b'\n')
    return {hashlib.sha256(b).hexdigest(),hashlib.sha256(lf).hexdigest(),hashlib.sha256(lf.replace(b'\n',b'\r\n')).hexdigest()}


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--compile',action='store_true')
    ap.add_argument('--output',type=Path)
    a=ap.parse_args()
    cand=ROOT/'board/vivado_zynq7000_xc7z020_pynq_puf3/candidate'
    manifest=cand/'manifest.json'
    if not manifest.is_file(): manifest=ROOT/'known_artifact_manifest.json'
    m=json.loads(manifest.read_text(encoding='utf-8'))
    inputs={n:h for n,h in m['source_sha256'].items() if Path(n).suffix in {'.v','.vh','.xdc','.c','.h'}
            and n not in m['excluded_from_build'] and not n.endswith('_tb.v')}
    bad=[]
    for n,h in inputs.items():
        p=ROOT/n
        if not p.is_file(): bad.append(n); continue
        if h not in eol_digests(p.read_bytes()): bad.append(n)
    support = {n:h for n,h in m['source_sha256'].items() if Path(n).suffix in {'.tcl','.xdc'}}
    for n,h in support.items():
        p=ROOT/n
        if not p.is_file(): bad.append(n); continue
        if h not in eol_digests(p.read_bytes()): bad.append(n)
    # These are read/imported by build.tcl or its opt_design pre-hook, not by Icarus.
    required = ['build/keys_ro_allow_loops.tcl','build/keys_ro_pblock.xdc']
    ipbase = 'board/vivado_zynq7000_xc7z020_ascon/riscv_vivado_project/riscv_vivado_project.srcs/sources_1/ip'
    required += [ipbase+'/'+n+'/'+n+'.xci' for n in ['axi_bram_ctrl_0','blk_mem_gen_0']]
    missing_support = [n for n in required if not (ROOT/n).is_file()]
    bad.extend(missing_support)
    artifacts={n:('MATCH' if digest(cand/n)==d['sha256'] else 'MISMATCH') if (cand/n).is_file()
               else 'NOT_BUNDLED_SOURCE_ONLY' for n,d in m['artifacts'].items()}
    result={'status':'PASS' if not bad and 'MISMATCH' not in artifacts.values() else 'FAIL',
            'scope':'production source identity and optional elaboration only; no new functional/board verdict',
            'production_inputs':len(inputs),'source_mismatches':bad,'artifacts':artifacts}
    result['build_support']={'candidate_hashes_checked':len(support),'required_paths':required,'missing':missing_support}
    if a.compile:
        iv=shutil.which('iverilog')
        if not iv: raise SystemExit('iverilog is required for --compile')
        sources=sorted(str(p.relative_to(ROOT)) for p in (ROOT/'src/rtl').glob('*.v') if p.name not in {'soc_top.v','top_pl_bram.v'})
        sources+=sorted(str(p.relative_to(ROOT)) for p in (ROOT/'src/rtl/ascon').glob('*.v') if not p.name.endswith('_tb.v'))
        sources+=sorted(str(p.relative_to(ROOT)) for p in (ROOT/'src/rtl/keys').glob('*.v') if p.name!='key_mmio.v')
        sources+=['board/vivado_zynq7000_xc7z020_pynq_puf3/rtl/soc_top.v',
                  'board/vivado_zynq7000_xc7z020_pynq_puf3/rtl/key_mmio.v',
                  'src/rtl/pynq/pynq_ctl.v','src/rtl/pynq/pynq_mbox.v',
                  'sim/keys/DNA_PORT_sim.v','sim/keys/BUFG_sim.v','sim/keys/LUT_sim.v',
                  'sim/ascon/axi_slave_bram.v','sim/pynq_puf3/tb_pynq_puf3.v']
        base=Path(tempfile.gettempdir())/'opencode'
        base.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='puf3_elab_',dir=base) as temp:
            command=[iv,'-g2012','-I','src/rtl','-I','src/rtl/ascon','-s','tb_pynq_puf3','-o',str(Path(temp)/'sim.vvp')]+sources
            run=subprocess.run(command,cwd=ROOT,capture_output=True,timeout=180)
            result['elaboration']={'exit_code':run.returncode,'diagnostics':(run.stdout+run.stderr).decode('utf-8',errors='replace')}
            if run.returncode: result['status']='FAIL'
    text=json.dumps(result,ensure_ascii=False,indent=2)+'\n'
    if a.output:
        a.output.parent.mkdir(parents=True,exist_ok=True)
        a.output.write_text(text,encoding='utf-8')
    print(text)
    return 0 if result['status']=='PASS' else 1


if __name__=='__main__':
    raise SystemExit(main())
