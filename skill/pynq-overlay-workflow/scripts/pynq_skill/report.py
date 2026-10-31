"""Collect Vivado utilization/timing reports and host results into one Markdown + JSON report.

Metrics are configurable through a schema (see references/report_schema.md): each metric names a
source (utilization / timing / json), a path inside it, an optional aggregation and an evidence
class. Anything that cannot be found is reported as `not_measured`, never silently dropped.
"""
import json
import os
import platform
import re
import statistics

from . import PynqSkillError
from .artifacts import sha256_file

# measured: observed on hardware; tool_report: number printed by Vivado (post-route utilization,
# static timing) - not a board measurement; simulated: fake/RTL model; estimated: computed from a
# stated basis; not_measured: missing.
EVIDENCE = ('measured', 'tool_report', 'simulated', 'estimated', 'not_measured')
SOURCE_KINDS = ('utilization', 'timing', 'json')
AGGREGATIONS = ('count', 'sum', 'min', 'max', 'mean', 'all_true')


class SchemaError(PynqSkillError):
    pass


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


def load_schema(src):
    """Load and validate a metric schema (path, JSON text or dict). Raises SchemaError."""
    if isinstance(src, dict):
        data = json.loads(json.dumps(src))
    elif str(src).lstrip().startswith('{'):
        data = json.loads(src)
    else:
        with open(src, encoding='utf-8') as f:
            data = json.load(f)
    problems = []
    sources = data.get('sources') or {}
    for name, s in sources.items():
        if s.get('kind') not in SOURCE_KINDS:
            problems.append('source %r: kind %r not in %s' % (name, s.get('kind'), SOURCE_KINDS))
        if s.get('evidence') not in EVIDENCE or s.get('evidence') == 'not_measured':
            problems.append('source %r: evidence %r must be one of %s (not not_measured)'
                            % (name, s.get('evidence'), EVIDENCE[:-1]))
    seen = set()
    for i, m in enumerate(data.get('metrics') or []):
        name = m.get('name')
        if not name:
            problems.append('metric #%d has no name' % i)
            continue
        if name in seen:
            problems.append('duplicate metric %r' % name)
        seen.add(name)
        constant = 'value' in m
        if constant == bool(m.get('source')):
            problems.append('%s: give exactly one of "source"+"path" or a constant "value"' % name)
        if m.get('source') and m['source'] not in sources:
            problems.append('%s: unknown source %r' % (name, m['source']))
        if m.get('source') and not m.get('path'):
            problems.append('%s: missing "path"' % name)
        if m.get('agg') is not None and m['agg'] not in AGGREGATIONS:
            problems.append('%s: agg %r not in %s' % (name, m['agg'], AGGREGATIONS))
        if '*' in str(m.get('path', '')) and m.get('agg') is None:
            problems.append('%s: wildcard path needs an "agg"' % name)
        ev = m.get('evidence')
        if ev is not None and ev not in EVIDENCE:
            problems.append('%s: evidence %r invalid' % (name, ev))
        if constant and ev is None:
            problems.append('%s: constant value needs an explicit evidence class' % name)
        if ev == 'estimated' and not m.get('basis'):
            problems.append('%s: estimated metric must state its "basis"' % name)
    if not seen:
        problems.append('schema has no metrics')
    if problems:
        raise SchemaError('invalid report schema %r' % data.get('title'), problems)
    data['_validated'] = True
    return data


def resolve_path(obj, path):
    """Dotted path; integer parts index lists; '*' fans out over list items / dict values."""
    items, fanned = [obj], False
    for part in path.split('.'):
        nxt = []
        for it in items:
            if part == '*':
                fanned = True
                nxt.extend(it if isinstance(it, list) else list(it.values()) if isinstance(it, dict) else [])
            elif isinstance(it, list):
                nxt.append(it[int(part)])
            elif isinstance(it, dict):
                nxt.append(it[part])
            else:
                raise KeyError(part)
        items = nxt
    return items if fanned else items[0]


def _aggregate(values, agg):
    if agg is None:
        return values
    vals = values if isinstance(values, list) else [values]
    if agg == 'count':
        return len(vals)
    if agg == 'all_true':
        return bool(vals) and all(v is True for v in vals)
    if not vals:
        raise KeyError('empty selection')
    nums = [float(v) for v in vals]
    return {'sum': sum, 'min': min, 'max': max, 'mean': statistics.mean}[agg](nums)


def _load_source(kind, path):
    if kind == 'utilization':
        return parse_utilization(path)
    if kind == 'timing':
        return parse_timing_summary(path)
    with open(path, encoding='utf-8') as f:
        data = json.load(f)
    return {'path': os.path.abspath(path), 'sha256': sha256_file(path), 'data': data}


