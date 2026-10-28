"""make_pynq_profile.py —— 从 .hwh 生成 navigator profile（供 NavigatorTransport 校验）

流程：
  1. 解析 Vivado 导出的 .hwh，收集所有 MEMRANGE 的 (BASEVALUE, HIGHVALUE)；
  2. 选出控制窗口与邮箱窗口（可用 --control/--mailbox 指定名字，否则按名字猜）；
  3. 校验对齐、非重叠、4 KB 以下；
  4. 计算 bit/hwh/firmware 的 SHA-256；
  5. 写出 schema_version=1 的 profile JSON（status=configured）；
  6. 立刻用 navigator_backend.read_profile + validate_overlay 自检一遍。

自检用的 overlay 是 duck-typed 替身：它的 bitfile_name / ip_dict 直接用 .hwh 的解析结果，
代表"PYNQ 加载完这个 overlay 之后会看到的地址表"。真正加载过的 overlay 检查在上板脚本里
再做一次（pynq.Overlay 真实对象）。因此本脚本成功**不等于**上板通过。

用法：
  python src/pynq/make_pynq_profile.py \
      --hwh build/local/pynq_ovl/top_pynq.hwh \
      --bit build/local/pynq_ovl/top_pynq.bit \
      --firmware build/local/pynq_svc/pynq_svc.elf \
      --firmware-id pynq-svc-v1 \
      --out board/vivado_zynq7000_xc7z020_pynq/pynq_profile.json
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

PART = 'xc7z020clg400-1'
PROTOCOL_REVISION = 'y01-draft-v1+uart-phy'
DESIGN_SOURCE = 'board/vivado_zynq7000_xc7z020_pynq (top_pynq + pynq_ctl/pynq_mbox)'


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, 'rb') as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def parse_hwh(path):
    """返回 {instance_name: {'phys_addr': int, 'addr_range': int}}。"""
    root = ET.parse(path).getroot()
    out = {}
    for elem in root.iter():
        base = elem.get('BASEVALUE') or elem.get('BASEADDR')
        high = elem.get('HIGHVALUE') or elem.get('HIGHADDR')
        if not base or not high:
            continue
        name = elem.get('INSTANCE') or elem.get('FULLNAME') or elem.tag
        base_v = int(base, 0)
        high_v = int(high, 0)
        size = high_v - base_v + 1
        # 同名多条 MEMRANGE（多窗口 IP）时只保留第一个并记录
        if name in out:
            continue
        out[name] = {'phys_addr': base_v, 'addr_range': size}
    return out


def pick(names, explicit, hints):
    if explicit:
        if explicit not in names:
            raise SystemExit('window %r not found in hwh (have: %s)'
                             % (explicit, ', '.join(sorted(names)) or '<none>'))
        return explicit
    for name in sorted(names):
        low = name.lower()
        if any(h in low for h in hints):
            return name
    raise SystemExit('cannot auto-pick a window matching %s; pass --control/--mailbox '
                     'explicitly (have: %s)' % (hints, ', '.join(sorted(names)) or '<none>'))


class _HwhOverlay:
    """duck-typed pynq.Overlay 替身：地址表来自 .hwh，不是真实加载结果。"""

    def __init__(self, bitfile, ip_dict):
        self.bitfile_name = bitfile
        self.ip_dict = ip_dict

    def is_loaded(self):
        return True


def build_profile(hwh, bit, firmware, firmware_id, control=None, mailbox=None):
    hwh_p, bit_p, fw_p = Path(hwh), Path(bit), Path(firmware)
    for p in (hwh_p, bit_p, fw_p):
        if not p.is_file():
            raise SystemExit('missing artifact: %s' % p)
    if bit_p.suffix.lower() != '.bit' or hwh_p.suffix.lower() != '.hwh':
        raise SystemExit('bit/hwh must be .bit/.hwh')
    if bit_p.with_suffix('.hwh').resolve() != hwh_p.resolve():
        raise SystemExit('bit and hwh must share the same basename and directory')

    ip_dict = parse_hwh(hwh_p)
    ctl = pick(ip_dict, control, ('ctl', 'control'))
    mb = pick(ip_dict, mailbox, ('mbox', 'mailbox'))
    if ctl == mb:
        raise SystemExit('control and mailbox resolved to the same window')

    ranges = []
    for name in (ctl, mb):
        info = ip_dict[name]
        base, size = info['phys_addr'], info['addr_range']
        if base % 4 or size <= 0 or size % 4:
            raise SystemExit('unaligned window for %s' % name)
        if size > 0x10000:
            raise SystemExit('window larger than 64 KiB for %s' % name)
        ranges.append((base, base + size))
    if max(ranges[0][0], ranges[1][0]) < min(ranges[0][1], ranges[1][1]):
        raise SystemExit('control and mailbox windows overlap')

    profile = {
        'schema_version': 1,
        'part': PART,
        'status': 'configured',
        'design_source': DESIGN_SOURCE,
        'protocol_revision': PROTOCOL_REVISION,
        'firmware_id': firmware_id,
        'artifacts': {
            'bit': {'path': str(bit_p.resolve()), 'sha256': sha256_file(bit_p)},
            'hwh': {'path': str(hwh_p.resolve()), 'sha256': sha256_file(hwh_p)},
            'firmware': {'path': str(fw_p.resolve()), 'sha256': sha256_file(fw_p)},
        },
        'ip_bindings': {
            'control': {'name': ctl, **ip_dict[ctl]},
            'mailbox': {'name': mb, **ip_dict[mb]},
        },
        'notes': [
            'UART-PHY channel: PS AXI-Lite byte FIFO <-> RV32 UART MMIO (0x20000000).',
            'addresses come from the exported .hwh; do not hand-edit them.',
            'hashes document provenance, not authenticity or secure boot.',
        ],
    }
    return profile, ip_dict


def selfcheck(profile, ip_dict):
    """用 navigator_backend 的正式校验函数复核刚生成的 profile。"""
    import tempfile
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import navigator_backend  # noqa: E402  （src/pynq 目录导入，避免与板载 pynq 包重名）

    fd = tempfile.NamedTemporaryFile('w', suffix='.json', delete=False, encoding='utf-8')
    json.dump(profile, fd)
    fd.close()
    try:
        prof = navigator_backend.read_profile(Path(fd.name))
        overlay = _HwhOverlay(profile['artifacts']['bit']['path'], ip_dict)
        navigator_backend.validate_overlay(prof, overlay)
        return prof
    finally:
        Path(fd.name).unlink(missing_ok=True)


def synth_hwh_fixture(path, ctl_base=0x40000000, mb_base=0x40001000):
    """单元测试用的合成 .hwh（只为验证解析器/校验器，不是任何真实设计证据）。"""
    xml = """<?xml version="1.0" encoding="UTF-8"?>
