"""Parse saved UART text; default evidence is simulated, never inferred as FPGA measurement."""
import argparse
import json
from pathlib import Path
import re
import shlex
import sys


def parse(text, evidence_kind='simulated'):
    if evidence_kind not in ('simulated','rtl_simulation','hardware_uart_capture'):
        raise ValueError('unknown evidence kind')
    meta = dict(mode=None, firmware_version=None, rtl_sha=None, bitstream_sha=None)
    rows, errors = [], []
    for number, line in enumerate(text.splitlines(),1):
        if 'software on RV32' in line:
            meta['mode'] = 'sw'
        elif re.search(r'===.*MMIO',line,re.I):
            meta['mode'] = 'hw'
        elif re.search(r'===.*ISE',line):
            meta['mode'] = 'ise'
        if line.strip().startswith('[ASCON]'):
            try:
                pairs = [token.split('=',1) for token in shlex.split(line.strip()[7:]) if '=' in token]
                fields = dict(pairs)
                if len(fields)!=len(pairs):
                    raise ValueError('duplicate log field')
                for key in meta:
                    if key in fields:
                        meta[key] = fields[key].lower() if key == 'mode' else fields[key]
                if meta['mode'] not in (None,'sw','hw','ise'):
                    raise ValueError('invalid mode')
                for key in ('rtl_sha','bitstream_sha'):
                    if meta[key] and not re.fullmatch(r'[0-9a-fA-F]{40}|[0-9a-fA-F]{64}',meta[key]):
                        raise ValueError('invalid '+key)
                if 'test' not in fields:
                    if 'status' in fields or 'mcycle' in fields:
                        raise ValueError('test name missing for result')
                    continue
                if not fields['test'] or len(fields['test'])>128:
                    raise ValueError('invalid test name')
                status = fields.get('status','NOT_RUN').upper()
                if status not in ('PASS','FAIL','BLOCKED','NOT_RUN'):
                    raise ValueError('invalid status')
                cycles = int(fields['mcycle'],0) if fields.get('mcycle') else None
                if cycles is not None and not 0 <= cycles < 2**64:
                    raise ValueError('mcycle outside u64')
                rows.append(dict(meta, test=fields['test'],status=status,mcycle=cycles,line=number))
            except (ValueError, TypeError) as exc:
                errors.append(dict(line=number,error=str(exc)))
        else:
            match = re.fullmatch(r'\s*([^:\r\n]+?)\s*:\s*(PASS|FAIL)\s*',line)
            if match:
                rows.append(dict(meta,test=match[1].strip(),status=match[2],mcycle=None,line=number))
            benchmark = re.fullmatch(r'\s*((?:enc|dec) \d+B|crypto latency|full MMIO|ISE cycles)\s*:\s*'
                                     r'(\d+)(?: cycles(?:,.*)?)?\s*',line)
            if benchmark:
                cycles = int(benchmark[2])
                if cycles >= 2**64:
                    errors.append(dict(line=number,error='mcycle outside u64'))
                else:
                    crypto = benchmark[1]=='crypto latency'
                    row = dict(meta,test=benchmark[1],status='NOT_RUN',mcycle=None if crypto else cycles,line=number)
                    if crypto:
                        row['crypto_core_cycles'] = cycles
                        row['cycle_scope'] = 'crypto core latency; not CSR mcycle'
                    rows.append(row)
            if re.search(r'\b(?:FAIL|FATAL|TIMEOUT)\b',line):
                errors.append(dict(line=number,error='failure marker in capture'))
    for row in rows:
        row['evidence_kind'] = evidence_kind
        row['simulated'] = evidence_kind != 'hardware_uart_capture'
        row['measurement_status'] = ('NOT_MEASURED' if row['mcycle'] is None else
                                     ('hardware_uart_capture_unverified' if not row['simulated'] else evidence_kind))
    status = 'FAIL' if errors or any(r['status']=='FAIL' for r in rows) else (
             'BLOCKED' if not rows or any(r['status']=='BLOCKED' for r in rows) else (
             'PASS' if any(r['status']=='PASS' for r in rows) else 'NOT_RUN'))
    return dict(schema_version=1,status=status,evidence_kind=evidence_kind,records=rows,errors=errors,
                note='Parsed claims only; no board/firmware/bitstream identity attestation. Missing metadata remains null.')


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('log',type=Path)
    p.add_argument('--evidence-kind',default='simulated',choices=('simulated','rtl_simulation','hardware_uart_capture'))
    p.add_argument('--out',type=Path)
    a = p.parse_args()
    result = parse(a.log.read_text(encoding='utf-8',errors='replace'),a.evidence_kind)
    result['input_file'] = str(a.log.resolve())
    text = json.dumps(result,indent=2,ensure_ascii=False)+'\n'
    if a.out:
        from common import local_output
        local_output(a.out).write_text(text,encoding='utf-8',newline='\n')
    else:
        print(text,end='')
    return {'PASS':0,'FAIL':1,'BLOCKED':2,'NOT_RUN':2}[result['status']]


if __name__ == '__main__':
    sys.exit(main())
