"""HLS ap_ctrl_hs start/complete with bounded wait and clear-on-read safety.

Bit positions follow the common Vitis HLS layout (bit0 start, bit1 done, bit2 idle,
bit3 ready, bit7 auto_restart). Confirm against the generated x<kernel>_hw.h.
"""
import time

from . import PynqSkillError

AP_START, AP_DONE, AP_IDLE, AP_READY, AUTO_RESTART = 0x1, 0x2, 0x4, 0x8, 0x80


class KernelTimeout(PynqSkillError):
    pass


def decode(value):
    return {'start': bool(value & AP_START), 'done': bool(value & AP_DONE), 'idle': bool(value & AP_IDLE),
            'ready': bool(value & AP_READY), 'auto_restart': bool(value & AUTO_RESTART)}


def run_once(mmio, *, ctrl_offset=0x00, timeout_s=1.0, clock=time.monotonic, sleep=time.sleep, poll_s=0.0001):
    """Wait idle -> start -> wait done. Each control read is decoded ONCE (ap_done may be
    clear-on-read), so a done observed while waiting for idle is not lost or misattributed."""
    deadline = clock() + timeout_s
    trace = []

    def snapshot():
        v = mmio.read(ctrl_offset)
        trace.append(v)
        return v

    v = snapshot()
    while not v & AP_IDLE:
        if clock() >= deadline:
            raise KernelTimeout('kernel never became idle before start; last CTRL=0x%X %s' % (v, decode(v)))
        sleep(poll_s)
        v = snapshot()
    mmio.write(ctrl_offset, AP_START)  # whole-register write: auto_restart stays 0
    while True:
        v = snapshot()
        if v & AP_DONE:
            return {'ctrl_trace': trace}
        if clock() >= deadline:
            raise KernelTimeout('kernel did not complete; last CTRL=0x%X %s (check m_axi addresses/'
                                'length args, clocks, or that done was not consumed elsewhere)' % (v, decode(v)))
        sleep(poll_s)
