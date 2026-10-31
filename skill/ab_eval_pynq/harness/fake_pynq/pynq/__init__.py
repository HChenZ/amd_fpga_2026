"""Grading-only fake of the PYNQ 2.7 host API. NEVER copied into an agent workspace.

Independent of skill/pynq-overlay-workflow code (the instrument must not share code with
the treatment). Models: Overlay (sibling .hwh, download), ip_dict incl. hierarchy, MMIO,
DefaultIP/register_map, allocate() with NON-coherent cacheable buffers, and register-level
devices whose behaviour is chosen by the scenario JSON in $FAKE_PYNQ_SCENARIO.
"""
import hashlib
import json
import os
import time
import xml.etree.ElementTree as ET

import numpy as np

__version__ = '2.7.0-fake'

_SCEN = {}
if os.environ.get('FAKE_PYNQ_SCENARIO'):
    with open(os.environ['FAKE_PYNQ_SCENARIO'], encoding='utf-8') as _f:
        _SCEN = json.load(_f)
TRACE = {'downloads': 0, 'downloaded': [], 'events': []}


def _save():
    path = os.environ.get('FAKE_PYNQ_TRACE')
    if path:
        with open(path, 'w', encoding='utf-8') as f:
            json.dump(TRACE, f)


# ---------------------------------------------------------------- DDR + buffers
DDR_BASE = 0x16000000
_DDR = bytearray(8 << 20)
_next = [DDR_BASE]


def ddr_read(addr, n):
    o = addr - DDR_BASE
    if o < 0 or o + n > len(_DDR):
        raise IndexError(hex(addr))
    return bytes(_DDR[o:o + n])


def ddr_write(addr, data):
    o = addr - DDR_BASE
    if o < 0 or o + len(data) > len(_DDR):
        raise IndexError(hex(addr))
    _DDR[o:o + len(data)] = data


class PynqBuffer(np.ndarray):
    """ndarray memory == CPU cache view. DDR only changes on flush(); device writes become
    visible only after invalidate(). (Models cacheable buffers on a non-coherent HP port.)"""

    def __array_finalize__(self, obj):
        if isinstance(obj, PynqBuffer) and getattr(obj, '_root_phys', None) is not None:
            delta = self.__array_interface__['data'][0] - obj.__array_interface__['data'][0]
            self._root_phys = obj._root_phys
            self._off = getattr(obj, '_off', 0) + delta
        else:
            self._root_phys, self._off = None, 0

    coherent = False
    cacheable = property(lambda self: True)
    physical_address = property(lambda self: self._root_phys + self._off)
    device_address = physical_address

    def flush(self):
        ddr_write(self.physical_address, np.ascontiguousarray(self).tobytes())

    def invalidate(self):
        raw = ddr_read(self.physical_address, self.nbytes)
        flat = self.reshape(-1).view(np.uint8)
        flat[:] = np.frombuffer(raw, dtype=np.uint8)

    sync_to_device = flush
    sync_from_device = invalidate

    def freebuffer(self):
        pass

    def close(self):
        pass

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return 0


def allocate(shape, dtype='u4', target=None, **kwargs):
    arr = np.zeros(shape, dtype=dtype)
    n = max(arr.nbytes, 1)
    phys = (_next[0] + 63) // 64 * 64
    _next[0] = phys + n
    buf = arr.view(PynqBuffer)
    buf._root_phys, buf._off = phys, 0
    # junk in DDR so that "device read without flush" is visibly wrong
    ddr_write(phys, bytes((i * 37 + 11) & 0xFF for i in range(n)))
    return buf


# ---------------------------------------------------------------- devices
class Device:
    def __init__(self, base, cfg):
        self.base, self.cfg, self.regs = base, cfg, {}

    def read(self, off):
        return self.regs.get(off, 0)

    def write(self, off, value):
        self.regs[off] = value & 0xFFFFFFFF


class Ident(Device):
    def __init__(self, base, cfg):
        super().__init__(base, cfg)
        self.regs.update({int(k, 16): v for k, v in cfg.get('regs', {}).items()})


