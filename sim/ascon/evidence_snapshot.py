"""Verify a retained implementation RTL snapshot against source files."""
import hashlib


def checked_rtl_snapshot(snapshot, source):
    if not snapshot.is_dir():
        raise ValueError('Implementation RTL snapshot is missing')
    expected = {p.relative_to(source).as_posix() for p in source.rglob('*')
                if p.is_file() and p.suffix in ('.v', '.vh')}
    hashes = {p.relative_to(snapshot).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
              for p in snapshot.rglob('*') if p.is_file() and p.suffix in ('.v', '.vh')}
    if not expected or set(hashes) != expected:
        raise ValueError('Implementation snapshot RTL file set is incomplete or unexpected')
    if not all(hashlib.sha256((source/name).read_bytes()).hexdigest() == value
               for name, value in hashes.items()):
        raise ValueError('RTL changed after implementation snapshot')
    return hashes
