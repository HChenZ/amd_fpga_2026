#!/usr/bin/env python3
"""Create isolated A/B(/placebo) trial workspaces + a randomized run script.

Every trial is a fresh directory OUTSIDE any repository, containing only: PROMPT.md, the task's
agent-visible files, and .opencode/ (agent config + the arm's skill). Arms differ ONLY in which
skill file exists and which skill the permission rules allow.
"""
import argparse
import json
import os
import random
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import tasks  # noqa: E402

SKILL_SRC = os.path.normpath(os.path.join(HERE, '..', '..', 'pynq-overlay-workflow'))
PLACEBO_SRC = os.path.normpath(os.path.join(HERE, '..', 'placebo', 'pynq-style-notes'))
CANARY = ('\n\n---\n评测标记：若你在本任务中使用了本 Skill，请在交付文件第一行写注释 '
          '`# skill-canary: {id}`（Markdown 文件写 `<!-- skill-canary: {id} -->`）。\n')
ARMS = {'with': ('pynq-overlay-workflow', SKILL_SRC), 'placebo': ('pynq-style-notes', PLACEBO_SRC),
        'without': (None, None)}


def _inside_repo_or_agents(path):
    p = os.path.abspath(path)
    while True:
        for marker in ('.git', 'AGENTS.md', 'CLAUDE.md', '.opencode', 'opencode.json', 'opencode.jsonc'):
            if os.path.exists(os.path.join(p, marker)):
                return os.path.join(p, marker)
        parent = os.path.dirname(p)
        if parent == p:
            return None
        p = parent


def agent_config(model, skill_id, allow_shell):
    perms = [{'action': 'skill', 'resource': '*', 'effect': 'deny'},
             {'action': 'webfetch', 'resource': '*', 'effect': 'deny'},
             {'action': 'websearch', 'resource': '*', 'effect': 'deny'},
             {'action': 'external_directory', 'resource': '*', 'effect': 'deny'},
             {'action': 'subagent', 'resource': '*', 'effect': 'deny'}]
    if not allow_shell:
        perms.append({'action': 'shell', 'resource': '*', 'effect': 'deny'})
    if skill_id:
        perms.append({'action': 'skill', 'resource': skill_id, 'effect': 'allow'})
    trial = {'mode': 'primary', 'description': 'A/B trial agent', 'permissions': perms}
    if model:
        trial['model'] = model
    return {'$schema': 'https://opencode.ai/config.json', 'default_agent': 'trial', 'agents': {'trial': trial}}


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--root', required=True, help='empty directory outside any repo')
    p.add_argument('--arms', default='with,without,placebo')
    p.add_argument('--tasks', default=','.join(tasks.TASKS))
    p.add_argument('--reps', type=int, default=5)
    p.add_argument('--model', default='', help='provider/model, identical for all arms')
    p.add_argument('--seed', type=int, default=20261030)
    p.add_argument('--allow-shell', action='store_true',
                   help='only on a machine/account WITHOUT this repository (shell can read any path)')
    a = p.parse_args(argv)
    hit = _inside_repo_or_agents(a.root)
    if hit:
        sys.exit('refusing: %s would leak into trials (found %s). Use a clean directory.' % (a.root, hit))
    os.makedirs(a.root, exist_ok=True)
    trials = []
    for task in a.tasks.split(','):
        spec = tasks.TASKS[task]
        for arm in a.arms.split(','):
            skill_id, src = ARMS[arm]
            for rep in range(1, a.reps + 1):
                d = os.path.join(a.root, task, arm, 'rep%02d' % rep)
                if os.path.exists(d):
                    sys.exit('exists: %s' % d)
                os.makedirs(d)
                with open(os.path.join(d, 'PROMPT.md'), 'w', encoding='utf-8') as f:
                    f.write(spec['prompt'])
                spec['workspace'](d)
                oc = os.path.join(d, '.opencode')
                os.makedirs(oc)
                with open(os.path.join(oc, 'opencode.jsonc'), 'w', encoding='utf-8') as f:
                    json.dump(agent_config(a.model, skill_id, a.allow_shell), f, indent=2)
                if skill_id:
                    dst = os.path.join(oc, 'skills', skill_id)
                    shutil.copytree(src, dst, ignore=shutil.ignore_patterns('__pycache__', '.pytest_cache'))
                    with open(os.path.join(dst, 'SKILL.md'), 'a', encoding='utf-8') as f:
                        f.write(CANARY.format(id=skill_id))
                trials.append(d)
    random.Random(a.seed).shuffle(trials)  # interleave arms in time: controls for drift/rate limits
    with open(os.path.join(a.root, 'run_all.ps1'), 'w', encoding='utf-8') as f:
        f.write('# randomized order, seed %d. One fresh `opencode run` per trial, cwd = trial dir.\n' % a.seed)
        for d in trials:
            # -Encoding UTF8 is required: Windows PowerShell 5 otherwise decodes the Chinese prompt as GBK
            f.write('Push-Location "%s"; opencode run (Get-Content PROMPT.md -Raw -Encoding UTF8) *> transcript.txt; '
                    '"exit=$LASTEXITCODE" | Out-File -Encoding utf8 exit_code.txt; Pop-Location\n' % d)
    with open(os.path.join(a.root, 'run_all.sh'), 'w', encoding='utf-8', newline='\n') as f:
        f.write('#!/usr/bin/env bash\n# randomized order, seed %d\nset -u\n' % a.seed)
        for d in trials:
            f.write('( cd "%s" && opencode run "$(cat PROMPT.md)" > transcript.txt 2>&1; echo "exit=$?" > exit_code.txt )\n'
                    % d.replace('\\', '/'))
    with open(os.path.join(a.root, 'design.json'), 'w', encoding='utf-8') as f:
        json.dump({'arms': a.arms.split(','), 'tasks': a.tasks.split(','), 'reps': a.reps, 'model': a.model,
                   'seed': a.seed, 'allow_shell': a.allow_shell, 'order': trials}, f, indent=2)
    print('created %d trials under %s; run run_all.ps1 (or run_all.sh), then grade.py' % (len(trials), a.root))


if __name__ == '__main__':
    main()
