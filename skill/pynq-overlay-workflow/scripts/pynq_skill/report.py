"""Collect Vivado utilization/timing reports and host results into one Markdown + JSON report."""
import json
import os
import platform
import re

from .artifacts import sha256_file

EVIDENCE = ('measured', 'simulated', 'estimated', 'not_measured')


def _header(text):
    out = {}
    for key in ('Tool Version', 'Design', 'Device', 'Design State', 'Date'):
        m = re.search(r'\|\s*%s\s*:\s*(.+)' % re.escape(key), text)
        if m:
            out[key.lower().replace(' ', '_')] = m.group(1).strip()
    return out


def parse_utilization(path):
    with open(path, encoding='utf-8', errors='replace') as f:
        text = f.read()
    rows = {}
    for line in text.splitlines():
        cells = [c.strip() for c in line.strip().strip('|').split('|')]
        if len(cells) < 4 or cells[0] in ('Site Type', '') or set(cells[0]) <= set('-+'):
            continue
        name = cells[0].lstrip('* ').rstrip('*').strip()
        try:
            used = float(cells[1])
        except ValueError:
            continue
        avail = util = None
        nums = []
        for c in cells[2:]:
            try:
                nums.append(float(c))
            except ValueError:
                nums.append(None)
        if len(nums) >= 2 and nums[-1] is not None:
            util = nums[-1]
            avail = nums[-2]
        rows.setdefault(name, {'used': used, 'available': avail, 'util_pct': util})
    keys = ['Slice LUTs', 'Slice Registers', 'Block RAM Tile', 'DSPs', 'F7 Muxes', 'Register as Latch']
    summary = {k: rows[k] for k in keys if k in rows}
    return {'path': os.path.abspath(path), 'sha256': sha256_file(path), 'header': _header(text),
            'summary': summary, 'all': rows}


def parse_timing_summary(path):
    with open(path, encoding='utf-8', errors='replace') as f:
        text = f.read()
    m = re.search(r'WNS\(ns\)\s+TNS\(ns\).*?\n\s*-+.*?\n\s*([-\d.]+)\s+([-\d.]+)\s+(\d+)\s+(\d+)\s+([-\d.]+)\s+([-\d.]+)',
                  text, re.S)
    res = {'path': os.path.abspath(path), 'sha256': sha256_file(path), 'header': _header(text)}
    if m:
        res.update(wns_ns=float(m.group(1)), tns_ns=float(m.group(2)), whs_ns=float(m.group(5)),
                   ths_ns=float(m.group(6)), failing_setup_endpoints=int(m.group(3)))
        res['timing_met'] = res['wns_ns'] >= 0 and res['whs_ns'] >= 0
    else:
        res['timing_met'] = 'not_parsed'
    return res


def environment():
    env = {'python': platform.python_version(), 'platform': platform.platform()}
    try:
        import pynq
        env['pynq'] = getattr(pynq, '__version__', 'unknown')
    except Exception:
        env['pynq'] = 'not_installed'
    return env


def build_report(*, title, results=(), timings=(), utilization=None, timing=None, artifacts=None, notes=()):
    for t in timings:
        if t.get('evidence') not in EVIDENCE:
            raise ValueError('timing %r lacks evidence class %s' % (t.get('label'), EVIDENCE))
    passed = sum(1 for r in results if r['ok'])
    data = {'title': title, 'environment': environment(), 'artifacts': artifacts,
            'golden': {'passed': passed, 'total': len(results), 'cases': list(results)},
            'timings': list(timings), 'utilization': utilization, 'timing': timing, 'notes': list(notes)}
    md = ['# %s' % title, '', '## Environment', '']
    md += ['- %s: %s' % kv for kv in data['environment'].items()]
    if artifacts:
        md += ['', '## Artifacts', ''] + ['- `%s` sha256 `%s`' % kv for kv in artifacts.get('sha256', {}).items()]
    md += ['', '## Golden comparison: %d/%d passed' % (passed, len(results)), '',
           '| case | ok | detail |', '|---|---|---|']
    md += ['| %s | %s | %s |' % (r['name'], 'PASS' if r['ok'] else 'FAIL', r['summary']) for r in results]
    md += ['', '## Timing (host)', '', '| label | evidence | n | cold us | min | median | p95 |', '|---|---|---|---|---|---|---|']
    md += ['| %s | %s | %d | %.1f | %.1f | %.1f | %.1f |' % (t['label'], t['evidence'], t['n'], t['cold'], t['min'],
                                                             t['median'], t['p95']) for t in timings]
    md += ['', '## Resources', '']
    if utilization:
        h = utilization['header']
        md += ['Source `%s` (%s, %s, state %s)' % (utilization['path'], h.get('design'), h.get('device'),
                                                   h.get('design_state')), '', '| resource | used | available | util% |',
               '|---|---|---|---|']
        md += ['| %s | %g | %s | %s |' % (k, v['used'], v['available'], v['util_pct']) for k, v in utilization['summary'].items()]
    else:
        md += ['not_measured']
    md += ['', '## Timing closure', '']
    if timing and timing.get('timing_met') != 'not_parsed':
        md += ['WNS %.3f ns, TNS %.3f ns, WHS %.3f ns, met=%s (`%s`)' % (
            timing['wns_ns'], timing['tns_ns'], timing['whs_ns'], timing['timing_met'], timing['path'])]
    else:
        md += ['not_measured']
    if notes:
        md += ['', '## Notes', ''] + ['- %s' % n for n in notes]
    return data, '\n'.join(md) + '\n'


def write_report(out_md, data, md):
    with open(out_md, 'w', encoding='utf-8') as f:
        f.write(md)
    with open(os.path.splitext(out_md)[0] + '.json', 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2, default=str)
