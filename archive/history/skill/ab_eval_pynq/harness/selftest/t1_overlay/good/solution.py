import hashlib
import json
import os

from pynq import MMIO, Overlay

VLNV = 'example.org:user:accel:1.0'


def _sha(path):
    with open(path, 'rb') as f:
        return hashlib.sha256(f.read()).hexdigest()


def load_accel(bit_path, manifest_path):
    with open(manifest_path, encoding='utf-8') as f:
        files = json.load(f)['files']
    hwh_path = os.path.splitext(bit_path)[0] + '.hwh'   # the file PYNQ will actually use
    for path in (bit_path, hwh_path):
        name = os.path.basename(path)
        if not os.path.isfile(path) or files.get(name) != _sha(path):
            raise RuntimeError('artifact %s missing or not in manifest' % name)
    ol = Overlay(bit_path)
    hits = [k for k, v in ol.ip_dict.items() if v.get('type') == VLNV]
    if len(hits) != 1:
        raise RuntimeError('expected exactly one %s, found %s' % (VLNV, hits))
    ip = ol.ip_dict[hits[0]]
    mmio = MMIO(ip['phys_addr'], ip['addr_range'])
    if mmio.read(0x1C) != 0xACCE1001:
        raise RuntimeError('identity mismatch')
    return ol, mmio
