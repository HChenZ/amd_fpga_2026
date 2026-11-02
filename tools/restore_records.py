"""Restore immutable archived records into ignored local paths; never overwrite differing bytes."""
import hashlib
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]
ARCHIVE = ROOT / 'archive/evidence/raw_records_20261102.zip'


def main():
    restored = kept = 0
    with zipfile.ZipFile(ARCHIVE) as z:
        for info in z.infolist():
            name = info.filename
            if name.endswith('/') or name.endswith('SHA256SUMS.txt'):
                continue
            # report/llm_collab/sessions/ is tracked in the repository since 2026-11-02 (render-safe copy);
            # its byte-exact originals stay in this archive and are not restored over the tracked files.
            if not name.startswith(('data/', 'build/')):
                continue
            target = (ROOT / name).resolve()
            if not target.is_relative_to(ROOT):
                raise SystemExit('Unsafe archive path')
            body = z.read(info)
            if target.exists():
                if hashlib.sha256(target.read_bytes()).digest() != hashlib.sha256(body).digest():
                    raise SystemExit('Refusing to overwrite different local record: ' + name)
                kept += 1
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(body)
            restored += 1
    print('Record copies restored:', restored, 'already identical:', kept)


if __name__ == '__main__':
    main()
