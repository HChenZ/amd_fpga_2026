"""Stage C: interface contract -> validated register map -> generated driver/test skeleton."""
import json
import pprint

from . import PynqSkillError

ACCESS = ('rw', 'ro', 'wo', 'rc', 'w1c')
READABLE = ('rw', 'ro', 'rc', 'w1c')
WRITABLE = ('rw', 'wo', 'w1c')


class ContractError(PynqSkillError):
    pass


class AccessError(PynqSkillError):
    pass


def _num(v):
    if isinstance(v, bool):
        raise ValueError(v)
    if isinstance(v, int):
        return v
    s = str(v).strip()
    return int(s, 16) if s.lower().startswith('0x') else int(s)


def _ident(name):
    return isinstance(name, str) and name.replace('_', 'a').isalnum() and not name[0].isdigit()


def load_contract(src):
    """Load and validate a contract (path, JSON text or dict). Raises ContractError."""
    if isinstance(src, dict):
        data = json.loads(json.dumps(src))
    elif str(src).lstrip().startswith('{'):
        data = json.loads(src)
    else:
        with open(src, encoding='utf-8') as f:
            data = json.load(f)
    problems = []
    try:
        addr_range = _num(data.get('addr_range', 0x10000))
    except ValueError:
        problems.append('addr_range is not a number')
        addr_range = 0x10000
    regs, used = {}, {}
    for i, r in enumerate(data.get('registers') or []):
        name = r.get('name')
        if not _ident(name):
            problems.append('register #%d has invalid name %r' % (i, name))
            continue
        if name in regs:
            problems.append('duplicate register %s' % name)
        try:
            off = _num(r['offset'])
        except (KeyError, ValueError):
            problems.append('%s: missing/invalid offset' % name)
            continue
        width = r.get('width', 32)
        acc = r.get('access', 'rw')
        if width != 32:
            problems.append('%s: width %r unsupported (use pairs for 64-bit)' % (name, width))
        if acc not in ACCESS:
            problems.append('%s: access %r not in %s' % (name, acc, ACCESS))
        if off % 4:
            problems.append('%s: offset 0x%X not 4-byte aligned' % (name, off))
        if off < 0 or off + 4 > addr_range:
            problems.append('%s: offset 0x%X outside addr_range 0x%X' % (name, off, addr_range))
        if off in used:
            problems.append('%s overlaps %s at 0x%X' % (name, used[off], off))
        used[off] = name
        fields, mask = {}, 0
        for f in r.get('fields') or []:
            fname, lsb, fw = f.get('name'), f.get('lsb'), f.get('width', 1)
            facc = f.get('access', acc)
            if not _ident(fname) or not isinstance(lsb, int) or not isinstance(fw, int) or fw < 1:
                problems.append('%s: invalid field %r' % (name, f))
                continue
            if lsb < 0 or lsb + fw > 32:
                problems.append('%s.%s: bits [%d+:%d] exceed 32' % (name, fname, lsb, fw))
                continue
            fmask = ((1 << fw) - 1) << lsb
            if fmask & mask:
                problems.append('%s.%s overlaps another field' % (name, fname))
            if facc not in ACCESS:
                problems.append('%s.%s: access %r invalid' % (name, fname, facc))
            mask |= fmask
            fields[fname] = {'lsb': lsb, 'width': fw, 'access': facc, 'mask': fmask}
        regs[name] = {'name': name, 'offset': off, 'access': acc, 'fields': fields,
                      'doc': r.get('doc', '')}
    pairs = {}
    for p in data.get('pairs') or []:
        if p.get('lo') not in regs or p.get('hi') not in regs:
            problems.append('pair %r references unknown registers' % p.get('name'))
            continue
        for part in ('lo', 'hi'):
            if regs[p[part]]['access'] not in WRITABLE:
                problems.append('pair %s: %s is not writable' % (p.get('name'), p[part]))
        pairs[p['name']] = (p['lo'], p['hi'])
    identity = []
    for ident in data.get('identity') or []:
        if ident.get('register') not in regs:
            problems.append('identity references unknown register %r' % ident.get('register'))
            continue
        identity.append((ident['register'], _num(ident['value'])))
    if not regs:
        problems.append('contract has no registers')
    if problems:
        raise ContractError('invalid contract %r' % data.get('name'), problems)
    return {'_validated': True, 'name': data.get('name', 'ip'), 'vlnv': data.get('vlnv'), 'addr_range': addr_range,
            'source': data.get('source'), 'registers': regs, 'pairs': pairs, 'identity': identity}


