"""Execute an unchanged existing Python runner, redirecting only its evidence writes.

The historical CPU runners have no --report option. Path.open is scoped to this
child process; writes under data/ascon/results go to --evidence instead. Other
Python writes outside build/local are refused. No algorithm, test, or RTL changes.
"""
import argparse
import os
from pathlib import Path
import runpy
import sys
from unittest.mock import patch

from common import ROOT, LOCAL, local_output


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--evidence', required=True, type=Path)
    p.add_argument('script', choices=('run_cpu_regression.py','run_cpu_units.py','check_failure_contract.py'))
    p.add_argument('args', nargs=argparse.REMAINDER)
    a = p.parse_args()
    destination = local_output(a.evidence)
    destination.mkdir(parents=True, exist_ok=False)
    evidence_root = (ROOT/'data/ascon/results').resolve()
    original = Path.open

    def redirected(path, mode='r', *args, **kwargs):
        if any(flag in mode for flag in 'wax+'):
            absolute = path.resolve()
            if absolute.is_relative_to(evidence_root):
                path = destination/absolute.relative_to(evidence_root)
                path.parent.mkdir(parents=True, exist_ok=True)
            elif not absolute.is_relative_to(LOCAL.resolve()):
                raise PermissionError('runner attempted to write outside build/local')
        return original(path, mode, *args, **kwargs)

    os.chdir(ROOT)
    sys.dont_write_bytecode = True
    sys.path.insert(0, str(ROOT/'sim/ascon'))
    sys.argv = [a.script] + (a.args[1:] if a.args[:1] == ['--'] else a.args)
    print('Existing runner:', a.script, 'evidence redirected to:', destination, flush=True)
    with patch.object(Path, 'open', redirected):
        runpy.run_path(str(ROOT/'sim/ascon'/a.script), run_name='__main__')


if __name__ == '__main__':
    main()
