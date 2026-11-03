"""Capture the standalone PUF self-test ASCII log through the PYNQ mailbox.

No Y01 framing, epoch service, raw-key API or secure-boot claim.
Run on the board with the matching bit/HWH and evidence manifest.

Refuses (exit 1, before any MMIO access) any bitstream listed in
INVALIDATED_BIT_SHA256 -- notably the withdrawn puf_v2 candidate documented in
candidate/INVALID.md. There is no bypass option.
"""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import platform
import sys
import time


# Hard refusal list: bitstreams this project has formally invalidated. There is no
# override flag. See candidate/INVALID.md for the evidence behind each entry.
# 05c955cd...3dc62 = puf_v2 STRUCTURAL_DIAGNOSTIC_ONLY candidate built before the
# FIXED_IO/DDR BD export fix: 301 CRITICAL WARNING [Netlist 29-160] in impl_1.log and
# only +0.009ns setup slack after post-route phys_opt_design.
INVALIDATED_BIT_SHA256 = frozenset({
    '05c955cdc8ca5d7c019eed1194e4f2403ef1d415e582750fa04c7a1b5cf3dc62',
})


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--bit', required=True)
    p.add_argument('--control', default='control')
    p.add_argument('--mailbox', default='mailbox')
    p.add_argument('--manifest', required=True, help='candidate/manifest.json pairing bit/HWH/firmware')
    p.add_argument('--timeout', type=float, default=10)
    p.add_argument('--out', required=True)
    a=p.parse_args()
    if a.timeout<=0: p.error('--timeout must be positive')
    out=Path(a.out); out.mkdir(parents=True,exist_ok=False)
    bit=Path(a.bit); hwh=bit.with_suffix('.hwh')
    bit_sha=digest(bit)
    result={'timestamp':datetime.datetime.now(datetime.timezone.utc).isoformat(),
            'kind':'physical_board_puf_soc_v2_ascii_selftest','board':platform.platform(),
            'python':sys.version,'bit_sha256':bit_sha,'hwh_sha256':digest(hwh),
            'candidate_manifest_sha256':digest(a.manifest),'command':sys.argv,
            'timing_signoff':False,'physical_entropy':'not_measured','secure_boot':False,
            'status':'FAIL','exit_code':1}
    raw=bytearray()
    try:
        if bit_sha in INVALIDATED_BIT_SHA256:
            raise RuntimeError('Refusing invalidated bitstream (candidate/INVALID.md): '+bit_sha)
        manifest=json.loads(Path(a.manifest).read_text())
        if manifest.get('schema')!='puf_soc_candidate_v1': raise RuntimeError('Wrong candidate manifest schema')
        expected=manifest['artifact_sha256']
        if digest(bit)!=expected['puf.bit'] or digest(hwh)!=expected['puf.hwh']:
            raise RuntimeError('Bit/HWH mismatch with candidate manifest')
        result['firmware_elf_sha256']=expected['puf_v2.elf']
        result['firmware_coe_sha256']=expected['puf_v2.coe']
        import pynq
        result['pynq_version']=pynq.__version__
        overlay=pynq.Overlay(str(bit), download=True)
        result['ip_dict']=overlay.ip_dict
        def mmio(name):
            if name not in overlay.ip_dict: raise RuntimeError('HWH instance missing: '+name)
            d=overlay.ip_dict[name]
            return pynq.MMIO(d['phys_addr'],d['addr_range'])
        ctl,mb=mmio(a.control),mmio(a.mailbox)
        cid,version,mid=ctl.read(8),ctl.read(12),mb.read(0x1c)
        result.update(control_id=cid,control_version=version,mailbox_id=mid,
                      diagnostic=bool(version&256))
        if cid!=0x32554650 or version not in (2,258) or mid!=0x4d424f58:
            raise RuntimeError('Wrong overlay identity; expected PUF2 ASCII logger')
        if version!=manifest['control_version']: raise RuntimeError('ABI mode differs from candidate manifest')
        # Explicitly inspect PYNQ's configured clock state; do not change frequency
        # to mask a logic timing failure. Overlay/HWH config supplies clocks.
        result['fclk0_mhz']=pynq.Clocks.fclk0_mhz
        result['fclk1_mhz']=pynq.Clocks.fclk1_mhz
        if abs(result['fclk0_mhz']-100)>0.1 or abs(result['fclk1_mhz']-25)>0.1:
            raise RuntimeError('PS clock state must be 100MHz core and 25MHz management')
        ctl.write(0,1); time.sleep(0.01)
        ctl.write(0,0)
        deadline=time.monotonic()+a.timeout
        while time.monotonic()<deadline:
            status=mb.read(0x0c)
            if status&(1<<18): raise RuntimeError('mailbox RX overflow')
            if status&0xffff:
                raw.append(mb.read(4)&255)
                if b'PUF_V2_FAIL' in raw:
                    # Continue briefly to retain the failure phase printed next.
                    time.sleep(.01)
                    while mb.read(0x0c)&0xffff: raw.append(mb.read(4)&255)
                    raise RuntimeError('firmware self-test failed')
                if b'PUF_V2_TEST_PASS\r\n' in raw or b'PUF_V2_TEST_PASS\n' in raw:
                    if b'PUF_V2_OFFLINE_SELFTEST' not in raw: raise RuntimeError('boot marker missing')
                    if ctl.read(4)&8: raise RuntimeError('sticky SoC bus fault / LED1 set')
                    result.update(status='PASS',exit_code=0)
                    break
            else: time.sleep(.001)
        else: raise TimeoutError('PUF firmware ASCII deadline')
        result['final_control_status']=ctl.read(4)
        result['final_mailbox_status']=mb.read(0x0c)
    except Exception as e:
        result['error']=repr(e)
    finally:
        (out/'uart.bin').write_bytes(raw)
        (out/'uart.txt').write_text(raw.decode('ascii',errors='backslashreplace'),encoding='utf-8')
        (out/'result.json').write_text(json.dumps(result,indent=2,default=str)+'\n',encoding='utf-8')
    print(result['status'],out)
    return result['exit_code']


if __name__=='__main__': sys.exit(main())
