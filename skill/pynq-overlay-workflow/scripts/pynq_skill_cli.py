#!/usr/bin/env python3
"""pynq-overlay-workflow command line: hwh | artifacts | gen | report. Exit 0 = pass, 1 = check failed."""
import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from pynq_skill import PynqSkillError, artifacts, hwh, regmap, report  # noqa: E402


def cmd_hwh(a):
    info = hwh.parse_hwh(a.hwh)
    if a.json:
        print(json.dumps({'ps': info['ps'], 'clocks': info['clocks'], 'ps_ref_clk_mhz': info['ps_ref_clk_mhz'],
                          'ips': {k: {x: v[x] for x in ('phys_addr', 'addr_range', 'vlnv')}
                                  for k, v in info['ips'].items()}}, indent=2))
    else:
        print('\n'.join(hwh.summary_lines(info)))
    if a.contract:
        c = regmap.load_contract(a.contract)
        ip = info['ips'].get(a.ip)
        if ip is None:
            print('IP %r not in hwh' % a.ip)
            return 1
        problems = regmap.cross_check_hwh(c, ip['registers'])
        print('\n'.join(['cross-check:'] + problems) if problems else 'cross-check: contract matches hwh registers')
    return 0


def cmd_artifacts(a):
    res = artifacts.check_artifacts(a.bit, hwh_path=a.hwh, manifest=a.manifest)
    print(json.dumps(res, indent=2))
    return 0


def cmd_gen(a):
    c = regmap.load_contract(a.contract)
    os.makedirs(a.out, exist_ok=True)
    mod = '%s_driver' % c['name']
    drv = os.path.join(a.out, mod + '.py')
    tst = os.path.join(a.out, 'test_%s.py' % mod)
    with open(drv, 'w', encoding='utf-8') as f:
        f.write(regmap.generate_driver(c))
    with open(tst, 'w', encoding='utf-8') as f:
        f.write(regmap.generate_test_skeleton(c, mod))
    print('wrote %s\nwrote %s' % (drv, tst))
    return 0


def cmd_report(a):
    results = []
    timings = []
    if a.results:
        with open(a.results, encoding='utf-8') as f:
            raw = json.load(f)
        results, timings = raw.get('golden', []), raw.get('timings', [])
    util = report.parse_utilization(a.utilization) if a.utilization else None
    timing = report.parse_timing_summary(a.timing) if a.timing else None
    data, md = report.build_report(title=a.title, results=results, timings=timings, utilization=util, timing=timing)
    report.write_report(a.out, data, md)
    print('wrote %s (+ .json)' % a.out)
    return 0 if all(r['ok'] for r in results) else 1


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest='cmd', required=True)
    s = sub.add_parser('hwh', help='list IPs/addresses/clocks; optionally cross-check a contract')
    s.add_argument('hwh')
    s.add_argument('--json', action='store_true')
    s.add_argument('--contract')
    s.add_argument('--ip')
    s.set_defaults(fn=cmd_hwh)
    s = sub.add_parser('artifacts', help='bit/hwh pairing + manifest hash check')
    s.add_argument('bit')
    s.add_argument('--hwh')
    s.add_argument('--manifest')
    s.set_defaults(fn=cmd_artifacts)
    s = sub.add_parser('gen', help='contract -> driver + pytest skeleton')
    s.add_argument('contract')
    s.add_argument('-o', '--out', required=True)
    s.set_defaults(fn=cmd_gen)
    s = sub.add_parser('report', help='golden/timing JSON + Vivado reports -> Markdown/JSON')
    s.add_argument('--results')
    s.add_argument('--utilization')
    s.add_argument('--timing')
    s.add_argument('--title', default='PYNQ overlay report')
    s.add_argument('-o', '--out', required=True)
    s.set_defaults(fn=cmd_report)
    a = p.parse_args(argv)
    try:
        return a.fn(a)
    except PynqSkillError as e:
        print('FAIL: %s' % e, file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