def collect_metrics(schema, source_paths):
    """Evaluate every schema metric. Returns (records, problems).

    source_paths: {source_name: file path}. A source without a usable file makes all its
    metrics `not_measured`; a missing REQUIRED metric is also listed in problems.
    """
    schema = schema if schema.get('_validated') else load_schema(schema)
    loaded, load_err = {}, {}
    for name, spec in schema.get('sources', {}).items():
        path = (source_paths or {}).get(name)
        if not path or not os.path.isfile(path):
            load_err[name] = 'source file not provided' if not path else 'source file not found: %s' % path
            continue
        try:
            loaded[name] = _load_source(spec['kind'], path)
        except (OSError, ValueError) as e:
            load_err[name] = 'cannot parse source: %s' % e
    records, problems = [], []
    for m in schema['metrics']:
        rec = {'name': m['name'], 'unit': m.get('unit', ''), 'required': bool(m.get('required')),
               'source': m.get('source'), 'path': m.get('path'), 'agg': m.get('agg'),
               'basis': m.get('basis'), 'value': None, 'evidence': 'not_measured', 'status': 'missing',
               'note': '', 'source_file': None, 'source_sha256': None}
        if 'value' in m:
            rec.update(value=m['value'], evidence=m['evidence'], status='ok', note='constant')
        elif m['source'] in load_err:
            rec['note'] = load_err[m['source']]
        else:
            src = loaded[m['source']]
            rec.update(source_file=src['path'], source_sha256=src['sha256'])
            root = src['data'] if schema['sources'][m['source']]['kind'] == 'json' else src
            try:
                rec['value'] = _aggregate(resolve_path(root, m['path']), m.get('agg'))
                rec['evidence'] = m.get('evidence') or schema['sources'][m['source']]['evidence']
                rec['status'] = 'ok'
            except (KeyError, IndexError, ValueError, TypeError) as e:
                rec['note'] = 'path %r not found (%s)' % (m['path'], e)
        if rec['status'] != 'ok' and rec['required']:
            problems.append('required metric %r missing: %s' % (rec['name'], rec['note']))
        records.append(rec)
    return records, problems


def environment():
    env = {'python': platform.python_version(), 'platform': platform.platform()}
    try:
        import pynq
        env['pynq'] = getattr(pynq, '__version__', 'unknown')
    except Exception:
        env['pynq'] = 'not_installed'
    return env


def _fmt(v):
    if v is None:
        return '-'
    if isinstance(v, float):
        return '%g' % v
    return str(v)


def build_report(*, title, results=(), timings=(), utilization=None, timing=None, artifacts=None, notes=(),
                 metrics=(), problems=()):
    for t in timings:
        if t.get('evidence') not in EVIDENCE:
            raise ValueError('timing %r lacks evidence class %s' % (t.get('label'), EVIDENCE))
    passed = sum(1 for r in results if r['ok'])
    data = {'title': title, 'environment': environment(), 'artifacts': artifacts,
            'golden': {'passed': passed, 'total': len(results), 'cases': list(results)},
            'timings': list(timings), 'utilization': utilization, 'timing': timing, 'notes': list(notes),
            'metrics': list(metrics), 'problems': list(problems)}
    md = ['# %s' % title, '', '## Environment', '']
    md += ['- %s: %s' % kv for kv in data['environment'].items()]
    if artifacts:
        md += ['', '## Artifacts', ''] + ['- `%s` sha256 `%s`' % kv for kv in artifacts.get('sha256', {}).items()]
    if metrics:
        missing = sum(1 for m in metrics if m['status'] != 'ok')
        md += ['', '## Metrics (%d configured, %d not_measured)' % (len(metrics), missing), '',
               '| metric | value | unit | evidence | source | note |', '|---|---|---|---|---|---|']
        for m in metrics:
            src = '%s:`%s`' % (m['source'], m['path']) if m['source'] else 'constant'
            note = m['note'] if m['status'] != 'ok' else (('basis: ' + m['basis']) if m.get('basis') else '')
            md.append('| %s%s | %s | %s | %s | %s | %s |' % (m['name'], ' *' if m['required'] else '', _fmt(m['value']),
                                                         m['unit'], m['evidence'], src, note))
        files = sorted({'`%s` (sha256 %s...)' % (os.path.basename(m['source_file']), m['source_sha256'][:12])
                        for m in metrics if m['source_file']})
        md += ['', '`*` = required. Source files: ' + (', '.join(files) or 'none')]
    # With a metric schema, the fixed sections below are only printed when data was supplied for them,
    # so an empty legacy section never contradicts the Metrics table.
    legacy = not metrics
    if results or legacy:
        md += ['', '## Golden comparison: %d/%d passed' % (passed, len(results)), '',
               '| case | ok | detail |', '|---|---|---|']
        md += ['| %s | %s | %s |' % (r['name'], 'PASS' if r['ok'] else 'FAIL', r['summary']) for r in results]
    if timings or legacy:
        md += ['', '## Timing (host)', '', '| label | evidence | n | cold us | min | median | p95 |',
               '|---|---|---|---|---|---|---|']
        md += ['| %s | %s | %d | %.1f | %.1f | %.1f | %.1f |' % (t['label'], t['evidence'], t['n'], t['cold'], t['min'],
                                                                 t['median'], t['p95']) for t in timings]
    if utilization or legacy:
        md += ['', '## Resources', '']
    if utilization:
        h = utilization['header']
        md += ['Source `%s` (%s, %s, state %s)' % (utilization['path'], h.get('design'), h.get('device'),
                                                   h.get('design_state')), '', '| resource | used | available | util% |',
               '|---|---|---|---|']
        md += ['| %s | %g | %s | %s |' % (k, v['used'], v['available'], v['util_pct']) for k, v in utilization['summary'].items()]
    elif legacy:
        md += ['not_measured']
    if timing or legacy:
        md += ['', '## Timing closure', '']
        if timing and timing.get('timing_met') != 'not_parsed':
            md += ['WNS %.3f ns, TNS %.3f ns, WHS %.3f ns, met=%s (`%s`)' % (
                timing['wns_ns'], timing['tns_ns'], timing['whs_ns'], timing['timing_met'], timing['path'])]
        else:
            md += ['not_measured']
    if problems:
        md += ['', '## Problems', ''] + ['- %s' % p for p in problems]
    if notes:
        md += ['', '## Notes', ''] + ['- %s' % n for n in notes]
    return data, '\n'.join(md) + '\n'


def write_report(out_md, data, md):
    with open(out_md, 'w', encoding='utf-8') as f:
        f.write(md)
    with open(os.path.splitext(out_md)[0] + '.json', 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2, default=str)