class RegisterMap:
    """Contract-checked access on any object exposing read(offset)/write(offset, value)."""

    def __init__(self, mmio, contract):
        if not callable(getattr(mmio, 'read', None)) or not callable(getattr(mmio, 'write', None)):
            raise TypeError('mmio must expose read/write')
        self.mmio = mmio
        self.contract = contract if contract.get('_validated') else load_contract(contract)

    def _reg(self, name):
        try:
            return self.contract['registers'][name]
        except KeyError:
            raise AccessError('unknown register %r' % name) from None

    def read(self, name):
        reg = self._reg(name)
        if reg['access'] not in READABLE:
            raise AccessError('%s is write-only' % name)
        return self.mmio.read(reg['offset']) & 0xFFFFFFFF

    def write(self, name, value):
        reg = self._reg(name)
        if reg['access'] not in WRITABLE:
            raise AccessError('%s is %s (not writable)' % (name, reg['access']))
        if not isinstance(value, int) or not 0 <= value <= 0xFFFFFFFF:
            raise ValueError('%s: value must be a u32' % name)
        self.mmio.write(reg['offset'], value)

    def fields(self, name, value=None):
        """Decode all fields from ONE read (safe for clear-on-read registers)."""
        reg = self._reg(name)
        if value is None:
            value = self.read(name)
        return {f: (value & d['mask']) >> d['lsb'] for f, d in reg['fields'].items()}

    def read_field(self, name, field):
        reg = self._reg(name)
        if any(f['access'] == 'rc' for f in reg['fields'].values()) or reg['access'] == 'rc':
            raise AccessError('%s has clear-on-read bits; use fields(%r) once and keep the result'
                              % (name, name))
        return self.fields(name)[field]

    def write_field(self, name, field, value):
        reg = self._reg(name)
        d = reg['fields'].get(field)
        if d is None:
            raise AccessError('unknown field %s.%s' % (name, field))
        if d['access'] not in WRITABLE:
            raise AccessError('%s.%s is %s' % (name, field, d['access']))
        if reg['access'] in ('rc', 'w1c', 'wo') or any(
                f['access'] in ('rc', 'w1c') for f in reg['fields'].values()):
            raise AccessError('%s: read-modify-write would disturb rc/w1c/wo bits; write() the whole register'
                              % name)
        if not 0 <= value < (1 << d['width']):
            raise ValueError('%s.%s: value out of range' % (name, field))
        old = self.read(name)
        self.write(name, (old & ~d['mask'] & 0xFFFFFFFF) | (value << d['lsb']))

    def write_pair(self, pair, value):
        lo, hi = self.contract['pairs'][pair]
        if not 0 <= value < (1 << 64):
            raise ValueError('%s must be u64' % pair)
        self.write(lo, value & 0xFFFFFFFF)
        self.write(hi, value >> 32)

    def verify_identity(self):
        bad = []
        for name, expected in self.contract['identity']:
            got = self.read(name)
            if got != expected:
                bad.append('%s read 0x%08X expected 0x%08X' % (name, got, expected))
        if bad:
            raise AccessError('identity mismatch', bad)
        return True


def cross_check_hwh(contract, hwh_registers):
    """Compare contract offsets/fields with hwh <REGISTERS> metadata (if present)."""
    problems = []
    if not hwh_registers:
        return ['hwh has no register metadata for this IP (normal for custom RTL); contract is the only source']
    by_off = {r['offset']: (n, r) for n, r in hwh_registers.items()}
    for name, reg in contract['registers'].items():
        hit = by_off.get(reg['offset'])
        if hit is None:
            problems.append('%s @0x%X not described in hwh' % (name, reg['offset']))
            continue
        hname, hreg = hit
        for fname, f in reg['fields'].items():
            hf = hreg['fields'].get(fname)
            if hf is None:
                hf = next((v for v in hreg['fields'].values() if v['lsb'] == f['lsb']), None)
            if hf is None or (hf['lsb'], hf['width']) != (f['lsb'], f['width']):
                problems.append('%s.%s bits [%d+:%d] differ from hwh %s' % (name, fname, f['lsb'], f['width'], hname))
    return problems


def _cls(name):
    return ''.join(p.capitalize() for p in name.split('_')) or 'Ip'


