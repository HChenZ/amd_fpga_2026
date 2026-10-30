"""Stage D: bounded AXI DMA (PG021 simple mode) over raw MMIO, with cache maintenance.

Why not pynq.lib.dma: in PYNQ 2.x `_SDMAChannel.start()/stop()/wait()` spin without a
timeout, and the driver constructor calls start(). This adapter never spins unbounded,
decodes DMASR on failure, and refuses to release buffers until the DMA is proven halted.
Buffers must expose physical_address, nbytes, flush(), invalidate() (pynq.allocate does).
"""
import time

from . import PynqSkillError

MM2S, S2MM = 0x00, 0x30
CR, SR, ADDR, ADDR_MSB, LENGTH = 0x00, 0x04, 0x18, 0x1C, 0x28
CR_RS, CR_RESET = 0x1, 0x4
SR_HALTED, SR_IDLE, SR_SG = 0x1, 0x2, 0x8
SR_IRQ_ALL = 0x7000
SR_ERRORS = 0x770
_SR_BITS = [(0, 'Halted'), (1, 'Idle'), (3, 'SGIncld'), (4, 'DMAIntErr: length 0 or S2MM buffer shorter than packet'),
            (5, 'DMASlvErr: slave error on memory access (bad/freed physical address, port not enabled)'),
            (6, 'DMADecErr: address decode error (address not mapped)'), (8, 'SGIntErr'), (9, 'SGSlvErr'),
            (10, 'SGDecErr'), (12, 'IOC_Irq'), (13, 'Dly_Irq'), (14, 'Err_Irq')]


class DMAError(PynqSkillError):
    pass


class DMAQuarantine(DMAError):
    """DMA could not be proven halted; buffers are retained and must not be freed."""


def decode_dmasr(value):
    return [text for bit, text in _SR_BITS if value >> bit & 1]


def config_from_hwh(parameters):
    """Derive limits from the IP parameters in hwh / ip_dict[...]['parameters']."""
    def num(name, default=None):
        v = parameters.get(name, default)
        if v is None:
            raise DMAError('missing DMA parameter %s' % name)
        v = str(v)
        return int(v, 16) if v.lower().startswith('0x') else int(v)
    if num('c_include_sg', 0) or num('c_micro_dma', 0):
        raise DMAError('scatter-gather/micro DMA not supported; only simple mode is handled by this adapter')
    cfg = {'max_transfer': (1 << num('c_sg_length_width', 14)) - 1, 'align': {}}
    for base, ch in ((MM2S, 'mm2s'), (S2MM, 's2mm')):
        if num('c_include_' + ch, 1):
            width = num('c_m_axi_%s_data_width' % ch, 32)
            cfg['align'][base] = 1 if num('c_include_%s_dre' % ch, 0) else width // 8
    return cfg


