"""Offline stand-ins for MMIO, overlays, non-coherent buffers and an AXI DMA.

They model the failure modes host code must survive (stale cache views, missing TLAST,
slave errors, short packets, reset that never completes). Results obtained with fakes are
`simulated` evidence only - never report them as board measurements.
"""


class FakeMMIO:
    def __init__(self, addr_range=0x10000, *, on_read=None, on_write=None):
        self.addr_range = addr_range
        self.mem = {}
        self.on_read, self.on_write = on_read, on_write
        self.log = []

    def _check(self, offset):
        if offset % 4 or not 0 <= offset < self.addr_range:
            raise ValueError('MMIO offset 0x%X invalid (alignment/range 0x%X)' % (offset, self.addr_range))

    def read(self, offset, length=4):
        self._check(offset)
        value = self.mem.get(offset, 0)
        if self.on_read:
            value = self.on_read(offset, value)
        self.log.append(('r', offset, value))
        return value & 0xFFFFFFFF

    def write(self, offset, value):
        self._check(offset)
        self.log.append(('w', offset, value))
        if self.on_write and self.on_write(offset, value):
            return
        self.mem[offset] = value & 0xFFFFFFFF

    def peek(self, offset):
        return self.mem.get(offset, 0)

    def poke(self, offset, value):
        self.mem[offset] = value & 0xFFFFFFFF


class FakeOverlay:
    def __init__(self, ip_dict, loaded=True):
        self.ip_dict, self._loaded = ip_dict, loaded

    def is_loaded(self):
        return self._loaded


class FakeDDR:
    """Physical memory shared by 'CPU' buffers and the fake DMA."""

    def __init__(self, base=0x1000_0000, size=1 << 20):
        self.base, self.data, self.next = base, bytearray(size), base

    def alloc(self, n, align=64):
        self.next = (self.next + align - 1) // align * align
        addr, self.next = self.next, self.next + n
        if self.next > self.base + len(self.data):
            raise MemoryError('fake DDR exhausted')
        return addr

    def read(self, addr, n):
        o = addr - self.base
        if o < 0 or o + n > len(self.data):
            raise IndexError('address 0x%X+%d outside DDR' % (addr, n))
        return bytes(self.data[o:o + n])

    def write(self, addr, payload):
        o = addr - self.base
        if o < 0 or o + len(payload) > len(self.data):
            raise IndexError('address 0x%X+%d outside DDR' % (addr, len(payload)))
        self.data[o:o + len(payload)] = payload


class FakeBuffer:
    """Byte buffer with a separate CPU-cache view. coherent=False models a cacheable buffer:
    writes stay in the CPU view until flush(); DMA writes are invisible until invalidate()."""

    def __init__(self, ddr, nbytes, coherent=False, offset=0):
        self.ddr, self.coherent = ddr, coherent
        self.physical_address = ddr.alloc(nbytes) + offset
        self.nbytes = nbytes
        self.view = bytearray(ddr.read(self.physical_address, nbytes))
        self.freed = False
        self.flushes = self.invalidates = 0

    device_address = property(lambda self: self.physical_address)

    def _sync_in(self):
        if self.coherent:
            self.view[:] = self.ddr.read(self.physical_address, self.nbytes)

    def __len__(self):
        return self.nbytes

    def __getitem__(self, idx):
        self._sync_in()
        return self.view[idx]

    def __setitem__(self, idx, value):
        self._sync_in()
        if isinstance(idx, slice) and not isinstance(value, (bytes, bytearray)):
            value = bytes(value)
        self.view[idx] = value
        if self.coherent:
            self.ddr.write(self.physical_address, bytes(self.view))

    def __bytes__(self):
        self._sync_in()
        return bytes(self.view)

    def flush(self):
        self.flushes += 1
        self.ddr.write(self.physical_address, bytes(self.view))

    def invalidate(self):
        self.invalidates += 1
        self.view[:] = self.ddr.read(self.physical_address, self.nbytes)

    def freebuffer(self):
        self.freed = True


