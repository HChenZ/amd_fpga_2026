#!/usr/bin/env python3
"""Grade trial outputs against hidden scenarios on the fake PYNQ. Deterministic; no LLM judge.

Usage: grade.py --root <trials root> [--out results.csv]
       grade.py --solution <dir-with-solution.py> --task t3_dma     (grade one directory)
"""
import argparse
import csv
import json
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import tasks  # noqa: E402

FAKE = os.path.join(HERE, 'fake_pynq')
DRIVER = r'''
import sys, json
sys.path[:0] = {paths!r}
import pynq
result = {{'ok': False}}
try:
    import solution
{code}
except BaseException as e:
    result['ok'] = False
    result['why'] = '%s: %s' % (type(e).__name__, str(e)[:300])
with open({out!r}, 'w') as f:
    json.dump(result, f)
'''


def run_scenario(sol_dir, sc, tmp, timeout_s, extra_paths=()):
    scen = os.path.join(tmp, sc['name'] + '.scenario.json')
    out = os.path.join(tmp, sc['name'] + '.result.json')
    trace = os.path.join(tmp, sc['name'] + '.trace.json')
    with open(scen, 'w') as f:
        json.dump({'hardware': sc['hardware']}, f)
    code = '\n'.join('    ' + line for line in sc['code'].strip('\n').splitlines())
    script = DRIVER.format(paths=[FAKE, sol_dir] + list(extra_paths), code=code, out=out)
    env = dict(os.environ, FAKE_PYNQ_SCENARIO=scen, FAKE_PYNQ_TRACE=trace, PYTHONDONTWRITEBYTECODE='1')
    env.pop('PYTHONPATH', None)
    try:
        subprocess.run([sys.executable, '-c', script], cwd=sol_dir, env=env, timeout=timeout_s,
                       capture_output=True, text=True)
    except subprocess.TimeoutExpired:
        return 'hang', 'killed after %ss (unbounded wait?)' % timeout_s
    if not os.path.exists(out):
        return 'error', 'no result written'
    with open(out) as f:
        r = json.load(f)
    return ('pass' if r.get('ok') else 'fail'), r.get('why', '')


def grade_code(task, sol_dir, timeout_s=20):
    spec = tasks.TASKS[task]
    if not os.path.isfile(os.path.join(sol_dir, 'solution.py')):
        return [{'scenario': '*', 'outcome': 'missing', 'why': 'no solution.py'}]
    extra = []
    lib = os.path.join(sol_dir, '.opencode', 'skills', 'pynq-overlay-workflow', 'scripts')
    if os.path.isdir(lib):
        extra.append(lib)   # the with-arm may legitimately import the skill's helper library
    rows = []
    with tempfile.TemporaryDirectory() as tmp:
        for sc in spec['scenarios'](tmp):
            outcome, why = run_scenario(sol_dir, sc, tmp, timeout_s, extra)
            rows.append({'scenario': sc['name'], 'outcome': outcome, 'why': why})
    return rows


def grade_text(task, sol_dir):
    path = os.path.join(sol_dir, tasks.TASKS[task]['artifact'])
    if not os.path.isfile(path):
        return [{'scenario': '*', 'outcome': 'missing', 'why': 'no answers.md'}]
    with open(path, encoding='utf-8', errors='replace') as f:
        text = f.read()
    parts = re.split(r'(?m)^\s*#+\s*(Q\d+)\b', text)
    answers = {parts[i].upper(): parts[i + 1] for i in range(1, len(parts) - 1, 2)}
    rows = []
    for q, patterns in tasks.TASKS[task]['rubric'].items():
        ans = answers.get(q, '')
        miss = [pat for pat in patterns if not re.search(pat, ans)]
        rows.append({'scenario': q, 'outcome': 'pass' if ans and not miss else 'fail',
                     'why': 'missing concept %s' % miss if miss else ''})
    return rows


def trial_meta(sol_dir, task):
    meta = {'canary': '', 'uses_skill_lib': False, 'exit': ''}
    art = os.path.join(sol_dir, tasks.TASKS[task]['artifact'])
    if os.path.isfile(art):
        with open(art, encoding='utf-8', errors='replace') as f:
            text = f.read()
        m = re.search(r'skill-canary:\s*([\w-]+)', text)
        meta['canary'] = m.group(1) if m else ''
        meta['uses_skill_lib'] = 'pynq_skill' in text
    ec = os.path.join(sol_dir, 'exit_code.txt')
    if os.path.isfile(ec):
        with open(ec, encoding='utf-8-sig', errors='replace') as f:
            meta['exit'] = f.read().strip()
    return meta


def grade_dir(task, sol_dir):
    return grade_text(task, sol_dir) if 'rubric' in tasks.TASKS[task] else grade_code(task, sol_dir)


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--root')
    p.add_argument('--solution')
    p.add_argument('--task')
    p.add_argument('--out', default=None)
    a = p.parse_args(argv)
    if a.solution:
        rows = grade_dir(a.task, os.path.abspath(a.solution))
        for r in rows:
            print('%-28s %-7s %s' % (r['scenario'], r['outcome'], r['why']))
        passed = sum(r['outcome'] == 'pass' for r in rows)
        print('score %d/%d' % (passed, len(rows)))
        return 0
    out = a.out or os.path.join(a.root, 'results.csv')
    fields = ['task', 'arm', 'rep', 'scenario', 'outcome', 'why', 'canary', 'uses_skill_lib', 'exit']
    with open(out, 'w', newline='', encoding='utf-8') as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        for task in sorted(os.listdir(a.root)):
            if task not in tasks.TASKS:
                continue
            for arm in sorted(os.listdir(os.path.join(a.root, task))):
                for rep in sorted(os.listdir(os.path.join(a.root, task, arm))):
                    d = os.path.join(a.root, task, arm, rep)
                    meta = trial_meta(d, task)
                    for r in grade_dir(task, d):
                        w.writerow(dict(r, task=task, arm=arm, rep=rep, **meta))
                    print('graded', task, arm, rep)
    print('wrote', out)
    return 0


if __name__ == '__main__':
    sys.exit(main())