class BoundedSimpleDMA:
    def __init__(self, mmio, *, max_transfer=16383, align=None, clock=time.monotonic, sleep=time.sleep,
                 poll_s=0.0002):
        self.mmio, self.clock, self.sleep, self.poll_s = mmio, clock, sleep, poll_s
        self.max_transfer = max_transfer
        self.align = align or {MM2S: 4, S2MM: 4}
        self.retained = []
        self.last_status = {}

    @classmethod
    def from_parameters(cls, mmio, parameters, **kw):
        cfg = config_from_hwh(parameters)
        return cls(mmio, max_transfer=cfg['max_transfer'], align=cfg['align'], **kw)

    def _sr(self, base):
        v = self.mmio.read(base + SR)
        self.last_status['mm2s' if base == MM2S else 's2mm'] = v
        return v

    def _wait(self, cond, deadline, what):
        while True:
            if cond():
                return
            if self.clock() >= deadline:
                raise DMAError('timeout waiting for %s; %s' % (what, self.status_text()))
            self.sleep(min(self.poll_s, max(0.0, deadline - self.clock())))

    def status_text(self):
        parts = []
        for base, name in ((MM2S, 'MM2S'), (S2MM, 'S2MM')):
            v = self.mmio.read(base + SR)
            parts.append('%s DMASR=0x%08X [%s]' % (name, v, ', '.join(decode_dmasr(v)) or 'running/busy'))
        return '; '.join(parts)

    def _check_buffer(self, base, buf, n):
        addr = int(buf.physical_address)
        if not 0 < n <= min(buf.nbytes, self.max_transfer):
            raise ValueError('length %d must be 1..min(buffer %d, max_transfer %d)' % (n, buf.nbytes, self.max_transfer))
        if addr % self.align[base]:
            raise ValueError('physical address 0x%X not aligned to %d (no DRE)' % (addr, self.align[base]))
        return addr

    def _start_channel(self, base, deadline):
        if self.mmio.read(base + SR) & SR_SG:
            raise DMAError('scatter-gather DMA is not supported by this adapter')
        self.mmio.write(base + CR, CR_RS)
        self._wait(lambda: not self._sr(base) & SR_HALTED, deadline, 'channel 0x%X to leave halt' % base)
        self.mmio.write(base + SR, SR_IRQ_ALL)  # W1C stale IOC/Dly/Err from a previous transfer

    def transfer(self, tx, rx, *, timeout_s=1.0, tx_len=None, rx_len=None):
        """Send tx (MM2S) and receive into rx (S2MM). Returns the ACTUAL received byte count."""
        if not timeout_s > 0:
            raise ValueError('finite positive timeout required')
        if self.retained:
            raise DMAQuarantine('previous failure not recovered; call recover() first')
        deadline = self.clock() + timeout_s
        tx_len = tx.nbytes if tx_len is None else tx_len
        rx_len = rx.nbytes if rx_len is None else rx_len
        tx_addr = self._check_buffer(MM2S, tx, tx_len)
        rx_addr = self._check_buffer(S2MM, rx, rx_len)
        started = False
        try:
            for base in (S2MM, MM2S):
                self._start_channel(base, deadline)
            tx.flush()          # CPU -> DDR before the device reads it
            rx.flush()          # write back dirty lines so a later eviction cannot overwrite DMA data
            started = True
            for base, addr, n in ((S2MM, rx_addr, rx_len), (MM2S, tx_addr, tx_len)):  # receive first
                self.mmio.write(base + ADDR, addr & 0xFFFFFFFF)
                self.mmio.write(base + ADDR_MSB, addr >> 32)
                self.mmio.write(base + LENGTH, n)

            def done():
                tx_sr, rx_sr = self._sr(MM2S), self._sr(S2MM)
                if (tx_sr | rx_sr) & SR_ERRORS:
                    raise DMAError('DMA error; ' + self.status_text())
                return all(sr & SR_IDLE and sr & 0x1000 for sr in (tx_sr, rx_sr))
            self._wait(done, deadline, 'transfer completion')
            received = self.mmio.read(S2MM + LENGTH)
            rx.invalidate()     # DDR -> CPU view after the device wrote it
            return received
        except BaseException:
            if started:
                self._abort((tx, rx))
            raise

    def _abort(self, buffers):
        deadline = self.clock() + 1.0
        try:
            self.mmio.write(MM2S + CR, CR_RESET)  # resets both channels
            self._wait(lambda: not self.mmio.read(MM2S + CR) & CR_RESET
                       and self.mmio.read(MM2S + SR) & SR_HALTED and self.mmio.read(S2MM + SR) & SR_HALTED,
                       deadline, 'reset/halt')
        except BaseException:
            self.retained.extend(buffers)  # keep references alive: DMA may still write them
            raise DMAQuarantine('DMA not proven halted; buffers retained. ' + self.status_text())

    def recover(self, timeout_s=1.0):
        deadline = self.clock() + timeout_s
        self.mmio.write(MM2S + CR, CR_RESET)
        self._wait(lambda: not self.mmio.read(MM2S + CR) & CR_RESET
                   and self.mmio.read(MM2S + SR) & SR_HALTED and self.mmio.read(S2MM + SR) & SR_HALTED,
                   deadline, 'reset/halt during recover')
        self.retained.clear()
