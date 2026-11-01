"""Create separate current-source, historical-source, standalone Skill and report ZIPs."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'delivery'
SOURCE_EXT = {'.v','.vh','.sv','.c','.h','.s','.S','.ld','.py','.sh','.tcl','.ps1','.bat',
              '.xdc','.xci','.bd','.xpr','.coe','.mem','.hex','.json','.csv','.md','.txt','.ipynb',
              '.wcfg','.hwh','.yml','.yaml','.in','.ac','.make','.mak','.patch','.f','.flist',
              '.cfg','.conf','.sby','.svh','.vhd','.vhdl','.cpp','.hpp','.cc','.ini','.sdc','.tex','.dot','.gv','.m',
              '.tmpl','.html','.css','.js','.toml','.inc','.rst'}
ALLOWED = set()
SKIP_PARTS = {'.git','__pycache__','.pytest_cache','.ipynb_checkpoints','.Xil','validation',
              'work','work_v2','work_fix','output','candidate','reports','ASCON.cache','ASCON.sim'}


def sha(body):
    return hashlib.sha256(body).hexdigest()


def file_sha(path):
    return sha(path.read_bytes())


def source_files(base, skip_results=False):
    if not base.exists():
        return []
    result = []
    for p in base.rglob('*'):
        if not p.is_file():
            continue
        if p.relative_to(ROOT).as_posix() not in ALLOWED:
            continue
        parts = p.relative_to(base).parts
        if any(n in SKIP_PARTS or n.endswith(('.cache','.runs','.gen','.sim','.hw','.ip_user_files')) for n in parts):
            continue
        if skip_results and 'results' in parts:
            continue
        asset = ('figs' in parts or 'assets' in parts) and p.suffix in {'.pdf','.png','.jpg','.woff2'}
        if asset or p.suffix in SOURCE_EXT or '.v.backup' in p.name or p.name.lower() in {'license','copying','makefile','makefrag','latexmkrc','.gitignore'}:
            result.append(p)
    return result


def add_paths(files):
    return {p.relative_to(ROOT).as_posix():p.read_bytes() for p in files if p.is_file()}


def write_zip(name, prefix, items, revision):
    sums = {n:sha(b) for n,b in items.items()}
    meta = {'schema':1,'scope':name,'git_source_revision':revision,
            'generated':datetime.datetime.now().astimezone().isoformat(timespec='seconds'),
            'files':sums}
    items = dict(items)
    items['source_manifest.json'] = (json.dumps(meta,ensure_ascii=False,indent=2)+'\n').encode('utf-8')
    target = OUT/name
    temp = target.with_suffix('.tmp.zip')
    with zipfile.ZipFile(temp,'w',zipfile.ZIP_DEFLATED) as z:
        for n,b in sorted(items.items()):
            z.writestr(prefix+'/'+n,b)
    with zipfile.ZipFile(temp) as z:
        assert z.testzip() is None
        assert all(sha(z.read(prefix+'/'+n))==h for n,h in sums.items())
    temp.replace(target)
    return {'path':target.relative_to(ROOT).as_posix(),'sha256':file_sha(target),
            'bytes':target.stat().st_size,'files':len(items),'archive_root':prefix}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reject-label', action='append', default=[], help='Reject a label in delivery source text/names')
    args = parser.parse_args()
    for flags in (['ls-files','-z'], ['ls-files','--others','--exclude-standard','-z']):
        body = subprocess.check_output(['git',*flags],cwd=ROOT).decode('utf-8').strip('\0')
        ALLOWED.update(n for n in body.split('\0') if n)
    OUT.mkdir(exist_ok=True)
    revision = subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
    current = []
    for d in ['src','sim','ascon/ascon_c','ascon/pyascon','board/vivado_zynq7000_xc7z020_pynq_puf3',
              'board/vivado_zynq7000_xc7z020_ascon','board/atk_navigator_7020','data/ascon','tools']:
        current += source_files(ROOT/d,skip_results=True)
    current += [ROOT/n for n in ['build/readme.md','build/keys_ro_allow_loops.tcl','build/keys_ro_pblock.xdc','ascon/readme.md']]
    # Normative input PDFs are test/reference inputs, not an evidence-package copy.
    current += list((ROOT/'data/ascon/sources').glob('*.pdf'))
    current += [ROOT/n for n in ['README.md','AGENTS.md','LICENSE','project_board.md','.gitattributes','.gitignore','pytest.ini']]
    current += [p for p in (ROOT/'docs').glob('*.md') if p.is_file()]
    current += [ROOT/'src/pynq/jupyter_demo.ipynb',ROOT/'src/pynq/navigator_demo.ipynb']
    # Shared API's mock-test samples are small test fixtures, explicitly not new board data.
    items = add_paths(current)
    raw = ROOT/'archive/evidence/raw_records_20261102.zip'
    with zipfile.ZipFile(raw) as z:
        for stem in ['sw_timing_acb_sw','hw_timing_acb_hw','ise_timing_acb_ise']:
            for suffix in ['.json','.log']:
                name = 'data/ascon/results/key_lifecycle/'+stem+suffix
                items[name] = z.read(name)
    # The project ZIP deliberately excludes the independent Skill tree.
    items['pytest.ini'] = b'[pytest]\ntestpaths = src/pynq\nnorecursedirs = archive build data docs .git .venv\n'
    cand = ROOT/'board/vivado_zynq7000_xc7z020_pynq_puf3/candidate'
    items['known_artifact_manifest.json'] = (cand/'manifest.json').read_bytes()
    items['source_package.md'] = (
        '# Current PUF3 source package\n\nThis is source/configuration, not a prebuilt overlay or evidence bundle.\n'
        'Install Vivado2025.2, Icarus and an RV32IM_Zicsr cross compiler. Build from a Git checkout, or initialize\n'
        'a local Git repository/commit after extraction: the unchanged Tcl/package scripts query Git for provenance.\n'
        'The source_manifest identifies the actual archived source revision and byte hashes. A new local commit is not that original revision.\n'
        'Start at src/pynq_puf3/readme.md and build/readme.md. The historical artifact manifest is reference only;\n'
        'rebuilding does not prove a fresh bit has passed the archived board test.\n').encode()
    items['README.md'] = (
        '# Current PUF3 source project\n\n'
        'This package contains the RV32 five-stage CPU, Ascon SW/MMIO/ISE and PUF v1/DNA source,\n'
        'firmware, IP configurations, timing hooks, host libraries, vectors and the PUF3 Notebook.\n'
        'Start with [build instructions](build/readme.md), [board entry](board/readme.md),\n'
        '[Notebook guide](src/pynq_puf3/readme.md) and [source manifest](source_manifest.json).\n\n'
        'Vivado2025.2 / xc7z020clg400-1 / pynq_puf3_wrapper / PQF3=0x33465150 / pynq-svc-puf3.\n'
        'Use the board-local soc_top.v and key_mmio.v variants through the dedicated build Tcl; do not import all RTL blindly.\n'
        'See [source-only boundaries](source_package.md): no prebuilt overlay or evidence bundle is included.\n'
        'A Git checkout or a new local Git commit is required by the existing Vivado provenance queries.\n'
        'The six small archived timing files are host-test fixtures, not new performance measurements.\n'
        'The independent Skill, historical projects, report, full project board and raw records are separate in the full repository.\n'
        'Repository maintenance tools package_delivery.py, verify_delivery.py and restore_records.py require the full repository, not this source-only ZIP.\n'
        'Preserve LICENSE and file-level notices. PUF cross-power/PVT/reliability and RO-counter timing are not signed off.\n').encode()

    hist = add_paths(source_files(ROOT/'archive/history'))
    hist = {n.removeprefix('archive/history/'):b for n,b in hist.items()}
    # Supply current shared files without overwriting any isolated historical version.
    for n,b in items.items():
        if n.startswith(('src/rtl/','src/firmware/ascon_hw_rv32/','src/firmware/pynq_svc/',
                         'src/pynq/','ascon/','sim/ascon/','sim/keys/','data/ascon/',
                         'board/vivado_zynq7000_xc7z020_ascon/','build/keys_ro_')):
            hist.setdefault(n,b)
    invalid = 'board/vivado_zynq7000_xc7z020_puf_v2/candidate/INVALID.md'
    hist[invalid] = (ROOT/'archive/history'/invalid).read_bytes()
    # Retain distinct frozen source snapshots from the immutable experiment records.
    with zipfile.ZipFile(raw) as z:
        for n in z.namelist():
            if '/source_snapshot/' in n and Path(n).suffix in SOURCE_EXT and not n.endswith('.md'):
                hist['recorded_snapshots/'+n] = z.read(n)
    hist['README.md'] = (ROOT/'archive/history/README.md').read_bytes()
    hist['LICENSE'] = (ROOT/'LICENSE').read_bytes()

    skill_dir=ROOT/'skill/pynq-overlay-workflow'
    skill={p.relative_to(skill_dir).as_posix():p.read_bytes() for p in source_files(skill_dir)}
    skill['LICENSE']=(ROOT/'LICENSE').read_bytes()

    report=ROOT/'docs/tech_report/amd_fpga_2026_latex_final/amd_fpga_2026_report'
    if (report/'main.tex').is_file():
        paper={'final_report.pdf':(report/'output/pdf/final_report.pdf').read_bytes()}
        for folder in ['chapters','figs','evidence']:
            for p in (report/folder).rglob('*'):
                if p.is_file() and p.suffix in {'.tex','.png','.jpg','.pdf'}:
                    paper['latex/'+p.relative_to(report).as_posix()]=p.read_bytes()
        for n in ['main.tex','preamble.tex','cover.tex','header_logo.png','latexmkrc','build.ps1','build.sh',
                  'readme.md','build_review.py','review_evidence.py']:
            paper['latex/'+n]=(report/n).read_bytes()
    else:
        # Fresh clones keep editable report source in the independent tracked ZIP.
        with zipfile.ZipFile(OUT/'technical_report.zip') as z:
            paper={n.removeprefix('technical_report/'):z.read(n) for n in z.namelist()
                   if n.startswith('technical_report/') and not n.endswith(('/', '/source_manifest.json'))}
    paper['README.md']=(
        '# Technical report\n\nfinal_report.pdf is the current compiled paper. Editable files are under latex/.\n'
        'Compile main.tex with XeLaTeX/latexmk or Tectonic. The report verifier requires the full repository and\n'
        'restored original record layout; review scripts retain that original layout and may need explicit path restoration.\n'
        'Standalone LaTeX compilation is not a new evidence/board verification.\n'
        'Screenshot pixels and third-party notices are preserved. Original test/implementation records are not included.\n').encode()
    paper['LICENSE']=(ROOT/'LICENSE').read_bytes()

    groups=[('puf3_project.zip','puf3_project',items),('historical_projects.zip','historical_projects',hist),
            ('pynq_overlay_workflow_skill.zip','pynq-overlay-workflow',skill),('technical_report.zip','technical_report',paper)]
    for label in args.reject_label:
        bad=[]
        for name,_,content in groups:
            for n,b in content.items():
                if label.casefold() in n.casefold() or (Path(n).suffix.lower() not in {'.pdf','.png','.jpg'} and
                                                      label.casefold() in b.decode('utf-8',errors='ignore').casefold()):
                    bad.append(name+':'+n)
        if bad: raise SystemExit('Rejected label remains in delivery source: '+'\n'.join(bad))
    result={'source_revision':revision,'generated':datetime.datetime.now().astimezone().isoformat(timespec='seconds'),
            'packages':[write_zip(n,p,d,revision) for n,p,d in groups],
            'scope':'current and historical source separated; independent Skill; editable report; no evidence-package attachment'}
    (OUT/'manifest.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(result,ensure_ascii=False,indent=2))


if __name__=='__main__':
    main()
