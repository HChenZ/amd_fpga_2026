"""Stage A: prove that .bit and .hwh belong together before downloading anything."""
import hashlib
import json
import os

from . import PynqSkillError


class ArtifactError(PynqSkillError):
    pass


def sha256_file(path, chunk=1 << 20):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for block in iter(lambda: f.read(chunk), b''):
            h.update(block)
    return h.hexdigest()


def _load_manifest(manifest):
    if manifest is None or isinstance(manifest, dict):
        return manifest
    with open(manifest, encoding='utf-8') as f:
        return json.load(f)


def _manifest_entry(manifest, filename):
    """Accept {"artifacts": {"x.bit": {"sha256":..}}} or {"x.bit": "<sha256>"}."""
    table = manifest.get('artifacts', manifest)
    entry = table.get(filename)
    if isinstance(entry, str):
        return {'sha256': entry}
    return entry


def check_artifacts(bit_path, *, hwh_path=None, manifest=None, extra=()):
    """Return {'bit','hwh','sha256':{name:hash}} or raise ArtifactError listing every problem.

    PYNQ looks for <stem>.hwh next to <stem>.bit; a different hwh is a problem even if it
    exists, because Overlay() will silently use the sibling file instead.
    """
    problems = []
    bit_path = os.path.abspath(bit_path)
    sibling = os.path.splitext(bit_path)[0] + '.hwh'
    if hwh_path is None:
        hwh_path = sibling
    hwh_path = os.path.abspath(hwh_path)
    if os.path.normcase(hwh_path) != os.path.normcase(sibling):
        problems.append('hwh %s is not the sibling PYNQ will load (%s)' % (hwh_path, sibling))
    files = [bit_path, hwh_path] + [os.path.abspath(p) for p in extra]
    hashes = {}
    for path in files:
        if not os.path.isfile(path):
            problems.append('missing file: %s' % path)
            continue
        if os.path.getsize(path) == 0:
            problems.append('empty file: %s' % path)
        hashes[os.path.basename(path)] = sha256_file(path)
    manifest = _load_manifest(manifest)
    if manifest is not None:
        for path in files:
            name = os.path.basename(path)
            entry = _manifest_entry(manifest, name)
            if entry is None:
                problems.append('%s not listed in manifest' % name)
                continue
            if name in hashes and entry.get('sha256', '').lower() != hashes[name]:
                problems.append('%s sha256 %s != manifest %s' % (name, hashes[name], entry.get('sha256')))
            if 'bytes' in entry and os.path.isfile(path) and os.path.getsize(path) != entry['bytes']:
                problems.append('%s size %d != manifest %d' % (name, os.path.getsize(path), entry['bytes']))
    if problems:
        raise ArtifactError('artifact check failed', problems)
    return {'bit': bit_path, 'hwh': hwh_path, 'sha256': hashes}


def write_manifest(paths, out_path, **metadata):
    """Create a manifest binding artifacts produced by ONE implementation run."""
    data = dict(metadata)
    data['artifacts'] = {os.path.basename(p): {'bytes': os.path.getsize(p), 'sha256': sha256_file(p)}
                         for p in paths}
    with open(out_path, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2, sort_keys=True)
    return data