<EDKSYSTEM>
  <MODULES>
    <MODULE FULLNAME="/top_pynq_i/pynq_ctl_0" INSTANCE="pynq_ctl_0" MODTYPE="pynq_ctl">
      <MEMRANGE INSTANCE="pynq_ctl_0" BASENAME="C_BASEADDR" BASEVALUE="0x%08X" HIGHVALUE="0x%08X"
                MASTERBUSINTERFACE="/processing_system7_0/M_AXI_GP0"
                SLAVEBUSINTERFACE="/pynq_ctl_0/S_AXI"/>
    </MODULE>
    <MODULE FULLNAME="/top_pynq_i/pynq_mbox_0" INSTANCE="pynq_mbox_0" MODTYPE="pynq_mbox">
      <MEMRANGE INSTANCE="pynq_mbox_0" BASENAME="C_BASEADDR" BASEVALUE="0x%08X" HIGHVALUE="0x%08X"
                MASTERBUSINTERFACE="/processing_system7_0/M_AXI_GP0"
                SLAVEBUSINTERFACE="/pynq_mbox_0/S_AXI"/>
    </MODULE>
  </MODULES>
</EDKSYSTEM>
""" % (ctl_base, ctl_base + 0xFFF, mb_base, mb_base + 0xFFF)
    Path(path).write_text(xml, encoding='utf-8')
    return path


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument('--hwh')
    ap.add_argument('--bit')
    ap.add_argument('--firmware')
    ap.add_argument('--firmware-id', default='pynq-svc-v1')
    ap.add_argument('--control')
    ap.add_argument('--mailbox')
    ap.add_argument('--out')
    ap.add_argument('--selftest', action='store_true',
                    help='用合成 .hwh 跑一遍解析+校验（不产生任何真实工程证据）')
    args = ap.parse_args(argv)

    if args.selftest:
        import tempfile
        tmp = Path(tempfile.mkdtemp(prefix='pynq_profile_selftest_'))
        hwh = synth_hwh_fixture(tmp / 'top_pynq.hwh')
        (tmp / 'top_pynq.bit').write_bytes(b'\x00synthetic-bit\x00')
        (tmp / 'pynq_svc.elf').write_bytes(b'\x00synthetic-firmware\x00')
        profile, ip_dict = build_profile(hwh, tmp / 'top_pynq.bit', tmp / 'pynq_svc.elf',
                                        'pynq-svc-v1')
        out = tmp / 'pynq_profile.json'
        out.write_text(json.dumps(profile, indent=2), encoding='utf-8')
        prof = selfcheck(profile, ip_dict)
        print('selftest OK: bindings=%s bit=%s' % (prof['ip_bindings'],
                                                   Path(prof['artifacts']['bit']['path']).name))
        print('selftest profile written to %s (synthetic, not project evidence)' % out)
        return 0

    for req in ('hwh', 'bit', 'firmware', 'out'):
        if not getattr(args, req):
            ap.error('--%s is required' % req)

    profile, ip_dict = build_profile(args.hwh, args.bit, args.firmware,
                                     args.firmware_id, args.control, args.mailbox)
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(profile, indent=2) + '\n', encoding='utf-8')
    selfcheck(profile, ip_dict)
    print('profile written: %s' % out)
    print('  control: %s @ 0x%08X (%d bytes)' % (
        profile['ip_bindings']['control']['name'],
        profile['ip_bindings']['control']['phys_addr'],
        profile['ip_bindings']['control']['addr_range']))
    print('  mailbox: %s @ 0x%08X (%d bytes)' % (
        profile['ip_bindings']['mailbox']['name'],
        profile['ip_bindings']['mailbox']['phys_addr'],
        profile['ip_bindings']['mailbox']['addr_range']))
    print('validate_overlay: PASS (hwh-derived address table)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
