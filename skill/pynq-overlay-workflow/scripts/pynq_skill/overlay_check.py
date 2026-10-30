"""Stage B: after Overlay() is constructed, prove the PL really is the expected design.

All checks run and are reported together; nothing is downloaded here. The overlay object
only needs `is_loaded()` and `ip_dict` (real pynq.Overlay or fakes.FakeOverlay).
"""
from . import PynqSkillError


class OverlayCheckError(PynqSkillError):
    pass


def _mmio_for(overlay, name, ip, mmio_factory):
    if mmio_factory is not None:
        return mmio_factory(ip['phys_addr'], ip['addr_range'])
    from pynq import MMIO  # only on the board
    return MMIO(ip['phys_addr'], ip['addr_range'])


def verify_overlay(overlay, hwh_info=None, *, required=(), identity=(), fclk_mhz=None,
                   clocks=None, fclk_tolerance=0.02, mmio_factory=None):
    """Verify a loaded overlay.

    required: iterable of IP names, or {name: expected_vlnv_or_None}
    identity: iterable of (ip_name, offset, expected_value) read through raw MMIO, so
              no IP driver constructor (which may spin on hardware) is triggered.
    fclk_mhz: {'fclk0_mhz': 100.0, ...} expected; defaults to the hwh clocks.
    clocks:   object with fclkN_mhz attributes (pynq.ps.Clocks); skipped if None.
    Returns a report dict; raises OverlayCheckError with every problem found.
    """
    problems, report = [], {'ips': {}, 'identity': [], 'clocks': {}}
    if not callable(getattr(overlay, 'is_loaded', None)) or not overlay.is_loaded():
        raise OverlayCheckError('overlay check failed', ['overlay is not loaded in the PL'])
    ip_dict = getattr(overlay, 'ip_dict', None) or {}
    if not isinstance(required, dict):
        required = {name: None for name in required}
    for name, vlnv in required.items():
        ip = ip_dict.get(name)
        if ip is None:
            close = [k for k in ip_dict if k.split('/')[-1] == name.split('/')[-1]]
            problems.append('IP %r missing from ip_dict%s' % (name, ' (did you mean %s?)' % close if close else ''))
            continue
        report['ips'][name] = {'phys_addr': ip.get('phys_addr'), 'addr_range': ip.get('addr_range'),
                               'type': ip.get('type')}
        if vlnv and ip.get('type') != vlnv:
            problems.append('IP %r type %r != expected %r' % (name, ip.get('type'), vlnv))
    if hwh_info is not None:
        for name, ip in ip_dict.items():
            ref = hwh_info['ips'].get(name)
            if ref is None:
                if name in required:
                    problems.append('IP %r present at runtime but absent from the reference hwh' % name)
                continue
            if ip.get('phys_addr') != ref['phys_addr'] or ip.get('addr_range') != ref['addr_range']:
                problems.append('IP %r runtime 0x%X/+0x%X != hwh 0x%X/+0x%X (stale or foreign hwh?)' % (
                    name, ip.get('phys_addr') or 0, ip.get('addr_range') or 0, ref['phys_addr'], ref['addr_range']))
        for name in required:
            if name not in hwh_info['ips']:
                problems.append('required IP %r not in reference hwh' % name)
    for name, offset, expected in identity:
        ip = ip_dict.get(name)
        if ip is None:
            problems.append('identity: IP %r missing' % name)
            continue
        if offset % 4 or offset >= ip['addr_range']:
            problems.append('identity: offset 0x%X invalid for %r' % (offset, name))
            continue
        value = _mmio_for(overlay, name, ip, mmio_factory).read(offset)
        report['identity'].append({'ip': name, 'offset': offset, 'value': value, 'expected': expected})
        if value != expected:
            problems.append('identity: %s+0x%X read 0x%08X, expected 0x%08X' % (name, offset, value, expected))
    expected_clk = dict(fclk_mhz or (hwh_info or {}).get('clocks', {}))
    if clocks is not None:
        for key, want in expected_clk.items():
            got = getattr(clocks, key, None)
            if got is None:
                continue
            report['clocks'][key] = {'register_derived': got, 'expected': want}
            if want and abs(got - want) > fclk_tolerance * want:
                problems.append('%s register-derived %.3f MHz != expected %.3f MHz '
                                '(check PS reference clock assumption)' % (key, got, want))
    if problems:
        raise OverlayCheckError('overlay check failed', problems)
    return report


def load_overlay(bit_path, *, manifest=None, overlay_cls=None, download=True, **verify_kwargs):
    """Stage A + B in the right order: hash check, then download, then verify."""
    from . import artifacts, hwh
    art = artifacts.check_artifacts(bit_path, manifest=manifest)
    info = hwh.parse_hwh(art['hwh'])
    if overlay_cls is None:
        from pynq import Overlay as overlay_cls
    overlay = overlay_cls(art['bit'], download=download)
    report = verify_overlay(overlay, info, **verify_kwargs)
    report['artifacts'] = art
    return overlay, info, report