class FakeAllocator:
    def __init__(self, ddr=None, coherent=False):
        self.ddr, self.coherent, self.buffers = ddr or FakeDDR(), coherent, []

    def __call__(self, shape, dtype='u1', **kw):
        n = shape[0] if isinstance(shape, tuple) else shape
        size = {'u1': 1, 'u4': 4, 'uint8': 1, 'uint32': 4}.get(str(dtype), 1) * n
        buf = FakeBuffer(self.ddr, size, coherent=kw.get('coherent', self.coherent))
        self.buffers.append(buf)
        return buf


class FakeAxiDma(FakeMMIO):
    """Register-level AXI DMA (simple mode) moving bytes through FakeDDR.

    process(bytes)->bytes is the PL stream function (default loopback).
    fault: None | 'no_tlast' | 'slave_error' | 'short' | 'stuck_reset' | 'slow'
    """

    def __init__(self, ddr, process=None, fault=None, short_by=4, slow_polls=3):
        super().__init__(0x10000)
        self.ddr, self.process, self.fault = ddr, process or (lambda b: b), fault
        self.short_by, self.slow_polls = short_by, slow_polls
        self.mem.update({0x04: 0x1, 0x34: 0x1})  # both channels halted after reset
        self.armed = {}
        self.pending = None
        self.transfers = []

    def write(self, offset, value):
        self._check(offset)
        self.log.append(('w', offset, value))
        base = 0x30 if offset >= 0x30 else 0x00
        reg = offset - base
        if reg == 0x00:
            if value & 0x4:  # reset both channels
                if self.fault == 'stuck_reset':
                    self.mem[0x00] = 0x4
                    return
                self.mem.update({0x00: 0, 0x30: 0, 0x04: 0x1, 0x34: 0x1, 0x58: 0, 0x28: 0})
                self.armed.clear()
                self.pending = None
                return
            self.mem[offset] = value
            if value & 0x1:  # RS clears Halted; Idle stays 0 until a transfer completes
                self.mem[base + 0x04] &= ~0x1
            return
        if reg == 0x04:
            self.mem[offset] = self.mem.get(offset, 0) & ~(value & 0x7000)
            return
        self.mem[offset] = value & 0xFFFFFFFF
        if reg == 0x28:
            if self.mem.get(base, 0) & 1 == 0:
                self.mem[base + 0x04] = self.mem.get(base + 0x04, 0) | 0x10 | 0x1
                return
            self.mem[base + 0x04] &= ~0x2  # busy
            self.armed[base] = (self.mem.get(base + 0x18, 0) | self.mem.get(base + 0x1C, 0) << 32, value)
            if len(self.armed) == 2:
                self.pending = self.slow_polls if self.fault == 'slow' else 0

    def read(self, offset, length=4):
        if self.pending is not None and offset in (0x04, 0x34):
            if self.pending > 0:
                self.pending -= 1
            else:
                self.pending = None
                self._complete()
        return super().read(offset)

    def _complete(self):
        (sa, slen), (da, dlen) = self.armed[0x00], self.armed[0x30]
        self.armed.clear()
        if self.fault == 'no_tlast':
            self.mem[0x04] |= 0x1002  # MM2S finishes, S2MM waits for TLAST forever
            return
        if self.fault == 'slave_error':
            self.mem[0x34] |= 0x4021
            self.mem[0x04] |= 0x1002
            return
        try:
            out = self.process(self.ddr.read(sa, slen))
        except IndexError:
            self.mem[0x04] |= 0x4041
            return
        if self.fault == 'short':
            out = out[:max(0, len(out) - self.short_by)]
        if len(out) > dlen:
            self.mem[0x34] |= 0x4011
            self.mem[0x04] |= 0x1002
            return
        try:
            self.ddr.write(da, out)
        except IndexError:
            self.mem[0x34] |= 0x4041
            return
        self.transfers.append((sa, slen, da, len(out)))
        self.mem[0x58] = len(out)
        self.mem[0x04] |= 0x1002
        self.mem[0x34] |= 0x1002


class ManualClock:
    """Deterministic clock: sleep() advances time, so timeouts are tested without waiting."""

    def __init__(self):
        self.t = 0.0

    def __call__(self):
        return self.t

    def sleep(self, dt):
        self.t += max(dt, 1e-6)