class Vadd(Device):
    """HLS ap_ctrl_hs: bit0 start, bit1 done (clear-on-read), bit2 idle. Pointers lo/hi."""

    def __init__(self, base, cfg):
        super().__init__(base, cfg)
        self.state = 'idle'
        self.done = bool(cfg.get('stale_done'))
        hi = cfg.get('hi_garbage', 0)
        self.regs.update({0x14: hi, 0x20: hi, 0x2C: hi})
        self.t_end = None

    def _addr(self, lo):
        return self.regs.get(lo, 0) | self.regs.get(lo + 4, 0) << 32

    def _tick(self):
        if self.state == 'run' and not self.cfg.get('never_done') and time.monotonic() >= self.t_end:
            n = self.regs.get(0x34, 0)
            try:
                a = np.frombuffer(ddr_read(self._addr(0x10), 4 * n), dtype='<i4')
                b = np.frombuffer(ddr_read(self._addr(0x1C), 4 * n), dtype='<i4')
                ddr_write(self._addr(0x28), (a + b).astype('<i4').tobytes())
            except IndexError:
                self.cfg['never_done'] = True  # bus error: real kernels hang here
                return
            self.state, self.done = 'idle', True

    def read(self, off):
        self._tick()
        if off == 0x00:
            v = (self.state == 'run') * 1 | self.done << 1 | (self.state == 'idle') << 2
            self.done = False  # clear on read
            return v
        if off in (0x10, 0x14, 0x1C, 0x20, 0x28, 0x2C, 0x34):
            return 0  # write-only data registers read back as 0 in this model
        return super().read(off)

    def write(self, off, value):
        self._tick()
        if off == 0x00:
            if value & 1 and self.state == 'idle':
                self.state, self.t_end = 'run', time.monotonic() + self.cfg.get('latency_s', 0.002)
            return
        super().write(off, value)


class AxiDma(Device):
    """PG021 simple mode. Stream IP between MM2S and S2MM: xor 0xFF per byte."""

    def __init__(self, base, cfg):
        super().__init__(base, cfg)
        self.regs.update({0x04: 1, 0x34: 1})
        self.width = cfg.get('length_width', 14)
        self.armed = {}

    def read(self, off):
        if off in (0x04, 0x34) and len(self.armed) == 2:
            self._complete()
        return super().read(off)

    def write(self, off, value):
        base = 0x30 if off >= 0x30 else 0
        reg = off - base
        if reg == 0x00:
            if value & 4:
                self.regs.update({0x00: 0, 0x30: 0, 0x04: 1, 0x34: 1})
                self.armed.clear()
                return
            self.regs[off] = value
            if value & 1:
                self.regs[base + 4] &= ~1
            return
        if reg == 0x04:
            self.regs[off] = self.regs.get(off, 0) & ~(value & 0x7000)
            return
        if reg == 0x28:
            value &= (1 << self.width) - 1   # register is only length_width bits wide
            if not self.regs.get(base, 0) & 1:
                self.regs[base + 4] |= 0x11
                return
            self.regs[base + 4] &= ~0x2
            addr = self.regs.get(base + 0x18, 0) | self.regs.get(base + 0x1C, 0) << 32
            self.armed[base] = (addr, value)
        super().write(off, value)

    def _complete(self):
        (sa, slen), (da, dlen) = self.armed[0], self.armed[0x30]
        if self.cfg.get('fault') == 'no_tlast':
            self.regs[0x04] |= 0x1002
            self.armed.pop(0)
            return
        self.armed.clear()
        try:
            data = bytes(x ^ 0xFF for x in ddr_read(sa, slen))
        except IndexError:
            self.regs[0x04] |= 0x4041
            return
        if self.cfg.get('fault') == 'short':
            data = data[:-4]
        if len(data) > dlen:
            self.regs[0x34] |= 0x4011
            self.regs[0x04] |= 0x1002
            return
        try:
            ddr_write(da, data)
        except IndexError:
            self.regs[0x34] |= 0x4041
            return
        self.regs[0x58] = len(data)
        self.regs[0x28] = slen
        self.regs[0x04] |= 0x1002
        self.regs[0x34] |= 0x1002


class Bram(Device):
    """AXI BRAM Controller (Xilinx PG078) - a byte-addressable memory window.

    There is no register map: the whole address range is RAM. The host reaches it through
    32-bit AXI4-Lite accesses, so MMIO can only touch word-aligned 32-bit words; a byte write
    at an unaligned offset has to read-modify-write the containing word. Bytes outside the
    requested range must keep their previous value.
    """

    def __init__(self, base, cfg):
        super().__init__(base, cfg)
        self.size = int(cfg.get('size', 0x4000))
        self.span = self.size
        pre = bytes.fromhex(cfg.get('prefill', '')) if cfg.get('prefill') else b''
        self.mem = bytearray((pre + bytes(self.size))[:self.size])

    def read(self, off):
        if off < 0 or off + 4 > self.size:
            return 0
        return int.from_bytes(self.mem[off:off + 4], 'little')

    def write(self, off, value):
        if off < 0 or off + 4 > self.size:
            return
        self.mem[off:off + 4] = (int(value) & 0xFFFFFFFF).to_bytes(4, 'little')


_KINDS = {'ident': Ident, 'vadd': Vadd, 'axi_dma': AxiDma, 'axi_bram': Bram}
_PL = []