def generate_driver(contract):
    c = contract
    out = ['"""Generated from contract %r (%s). Do not edit; regenerate from the contract."""' % (
        c['name'], c.get('source') or 'source not recorded'), '',
        'CONTRACT = %s' % pprint.pformat({
            'name': c['name'], 'vlnv': c['vlnv'], 'addr_range': c['addr_range'],
            'registers': [{'name': r['name'], 'offset': r['offset'], 'access': r['access'],
                           'fields': [{'name': f, 'lsb': d['lsb'], 'width': d['width'], 'access': d['access']}
                                      for f, d in r['fields'].items()]}
                          for r in c['registers'].values()],
            'pairs': [{'name': k, 'lo': v[0], 'hi': v[1]} for k, v in c['pairs'].items()],
            'identity': [{'register': n, 'value': v} for n, v in c['identity']]}, sort_dicts=False), '',
        '']
    for r in c['registers'].values():
        out.append('%s = 0x%02X  # %s' % (r['name'], r['offset'], r['access']))
    out += ['', '', 'class %s:' % _cls(c['name']),
            '    """Thin driver: all accesses go through pynq_skill.regmap.RegisterMap checks."""', '',
            '    def __init__(self, mmio):',
            '        from pynq_skill.regmap import RegisterMap',
            '        self.regs = RegisterMap(mmio, CONTRACT)', '',
            '    @classmethod',
            '    def from_overlay(cls, overlay, name):',
            '        from pynq import MMIO',
            '        ip = overlay.ip_dict[name]',
            '        return cls(MMIO(ip["phys_addr"], ip["addr_range"]))', '']
    for r in c['registers'].values():
        lname = r['name'].lower()
        if r['access'] in READABLE:
            out += ['    def read_%s(self):' % lname, '        return self.regs.read(%r)' % r['name'], '']
        if r['access'] in WRITABLE:
            out += ['    def write_%s(self, value):' % lname, '        self.regs.write(%r, value)' % r['name'], '']
    for p in c['pairs']:
        out += ['    def set_%s(self, value):' % p.lower(), '        self.regs.write_pair(%r, value)' % p, '']
    return '\n'.join(out).rstrip() + '\n'


def generate_test_skeleton(contract, driver_module):
    c = contract
    cls = _cls(c['name'])
    out = ['"""Generated pytest skeleton for %s. Fill the TODO behavioural tests with an' % c['name'],
           'independent reference; the structural tests below must pass as generated."""',
           'import pytest', 'from pynq_skill.fakes import FakeMMIO',
           'from pynq_skill.regmap import AccessError',
           'from %s import %s, CONTRACT' % (driver_module, cls), '', '',
           'def make():',
           '    mmio = FakeMMIO(CONTRACT["addr_range"])',
           '    return %s(mmio), mmio' % cls, '', '',
           'def test_offsets_unique_and_aligned():',
           '    offs = [r["offset"] for r in CONTRACT["registers"]]',
           '    assert len(offs) == len(set(offs)) and all(o % 4 == 0 for o in offs)', '']
    for r in c['registers'].values():
        lname = r['name'].lower()
        if r['access'] == 'rw':
            out += ['', 'def test_%s_roundtrip():' % lname, '    drv, mmio = make()',
                    '    drv.write_%s(0xA5A5A5A5)' % lname,
                    '    assert mmio.peek(0x%02X) == 0xA5A5A5A5' % r['offset'],
                    '    assert drv.read_%s() == 0xA5A5A5A5' % lname]
        elif r['access'] == 'ro':
            out += ['', 'def test_%s_is_read_only():' % lname, '    drv, _ = make()',
                    '    with pytest.raises(AccessError):', '        drv.regs.write(%r, 1)' % r['name']]
        elif r['access'] == 'wo':
            out += ['', 'def test_%s_is_write_only():' % lname, '    drv, _ = make()',
                    '    with pytest.raises(AccessError):', '        drv.regs.read(%r)' % r['name']]
    for p, (lo, hi) in c['pairs'].items():
        out += ['', 'def test_pair_%s_writes_both_halves():' % p.lower(), '    drv, mmio = make()',
                '    drv.set_%s(0x1_2345_6789)' % p.lower(),
                '    assert mmio.peek(0x%02X) == 0x23456789' % c['registers'][lo]['offset'],
                '    assert mmio.peek(0x%02X) == 0x1' % c['registers'][hi]['offset']]
    out += ['', '', '@pytest.mark.skip(reason="TODO: behavioural test against an independent golden model")',
            'def test_behaviour_against_golden():', '    pass', '']
    return '\n'.join(out)
