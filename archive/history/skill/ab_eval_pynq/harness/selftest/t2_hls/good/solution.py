import time

import numpy as np
from pynq import allocate


def _deadline_check(deadline, what):
    if time.monotonic() >= deadline:
        raise TimeoutError(what)


def vadd(overlay, a, b, timeout_s=1.0):
    ip = overlay.vadd_0
    deadline = time.monotonic() + timeout_s
    n = len(a)
    bufs = [allocate(shape=(n,), dtype=np.int32) for _ in range(3)]
    abuf, bbuf, cbuf = bufs
    abuf[:] = a
    bbuf[:] = b
    cbuf[:] = 0
    for buf in bufs:
        buf.flush()
    while not ip.read(0x00) & 0x4:          # wait idle; reading also consumes a stale COR done
        _deadline_check(deadline, 'kernel not idle')
    for off, buf in ((0x10, abuf), (0x1C, bbuf), (0x28, cbuf)):
        ip.write(off, buf.physical_address & 0xFFFFFFFF)
        ip.write(off + 4, buf.physical_address >> 32)
    ip.write(0x34, n)
    ip.write(0x00, 0x1)
    while not ip.read(0x00) & 0x2:
        _deadline_check(deadline, 'kernel did not finish')
    cbuf.invalidate()
    return np.array(cbuf, dtype=np.int32)
