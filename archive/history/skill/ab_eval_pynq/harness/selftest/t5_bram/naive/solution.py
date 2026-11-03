"""Naive solution for the T5 hold-out task - must fail on the designed traps.

Models the common shortcut: hardcoded base address, assumes a 4 KiB window, writes whole
32-bit words (so it clobbers the neighbouring bytes of an unaligned block), and has no
bounds check at all.
"""
from pynq import MMIO

BASE = 0x40000000
SIZE = 0x1000


def poke_block(overlay, offset, data):
    mmio = MMIO(BASE, SIZE)
    blob = bytes(data) + b'\x00' * (-len(data) % 4)      # pad to whole words
    for i in range(0, len(blob), 4):
        mmio.write(offset + i, int.from_bytes(blob[i:i + 4], 'little'))


def peek_block(overlay, offset, length):
    mmio = MMIO(BASE, SIZE)
    out = bytearray()
    for i in range(0, length + (-length % 4), 4):
        out += int(mmio.read(offset + i)).to_bytes(4, 'little')
    return bytes(out[:length])
