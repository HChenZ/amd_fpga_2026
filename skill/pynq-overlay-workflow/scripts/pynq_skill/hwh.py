"""Minimal HWH (Vivado hardware handoff XML) reader using only the standard library.

Extracts what host code needs: addressable IP instances (from the PS MEMRANGE table),
VLNV, IP parameters, optional <REGISTERS> metadata and PS clock settings.
"""
import xml.etree.ElementTree as ET


def _int(text):
    text = str(text).strip()
    return int(text, 16) if text.lower().startswith('0x') else int(text)


def _props(node):
    return {p.get('NAME'): p.get('VALUE') for p in node.findall('PROPERTY')}


def _registers(module):
    regs = {}
    for reg in module.iter('REGISTER'):
        p = _props(reg)
        if 'ADDRESS_OFFSET' not in p:
            continue
        fields = {}
        for fld in reg.iter('FIELD'):
            fp = _props(fld)
            if 'BIT_OFFSET' in fp and 'BIT_WIDTH' in fp:
                fields[fld.get('NAME')] = {'lsb': _int(fp['BIT_OFFSET']), 'width': _int(fp['BIT_WIDTH']),
                                           'access': fp.get('ACCESS')}
        regs[reg.get('NAME')] = {'offset': _int(p['ADDRESS_OFFSET']), 'width': _int(p.get('SIZE', 32)),
                                 'access': p.get('ACCESS'), 'fields': fields}
    return regs


def parse_hwh(path_or_text):
    text = path_or_text
    if not text.lstrip().startswith('<'):
        with open(path_or_text, encoding='utf-8', errors='replace') as f:
            text = f.read()
    root = ET.fromstring(text)
    modules = {}
    ps = None
    for mod in root.iter('MODULE'):
        inst = mod.get('INSTANCE')
        if not inst:
            continue
        params = {p.get('NAME'): p.get('VALUE') for p in mod.findall('./PARAMETERS/PARAMETER')}
        modules[inst] = {'vlnv': mod.get('VLNV'), 'modtype': mod.get('MODTYPE'),
                         'fullname': mod.get('FULLNAME'), 'parameters': params,
                         'registers': _registers(mod)}
        if mod.get('MODTYPE') in ('processing_system7', 'zynq_ultra_ps_e'):
            ps = (inst, mod)
    ips = {}
    if ps is not None:
        for rng in ps[1].iter('MEMRANGE'):
            inst = rng.get('INSTANCE')
            base, high = _int(rng.get('BASEVALUE')), _int(rng.get('HIGHVALUE'))
            key = (modules.get(inst, {}).get('fullname') or inst).lstrip('/')
            entry = ips.setdefault(key, {'instance': inst, 'ranges': []})
            entry['ranges'].append({'base': base, 'high': high, 'range': high - base + 1,
                                    'memtype': rng.get('MEMTYPE'), 'master': rng.get('MASTERBUSINTERFACE'),
                                    'block': rng.get('ADDRESSBLOCK')})
        for key, entry in ips.items():
            first = min(entry['ranges'], key=lambda r: r['base'])
            mod = modules.get(entry['instance'], {})
            entry.update(phys_addr=first['base'], addr_range=first['range'], vlnv=mod.get('vlnv'),
                         registers=mod.get('registers', {}), parameters=mod.get('parameters', {}))
    clocks = {}
    crystal = None
    if ps is not None:
        params = modules[ps[0]]['parameters']
        for i in range(4):
            v = params.get('PCW_FPGA%d_PERIPHERAL_FREQMHZ' % i) or params.get('PSU__CRL_APB__PL%d_REF_CTRL__ACT_FREQMHZ' % i)
            if v is not None:
                clocks['fclk%d_mhz' % i] = float(v)
        c = params.get('PCW_CRYSTAL_PERIPHERAL_FREQMHZ') or params.get('PSU__PSS_REF_CLK__FREQMHZ')
        crystal = float(c) if c is not None else None
    return {'ips': ips, 'modules': modules, 'ps': ps[0] if ps else None,
            'clocks': clocks, 'ps_ref_clk_mhz': crystal}


def summary_lines(info):
    lines = ['PS: %s  ref_clk=%s MHz  %s' % (info['ps'], info['ps_ref_clk_mhz'],
                                             ' '.join('%s=%g' % kv for kv in sorted(info['clocks'].items())))]
    for key in sorted(info['ips'], key=lambda k: info['ips'][k]['phys_addr']):
        ip = info['ips'][key]
        lines.append('0x%08X  +0x%-8X %-28s %s  regs=%d' % (ip['phys_addr'], ip['addr_range'], key,
                                                              ip['vlnv'], len(ip['registers'])))
    return lines
