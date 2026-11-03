"""Tie each COE build's BIN to the exact BIN used by the existing CPU runner."""
import argparse
import json
from pathlib import Path
import sys

from common import ROOT, local_output, sha256, write_json


def verify(builds_path, evidence):
    builds = json.loads(Path(builds_path).read_text(encoding='utf-8'))
    checks = []
    for row in builds:
        mode = row['mode']
        reports = list((Path(evidence)/('cpu_'+mode)).rglob('*.json'))
        if row['status']!='PASS' or len(reports)!=1:
            raise ValueError('missing successful firmware/CPU evidence: '+mode)
        cpu = json.loads(reports[0].read_text(encoding='utf-8'))
        if cpu.get('status')!='PASS' or cpu['source_head']!=row['source_head']:
            raise ValueError('CPU evidence failed or source HEAD differs: '+mode)
        command = next(c['command'] for c in cpu['commands']
                       if any(str(x).endswith(('objcopy','objcopy.exe')) for x in c['command']))
        binary = ROOT/command[-1]
        digest = sha256(binary)
        built = Path(row['outputs']['bin']['path'])
        if sha256(built)!=row['outputs']['bin']['sha256'] or digest!=row['outputs']['bin']['sha256']:
            raise ValueError('CPU-tested BIN differs from COE build BIN: '+mode)
        checks.append(dict(mode=mode,status='PASS',sha256=digest,cpu_bin=str(binary),coe_build_bin=str(built)))
    if {c['mode'] for c in checks}!={'sw','hw','ise'} or len(checks)!=3:
        raise ValueError('require exactly SW/HW/ISE build records')
    return checks


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--builds',type=Path,required=True)
    p.add_argument('--cpu-evidence',type=Path,required=True)
    p.add_argument('--out',type=Path,required=True)
    a=p.parse_args()
    result = dict(status='FAIL',evidence_kind='image_identity_check')
    try:
        result.update(checks=verify(a.builds,a.cpu_evidence),status='PASS')
    except Exception as exc:
        result['error']=str(exc)
    write_json(local_output(a.out),result)
    print(result['status'],a.out)
    return 0 if result['status']=='PASS' else 1


if __name__=='__main__':
    sys.exit(main())