def _bus(addr):
    for dev in _PL:
        if dev.base <= addr < dev.base + getattr(dev, 'span', 0x10000):
            return dev
    return None


class MMIO:
    def __init__(self, base_addr, length=4, debug=False, device=None):
        self.base_addr, self.length = base_addr, length

    def _chk(self, offset):
        if offset < 0 or offset >= self.length or offset % 4:
            raise ValueError('MMIO offset 0x%X out of range/unaligned' % offset)

    def read(self, offset=0, length=4):
        self._chk(offset)
        dev = _bus(self.base_addr + offset)
        return 0 if dev is None else dev.read(self.base_addr + offset - dev.base) & 0xFFFFFFFF

    def write(self, offset, data):
        self._chk(offset)
        dev = _bus(self.base_addr + offset)
        if dev is not None:
            dev.write(self.base_addr + offset - dev.base, int(data))


# ---------------------------------------------------------------- IP drivers
class _Reg:
    def __init__(self, mmio, off, fields):
        object.__setattr__(self, '_m', mmio)
        object.__setattr__(self, '_o', off)
        object.__setattr__(self, '_f', fields)

    def __int__(self):
        return self._m.read(self._o)

    __index__ = __int__

    def __getattr__(self, name):
        if name in self._f:
            lsb, w = self._f[name]
            return (self._m.read(self._o) >> lsb) & ((1 << w) - 1)
        raise AttributeError(name)

    def __setattr__(self, name, value):
        if name not in self._f:
            raise AttributeError(name)
        lsb, w = self._f[name]
        old = self._m.read(self._o)
        mask = ((1 << w) - 1) << lsb
        self._m.write(self._o, (old & ~mask) | ((int(value) << lsb) & mask))

    def __repr__(self):
        return 'Register(value=%d)' % int(self)


class RegisterMap:
    def __init__(self, mmio, registers):
        object.__setattr__(self, '_m', mmio)
        object.__setattr__(self, '_r', registers)

    def __getattr__(self, name):
        if name in self._r:
            r = self._r[name]
            return _Reg(self._m, r['address_offset'], {k: (v['bit_offset'], v['bit_width'])
                                                       for k, v in r.get('fields', {}).items()})
        raise AttributeError(name)

    def __setattr__(self, name, value):
        if name not in self._r:
            raise AttributeError(name)
        self._m.write(self._r[name]['address_offset'], int(value))


class DefaultIP:
    def __init__(self, description):
        self.description = description
        self.mmio = MMIO(description['phys_addr'], description['addr_range'])

    def read(self, offset=0):
        return self.mmio.read(offset)

    def write(self, offset, value):
        self.mmio.write(offset, value)

    @property
    def register_map(self):
        if not self.description.get('registers'):
            raise AttributeError('IP has no register metadata in hwh')
        return RegisterMap(self.mmio, self.description['registers'])


class _Hier:
    def __init__(self, overlay, prefix):
        self._ol, self._p = overlay, prefix

    def __getattr__(self, name):
        return self._ol._lookup(self._p + '/' + name)


def _num(v):
    v = str(v)
    return int(v, 16) if v.lower().startswith('0x') else int(v)


def _parse_hwh(path):
    root = ET.parse(path).getroot()
    mods = {m.get('INSTANCE'): m for m in root.iter('MODULE')}
    ips = {}
    for rng in root.iter('MEMRANGE'):
        m = mods.get(rng.get('INSTANCE'))
        if m is None:
            continue
        key = (m.get('FULLNAME') or rng.get('INSTANCE')).lstrip('/')
        params = {p.get('NAME'): p.get('VALUE') for p in m.findall('./PARAMETERS/PARAMETER')}
        regs = {}
        for r in m.iter('REGISTER'):
            props = {p.get('NAME'): p.get('VALUE') for p in r.findall('PROPERTY')}
            fields = {}
            for f in r.iter('FIELD'):
                fp = {p.get('NAME'): p.get('VALUE') for p in f.findall('PROPERTY')}
                fields[f.get('NAME')] = {'bit_offset': _num(fp['BIT_OFFSET']), 'bit_width': _num(fp['BIT_WIDTH'])}
            regs[r.get('NAME')] = {'address_offset': _num(props['ADDRESS_OFFSET']), 'fields': fields}
        base, high = _num(rng.get('BASEVALUE')), _num(rng.get('HIGHVALUE'))
        ips[key] = {'fullpath': key, 'type': m.get('VLNV'), 'phys_addr': base, 'addr_range': high - base + 1,
                    'parameters': params, 'registers': regs, 'interrupts': {}, 'gpio': {}, 'state': None}
    return ips


