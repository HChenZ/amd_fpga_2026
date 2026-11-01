"""Small standard-library helpers for local, non-destructive board preparation."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
LOCAL = ROOT / 'build/local'


def local_output(path):
    path = Path(path).resolve()
    if not path.is_relative_to(LOCAL.resolve()) or path == LOCAL.resolve():
        raise ValueError('output must be a child of build/local')
    return path


def sha256(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def write_json(path, value):
    Path(path).write_text(json.dumps(value, indent=2, ensure_ascii=False) + '\n', encoding='utf-8', newline='\n')


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT).decode('utf-8', 'replace').strip()


def compiler_prefix(prefix):
    # An explicit native prefix works on every drive; otherwise prefer installed WSL GCC.
    if os.name == 'nt' and not Path(prefix + 'gcc').is_absolute() and not Path(prefix + 'gcc.exe').is_absolute():
        return ['wsl', '-d', os.environ.get('PREBOARD_WSL_DISTRO', 'Ubuntu'), '--']
    return []


def run(command, *, timeout=120, cwd=ROOT, log=None):
    start = time.monotonic()
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE='1', PYTHONUTF8='1')
    try:
        result = subprocess.run([str(x) for x in command], cwd=cwd, env=env,
                                capture_output=True, timeout=timeout)
        output = (result.stdout + result.stderr).decode('utf-8', 'replace').replace('\r\n', '\n')
        code, status = result.returncode, 'PASS' if result.returncode == 0 else 'FAIL'
    except FileNotFoundError as exc:
        output, code, status = str(exc), None, 'BLOCKED'
    except subprocess.TimeoutExpired as exc:
        output = ((exc.stdout or b'') + (exc.stderr or b'')).decode('utf-8', 'replace') + '\nTIMEOUT'
        code, status = None, 'FAIL'
    record = dict(command=[str(x) for x in command], cwd=str(cwd), exit_code=code,
                  status=status, elapsed_s=round(time.monotonic() - start, 3))
    if log:
        Path(log).write_text(json.dumps(record, ensure_ascii=False) + '\n' + output,
                             encoding='utf-8', newline='\n')
        record['log'] = str(log)
    return record, output


def python_command():
    return [sys.executable, '-B']
