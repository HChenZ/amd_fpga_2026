import hashlib
import json
import os

from pynq import Overlay


def load_accel(bit_path, manifest_path):
    files = json.load(open(manifest_path))['files']
    if hashlib.sha256(open(bit_path, 'rb').read()).hexdigest() != files[os.path.basename(bit_path)]:
        raise RuntimeError('bit hash mismatch')
    ol = Overlay(bit_path)
    ip = ol.accel_0
    if ip.read(0x1C) != 0xACCE1001:
        raise RuntimeError('bad id')
    return ol, ip.mmio
