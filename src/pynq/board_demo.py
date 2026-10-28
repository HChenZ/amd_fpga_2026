"""Hardware-only entrypoint. Run from repository root on the board (Python >=3.8)."""
import argparse
import hashlib
import json
import time
from pathlib import Path
if __package__:
    from .ascon_host_api import AsconHost, AuthenticationError
    from .pynq_transport import BridgeRegs, PynqUartTransport
    from .mailbox_backend import MailboxBackend
    from .navigator_backend import validate_overlay
    from .make_pynq_profile import build_profile
    from .golden_checker import parse_kat
else:
    from ascon_host_api import AsconHost, AuthenticationError
    from pynq_transport import BridgeRegs, PynqUartTransport
    from mailbox_backend import MailboxBackend
    from navigator_backend import validate_overlay
    from make_pynq_profile import build_profile
    from golden_checker import parse_kat

def run(release, full_kat=False):
    from pynq import Overlay, MMIO
    release=Path(release).resolve()
    manifest=json.loads((release/'manifest.json').read_text(encoding='utf-8'))
    for name,info in manifest['artifacts'].items():
        artifact=release/name
        assert artifact.stat().st_size==info['bytes'], 'release size mismatch: '+name
        assert hashlib.sha256(artifact.read_bytes()).hexdigest()==info['sha256'], 'release hash mismatch: '+name
    bit=release/'pynq.bit'; hwh=release/'pynq.hwh'; fw=release/'pynq_svc.elf'
    # Generate board-local paths; no Windows absolute paths in portable releases.
    profile,_=build_profile(str(hwh),str(bit),str(fw),'pynq-svc-v1',None,None)
    overlay=Overlay(str(bit))
    validate_overlay(profile,overlay)
    binding=profile['ip_bindings']
    def mmio(kind):
        p=binding[kind];return MMIO(p['phys_addr'],p['addr_range'])
    regs=BridgeRegs(mmio('control'),mmio('mailbox'))
    regs.check_identity()
    transport=PynqUartTransport(regs,expected_firmware_id='pynq-svc-v1')
    backend=MailboxBackend(transport,mode='sw',timeout_s=30.0)
    report={'kind':'hardware','service':transport.last_service,'modes':{},'board_validation':'NOT_RUN'}
    cases=[c for c in parse_kat() if len(c['PT'])<=16 and len(c['AD'])<=16]
    if not full_kat: cases=[cases[i] for i in (0,1,16,17,144,288)]
    for mode in ('sw','hw','ise'):
        # MailboxBackend resolves mode during construction; use its enum mapping.
        from_mode={'sw':1,'hw':2,'ise':3}
        if __package__: from .mailbox_protocol import Mode
        else: from mailbox_protocol import Mode
        backend.mode=Mode(from_mode[mode])
        backend.name='mailbox-'+mode
        host=AsconHost(backend); passed=0; rejected=0; samples=[]
        for c in cases:
            k,n,ad,pt,ct=(c[x] for x in ('Key','Nonce','AD','PT','CT'))
            r=host.encrypt(k,n,ad,pt,timeout_s=10)
            assert not r.simulated and r.ciphertext+r.tag==ct, 'KAT encrypt mismatch'
            assert host.decrypt(k,n,ad,ct[:-16],ct[-16:],timeout_s=10).plaintext==pt
            bad=ct[-16:-1]+bytes([ct[-1]^1])
            try: host.decrypt(k,n,ad,ct[:-16],bad,timeout_s=10)
            except AuthenticationError: rejected+=1
            else: raise AssertionError('bad tag accepted')
            passed+=1
            samples.append({'kat':c['count'],'cycles':r.cycles if r.cycles is not None else 'NOT_MEASURED'})
        report['modes'][mode]={'kat_pass':passed,'tag_reject':rejected,'samples':samples}
        print(mode,report['modes'][mode],flush=True)
    report['board_validation']='PASS'
    return report

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--release',default='board/vivado_zynq7000_xc7z020_pynq/release')
    p.add_argument('--full-kat',action='store_true',help='all 289 supported official cases per mode')
    p.add_argument('--out',default='pynq_board_result.json')
    a=p.parse_args()
    result=run(a.release,a.full_kat)
    Path(a.out).write_text(json.dumps(result,indent=2,default=str),encoding='utf-8')
    print('hardware KAT PASS; save JSON and terminal log')
if __name__=='__main__':main()