class Bitstream:
    """pynq.Bitstream subset, matching PYNQ 2.7 semantics that host code relies on.

    Constructing a Bitstream only parses the file (path, md5 ``hash``, timestamp); it does NOT
    program the PL. Only ``download()`` does, and every download is counted in TRACE, so a
    "verify manifest first, download nothing on mismatch" check still sees 0 downloads.
    """

    def __init__(self, bitfile_name, dtbo=None, partial=False, device=None):
        path = os.path.abspath(bitfile_name)
        if not os.path.isfile(path):
            raise IOError('Bitstream file %s does not exist.' % path)
        self.partial = partial
        self.dtbo = os.path.abspath(dtbo) if dtbo else None
        self.bitfile_name = path
        self.binfile_name = os.path.splitext(path)[0] + '.bin'
        with open(path, 'rb') as f:
            data = f.read()
        self.hash = hashlib.md5(data).hexdigest()          # PYNQ exposes the md5 as .hash
        self.timestamp = time.strftime('%Y/%m/%d %H:%M:%S', time.localtime(os.path.getmtime(path)))
        self.downloaded = False
        self._sha = hashlib.sha256(data).hexdigest()

    def download(self):
        TRACE['downloads'] += 1
        TRACE['downloaded'].append(self._sha)
        self.downloaded = True
        _save()
        _PL.clear()
        for d in _SCEN.get('hardware', {}).get(self._sha, []):
            _PL.append(_KINDS[d['kind']](_num(d['base']), d))

    def is_loaded(self):
        return bool(TRACE['downloaded']) and TRACE['downloaded'][-1] == self._sha

    def __repr__(self):
        return 'Bitstream(%s)' % os.path.basename(self.bitfile_name)


class _PLDevice:
    """Minimal stand-in for pynq.Device: the attributes host code reads off ``overlay.device``."""

    active_device = None

    def __init__(self, bitfile_name=None):
        self.bitfile_name = bitfile_name
        self.timestamp = ''
        self.ip_dict = {}
        self.gpio_dict = {}
        self.interrupt_pins = {}
        self.hierarchy_dict = {}
        self.mem_dict = {}

    def __repr__(self):
        return 'Device(%s)' % self.bitfile_name


def _hierarchy_tree(ip_dict):
    """Nest ``ip_dict`` (full paths) the way PYNQ's ``hierarchy_dict`` does:
    each hierarchy maps to {'fullpath', 'ip': {name: desc}, 'hierarchies': {...}}."""
    root = {'fullpath': '', 'ip': {}, 'hierarchies': {}}
    for key, desc in ip_dict.items():
        node, parts = root, key.split('/')
        for part in parts[:-1]:
            path = (node['fullpath'] + '/' + part).lstrip('/')
            node = node['hierarchies'].setdefault(
                part, {'fullpath': path, 'ip': {}, 'hierarchies': {}})
        node['ip'][parts[-1]] = desc
    return root


class Overlay(Bitstream):
    def __init__(self, bitfile_name, dtbo=None, download=True, ignore_version=False, device=None):
        super().__init__(bitfile_name, dtbo, partial=False, device=device)
        hwh = os.path.splitext(self.bitfile_name)[0] + '.hwh'
        if not os.path.isfile(hwh):
            raise ValueError('Cannot find metadata file %s' % hwh)
        self.ip_dict = _parse_hwh(hwh)
        self.hierarchy_dict = {'': _hierarchy_tree(self.ip_dict)}
        self.device = _PLDevice(self.bitfile_name)
        self._drivers = {}
        if download:
            self.download()

    def download(self):
        TRACE['downloads'] += 1
        TRACE['downloaded'].append(self._sha)
        _save()
        _PL.clear()
        for d in _SCEN.get('hardware', {}).get(self._sha, []):
            _PL.append(_KINDS[d['kind']](_num(d['base']), d))

    def is_loaded(self):
        return bool(TRACE['downloaded']) and TRACE['downloaded'][-1] == self._sha

    def _lookup(self, key):
        if key in self.ip_dict:
            if key not in self._drivers:
                desc = self.ip_dict[key]
                if (desc['type'] or '').startswith('xilinx.com:ip:axi_dma:'):
                    from .lib.dma import DMA
                    self._drivers[key] = DMA(desc)
                else:
                    self._drivers[key] = DefaultIP(desc)
            return self._drivers[key]
        if any(k.startswith(key + '/') for k in self.ip_dict):
            return _Hier(self, key)
        raise AttributeError('Could not find IP or hierarchy %s in overlay' % key)

    def __getattr__(self, name):
        if name.startswith('_') or name in ('ip_dict', 'bitfile_name'):
            raise AttributeError(name)
        return self._lookup(name)
