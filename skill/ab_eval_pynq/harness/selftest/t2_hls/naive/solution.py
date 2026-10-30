import numpy as np
from pynq import allocate


def vadd(overlay, a, b, timeout_s=1.0):
    ip = overlay.vadd_0
    n = len(a)
    abuf = allocate(shape=(n,), dtype=np.int32)
    bbuf = allocate(shape=(n,), dtype=np.int32)
    cbuf = allocate(shape=(n,), dtype=np.int32)
    abuf[:] = a
    bbuf[:] = b
    ip.write(0x10, abuf.physical_address)
    ip.write(0x1C, bbuf.physical_address)
    ip.write(0x28, cbuf.physical_address)
    ip.write(0x34, n)
    ip.write(0x00, 1)
    while (ip.read(0x00) & 0x2) == 0:
        pass
    return np.array(cbuf)
