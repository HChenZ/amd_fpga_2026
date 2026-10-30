#!/usr/bin/env python3
"""Layer-1 check: each deliberate bug injected into a temp copy of the skill's tools must make
its offline test-suite FAIL. A suite that stays green under a mutation is too weak to trust."""
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SKILL = os.path.normpath(os.path.join(HERE, '..', '..', 'pynq-overlay-workflow'))

MUTATIONS = [
    ('dma: drop rx.invalidate()', 'scripts/pynq_skill/dma.py', '            rx.invalidate()     # DDR', '            pass  # DDR'),
    ('dma: drop tx.flush()', 'scripts/pynq_skill/dma.py', '            tx.flush()          # CPU', '            pass  # CPU'),
    ('dma: use requested length', 'scripts/pynq_skill/dma.py', 'received = self.mmio.read(S2MM + LENGTH)', 'received = rx_len'),
    ('dma: no quarantine', 'scripts/pynq_skill/dma.py', '            self.retained.extend(buffers)', '            pass'),
    ('dma: send before receive', 'scripts/pynq_skill/dma.py', '((S2MM, rx_addr, rx_len), (MM2S, tx_addr, tx_len))', '((MM2S, tx_addr, tx_len), (S2MM, rx_addr, rx_len))'),
    # (removing only the idle loop is an equivalent mutant: the first snapshot() already consumes stale done)
    ('hls: start without reading CTRL', 'scripts/pynq_skill/hls_ctrl.py', '    v = snapshot()\n    while not v & AP_IDLE:',
     '    v = AP_IDLE\n    while not v & AP_IDLE:'),
    ('hls: unbounded completion wait', 'scripts/pynq_skill/hls_ctrl.py',
     "        if clock() >= deadline:\n            raise KernelTimeout('kernel did not complete",
     "        if False:\n            raise KernelTimeout('kernel did not complete"),
    ('regmap: allow RMW on rc', 'scripts/pynq_skill/regmap.py', "any(\n                f['access'] in ('rc', 'w1c')", "False and any(\n                f['access'] in ('rc', 'w1c')"),
    ('regmap: pair writes lo only', 'scripts/pynq_skill/regmap.py', '        self.write(hi, value >> 32)\n', '\n'),
    ('regmap: allow overlap', 'scripts/pynq_skill/regmap.py', "        if off in used:", "        if False:"),
    ('artifacts: skip sibling rule', 'scripts/pynq_skill/artifacts.py', 'if os.path.normcase(hwh_path) != os.path.normcase(sibling):', 'if False:'),
    ('overlay: skip hwh address compare', 'scripts/pynq_skill/overlay_check.py', "if ip.get('phys_addr') != ref['phys_addr']", "if False and ip.get('phys_addr') != ref['phys_addr']"),
    ('golden: no sentinel hint', 'scripts/pynq_skill/golden.py', "        return 'all_sentinel'", "        return 'scattered'"),
]


def run_suite(root, timeout_s=120):
    """Return code; a hang (e.g. mutant removed a deadline) counts as detected (-1)."""
    try:
        return subprocess.run([sys.executable, '-m', 'pytest', '-q', '-x', '-p', 'no:cacheprovider',
                               os.path.join(root, 'tests')], capture_output=True, text=True, cwd=root,
                              timeout=timeout_s).returncode
    except subprocess.TimeoutExpired:
        return -1


def main():
    killed = 0
    with tempfile.TemporaryDirectory() as tmp:
        base = os.path.join(tmp, 'pynq-overlay-workflow')
        shutil.copytree(SKILL, base, ignore=shutil.ignore_patterns('__pycache__'))
        assert run_suite(base) == 0, 'unmutated suite must pass first'
        for name, rel, old, new in MUTATIONS:
            work = os.path.join(tmp, 'm')
            shutil.rmtree(work, ignore_errors=True)
            shutil.copytree(base, work)
            path = os.path.join(work, rel)
            with open(path, encoding='utf-8') as f:
                src = f.read()
            if src.count(old) != 1:
                print('SKIP (pattern not unique/found): %s' % name)
                continue
            with open(path, 'w', encoding='utf-8') as f:
                f.write(src.replace(old, new))
            rc = run_suite(work)
            killed += rc != 0
            print('%-36s %s' % (name, 'KILLED' if rc else 'SURVIVED  <-- tests too weak'))
    print('killed %d/%d mutations' % (killed, len(MUTATIONS)))
    return 0 if killed == len(MUTATIONS) else 1


if __name__ == '__main__':
    sys.exit(main())
