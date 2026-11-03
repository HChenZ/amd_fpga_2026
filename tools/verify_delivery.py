"""Verify ZIP manifests, cold-source firmware/elaboration/host tests and the independent Skill."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import platform
import re
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def sha(body):
    return hashlib.sha256(body).hexdigest()


def unpack(archive, target, item, labels):
    if sha(archive.read_bytes()) != item['sha256']:
        raise ValueError('ZIP hash mismatch: '+item['path'])
    with zipfile.ZipFile(archive) as z:
        if z.testzip() is not None:
            raise ValueError('ZIP CRC mismatch: '+item['path'])
        manifest = json.loads(z.read(item['archive_root']+'/source_manifest.json'))
        for n,h in manifest['files'].items():
            if sha(z.read(item['archive_root']+'/'+n)) != h:
                raise ValueError('Member hash mismatch: '+n)
        for info in z.infolist():
            path = (target/info.filename).resolve()
            if not path.is_relative_to(target.resolve()):
                raise ValueError('Unsafe ZIP path: '+info.filename)
            if info.is_dir():
                continue
            body = z.read(info)
            for label in labels:
                if label.casefold() in info.filename.casefold() or (path.suffix not in {'.pdf','.png','.jpg','.woff2'}
                        and label.casefold() in body.decode('utf-8',errors='ignore').casefold()):
                    raise ValueError('Rejected label remains: '+info.filename)
            path.parent.mkdir(parents=True,exist_ok=True)
            path.write_bytes(body)
    return {'zip_hash':'PASS','crc':'PASS','member_hashes':len(manifest['files'])}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=ROOT/'build/metadata/source_delivery_check.json')
    parser.add_argument('--reject-label',action='append',default=[])
    args = parser.parse_args()
    m = json.loads((ROOT/'delivery/manifest.json').read_text(encoding='utf-8'))
    base = Path(tempfile.gettempdir())/'opencode'
    base.mkdir(exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix='delivery_check_',dir=base))
    checks = {}
    for item in m['packages']:
        checks[item['path']] = unpack(ROOT/item['path'],work,item,args.reject_label)

    def run(name,command,cwd,timeout=180):
        p = subprocess.run(command,cwd=cwd,capture_output=True,timeout=timeout)
        text = (p.stdout+p.stderr).decode('utf-8',errors='replace')
        (work/(name+'.log')).write_text(text,encoding='utf-8')
        checks[name] = {'exit_code':p.returncode,'tail':text[-2200:].replace(str(work),'<scratch>')}
        print(name,'exit',p.returncode)
        if p.returncode:
            raise RuntimeError(name+' failed; log '+str(work/(name+'.log')))

    project, skill = work/'puf3_project',work/'pynq-overlay-workflow'
    run('puf3_source_identity_elaboration',[sys.executable,'-B','-X','utf8','tools/verify_puf3_sources.py','--compile'],project)
    run('cold_host_tests',[sys.executable,'-B','-m','unittest','discover','-s','src/pynq','-p','test_*.py'],project)
    run('standalone_skill',[sys.executable,'-B','-m','pytest','tests','-q','-p','no:cacheprovider'],skill)
    run('cold_firmware',[sys.executable,'-B','-X','utf8','src/firmware/pynq_svc_puf/build.py',
                         '--out','build/local/cold_verify_puf3'],project,300)
    known = json.loads((project/'known_artifact_manifest.json').read_text(encoding='utf-8'))
    binary = project/'build/local/cold_verify_puf3/pynq_svc_puf.bin'
    actual = sha(binary.read_bytes())
    expected = known['artifacts']['pynq_svc_puf.bin']['sha256']
    checks['cold_binary_matches_verified_candidate'] = {'passed':actual==expected,'sha256':actual}
    if actual != expected:
        raise ValueError('Recompiled BIN differs from known candidate; investigate toolchain/source differences')

    # PyMuPDF is a verifier dependency, not a firmware/Skill runtime requirement.
    import pymupdf
    pdf = work/'technical_report/final_report.pdf'
    with pymupdf.open(pdf) as d:
        text = ''.join(p.get_text() for p in d)
        compact = re.sub(r'\s+','',text)
        matches = sum(text.casefold().count(label.casefold()) for label in args.reject_label)
        metrics = all(t in compact for t in ['21862','1369','3895','15.969','5.613'])
        checks['report'] = {'pages':len(d),'pdf_sha256':sha(pdf.read_bytes()),
                            'rejected_label_matches':matches,'metric_tokens_present':metrics}
    if matches or not metrics:
        raise ValueError('Report text check failed')
    record = {'status':'PASS','timestamp':datetime.datetime.now().astimezone().isoformat(timespec='seconds'),
              'python':platform.python_version(),
              'scope':'cold extraction/member checks, build input presence, host/Skill tests, firmware rebuild and elaboration; not a new Vivado/board verdict',
              'source_revision':m['source_revision'],'packages':m['packages'],'checks':checks}
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('PASS: all delivery checks; local logs',work)
    return 0


if __name__=='__main__':
    raise SystemExit(main())
