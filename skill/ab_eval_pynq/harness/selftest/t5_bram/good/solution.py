"""Reference (good) solution for the T5 hold-out task - instrument self-test only.

Written from Xilinx PG078 (AXI BRAM Controller: the whole window is BRAM, 32-bit accesses
only), not from any skill text.
"""
from pynq import MMIO

TARGET_VLNV = 'xilinx.com:ip:axi_bram_ctrl:4.1'


def _window(overlay):
    hits = [(name, d) for name, d in overlay.ip_dict.items() if d.get('type') == TARGET_VLNV]
    if not hits:
        raise RuntimeError('no AXI BRAM controller in this overlay')
    if len(hits) > 1:
        raise RuntimeError('ambiguous AXI BRAM controller: %s' % ', '.join(n for n, _ in hits))
    name, d = hits[0]
    base, size = int(d['phys_addr']), int(d['addr_range'])
    return MMIO(base, size, device=overlay.device), size


def _byte_write(mmio, offset, blob):
    i, n = 0, len(blob)
    while i < n:
        cur = offset + i
        word = cur & ~3
        shift = (cur & 3) * 8
        if shift == 0 and i + 4 <= n:
            mmio.write(word, int.from_bytes(blob[i:i + 4], 'little'))
            i += 4
            continue
        old = int(mmio.read(word))
        new = (old & ~(0xFF << shift) & 0xFFFFFFFF) | (blob[i] << shift)
        mmio.write(word, new)
        i += 1


def poke_block(overlay, offset, data):
    mmio, size = _window(overlay)
    blob = bytes(data)
    if offset < 0 or offset + len(blob) > size:
        raise ValueError('write of %d bytes at 0x%X does not fit in %d bytes'
                         % (len(blob), offset, size))
    _byte_write(mmio, offset, blob)


def peek_block(overlay, offset, length):
    mmio, size = _window(overlay)
    if offset < 0 or length < 0 or offset + length > size:
        raise ValueError('read of %d bytes at 0x%X does not fit in %d bytes' % (length, offset, size))
    out = bytearray()
    while len(out) + 4 <= length:
        word = offset + len(out)
        out += int(mmio.read(word)).to_bytes(4, 'little')
    while len(out) < length:
        word = (offset + len(out)) & ~3
        shift = ((offset + len(out)) & 3) * 8
        out.append((int(mmio.read(word)) >> shift) & 0xFF)
    return bytes(out)
