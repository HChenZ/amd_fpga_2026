"""Verify all packaged files without modifying them; Python standard library only."""
import hashlib
from pathlib import Path


def main():
    root = Path(__file__).resolve().parent
    expected = {}
    for line in (root / 'SHA256SUMS.txt').read_text(encoding='utf-8').splitlines():
        digest, name = line.split('  ', 1)
        path = (root / name).resolve()
        if not path.is_relative_to(root):
            raise SystemExit('Unsafe manifest path')
        expected[name] = digest
    actual = {p.relative_to(root).as_posix() for p in root.rglob('*') if p.is_file()
              and '.git' not in p.parts and '__pycache__' not in p.parts
              and p.name != 'SHA256SUMS.txt'}
    missing = sorted(set(expected) - actual)
    extra = sorted(actual - set(expected))
    bad = [name for name, digest in expected.items() if name in actual
           and hashlib.sha256((root / name).read_bytes()).hexdigest() != digest]
    print(f'{len(expected)} files; missing={len(missing)}, extra={len(extra)}, changed={len(bad)}')
    for name in missing + extra + bad:
        print(name)
    return int(bool(missing or extra or bad))


if __name__ == '__main__':
    raise SystemExit(main())
