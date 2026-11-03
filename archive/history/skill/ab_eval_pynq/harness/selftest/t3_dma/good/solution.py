import time

import numpy as np
from pynq import MMIO, allocate

CHUNK = 16380          # <= 2**c_sg_length_width - 1 and a multiple of the 4-byte bus width


def _poll(mmio, deadline):
    while True:
        tx, rx = mmio.read(0x04), mmio.read(0x34)
        if (tx | rx) & 0x70:
            raise RuntimeError('DMA error MM2S=0x%X S2MM=0x%X' % (tx, rx))
        if tx & 0x2 and rx & 0x2:
            return
        if time.monotonic() >= deadline:
            mmio.write(0x00, 0x4)       # reset both channels before giving buffers back
            raise TimeoutError('DMA did not complete (TLAST missing?) MM2S=0x%X S2MM=0x%X' % (tx, rx))


def transform(overlay, data, timeout_s=1.0):
    ip = overlay.ip_dict['axi_dma_0']
    mmio = MMIO(ip['phys_addr'], ip['addr_range'])     # avoid the driver's unbounded spins
    deadline = time.monotonic() + timeout_s
    out = bytearray()
    for i in range(0, len(data), CHUNK):
        chunk = data[i:i + CHUNK]
        tx = allocate(shape=(len(chunk),), dtype=np.uint8)
        rx = allocate(shape=(len(chunk),), dtype=np.uint8)
        tx[:] = np.frombuffer(chunk, dtype=np.uint8)
        rx[:] = 0xA5
        tx.flush()
        rx.flush()
        for base in (0x30, 0x00):
            mmio.write(base, 0x1)
            mmio.write(base + 0x04, 0x7000)
        for base, buf in ((0x30, rx), (0x00, tx)):
            mmio.write(base + 0x18, buf.physical_address & 0xFFFFFFFF)
            mmio.write(base + 0x1C, buf.physical_address >> 32)
            mmio.write(base + 0x28, len(chunk))
        _poll(mmio, deadline)
        got = mmio.read(0x58)
        rx.invalidate()
        out += bytes(rx[:got])
    return bytes(out)
