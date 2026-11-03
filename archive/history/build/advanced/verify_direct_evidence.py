"""Verify the exact HW_DIRECT candidate, current source identity and offline evidence.
This is artifact validation, not a rerun of Vivado or a board test.
"""
import argparse
import hashlib
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]

def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()

def checked_sources(manifest):
    for name,expected in manifest.get('source_sha256',{}).items():
        p=Path(name)
        if not p.is_absolute():p=ROOT/p
        if not p.is_file() or digest(p)!=expected:
            raise ValueError('current source differs from tested snapshot: '+name)

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--implementation',required=True,type=Path)
    ap.add_argument('--vendor-test',required=True,type=Path)
    ap.add_argument('--rtl-test',required=True,type=Path)
    ap.add_argument('--lifecycle',required=True,type=Path)
    ap.add_argument('--output',required=True,type=Path)
    a=ap.parse_args()
    report={'kind':'artifact_verification','board':'NOT_RUN','status':'FAIL','inputs':{}}
    try:
        impl=json.loads((a.implementation/'manifest.json').read_text(encoding='utf-8'))
        checked_sources(impl)
        for name,meta in impl['artifacts'].items():
            path=a.implementation/'candidate'/name
            if digest(path)!=meta['sha256'] or path.stat().st_size!=meta['bytes']:raise ValueError('artifact mismatch '+name)
        text=(a.implementation/'result.txt').read_text(encoding='utf-8')
        fields=dict(token.split('=',1) for token in text.split() if '=' in token)
        if float(fields['setup'])<0 or float(fields['hold'])<0 or fields['critical_drc']!='0':raise ValueError('implementation gate failed')
        timing=(a.implementation/'timing.rpt').read_text(encoding='utf-8')
        if 'checking no_clock (0)' not in timing or 'checking unconstrained_internal_endpoints (0)' not in timing:raise ValueError('unconstrained implementation')
        for name,folder in [('vendor',a.vendor_test),('rtl',a.rtl_test)]:
            p=folder/'summary.json';m=json.loads(p.read_text(encoding='utf-8'))
            if m['status']!='PASS':raise ValueError(name+' failed')
            checked_sources(m)
            report['inputs'][name]={'path':str(folder),'summary_sha256':digest(p)}
        lm=json.loads((a.lifecycle/'sources.json').read_text(encoding='utf-8'));checked_sources(lm)
        normal=(a.lifecycle/'run.log').read_text(encoding='utf-8',errors='replace')
        mutation=(a.lifecycle/'mutation_run.log').read_text(encoding='utf-8',errors='replace')
        if 'TEST_PASS lifecycle checks=201' not in normal or 'BAD_TAG_ACCEPTED' not in mutation:raise ValueError('lifecycle/mutation evidence missing')
        report['implementation']=impl
        report['lifecycle']=str(a.lifecycle)
        report['status']='PASS'
    except Exception as e:
        report['error']=str(e)
        raise
    finally:
        a.output.parent.mkdir(parents=True,exist_ok=True)
        a.output.write_text(json.dumps(report,indent=2),encoding='utf-8')
        print(report['status'],a.output)

if __name__=='__main__':main()
