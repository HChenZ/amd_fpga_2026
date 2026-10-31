"""Host-only capture CLI checks. Fake MMIO is never physical-board evidence."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import types
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[2]
# Workspace-local scratch space: no dependency on an absolute %TEMP% path.
BASE=Path(os.environ.get('PUF_CAPTURE_TEST_TMP') or ROOT/'build/tmp/puf_capture_test')
spec=importlib.util.spec_from_file_location('puf_capture',ROOT/'board/vivado_zynq7000_xc7z020_puf_v2/capture.py')
cli=importlib.util.module_from_spec(spec); spec.loader.exec_module(cli)


class CaptureTests(unittest.TestCase):
    def invoke(self, *, identity=0x32554650, clock=100, overflow=False, firmware_fail=False, mismatch=False, invalidated=False):
        BASE.mkdir(parents=True,exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='puf_capture_test_',dir=BASE) as d:
            d=Path(d)
            bit=d/'puf.bit'; hwh=d/'puf.hwh'
            bit.write_bytes(b'FAKE_TEST_BIT'); hwh.write_bytes(b'FAKE_TEST_HWH')
            bit_sha=hashlib.sha256(bit.read_bytes()).hexdigest()
            manifest={'schema':'puf_soc_candidate_v1','control_version':2,'artifact_sha256':{
                'puf.bit':bit_sha,
                'puf.hwh':hashlib.sha256(hwh.read_bytes()).hexdigest(),
                'puf_v2.elf':'host-test-fixture','puf_v2.coe':'host-test-fixture'}}
            m=d/'manifest.json'; m.write_text(json.dumps(manifest))
            if mismatch: bit.write_bytes(b'CHANGED_TEST_BIT')
            transcript=bytearray(b'PUF_V2_OFFLINE_SELFTEST\r\n'+
                (b'PUF_V2_FAIL 00000004\r\n' if firmware_fail else b'PUF_V2_TEST_PASS\r\n'))
            class FakeMMIO:
                def __init__(self,addr,size): self.addr=addr
                def write(self,a,value): pass
                def read(self,a):
                    if self.addr==0x40000000: return {8:identity,12:2,4:1}.get(a,0)
                    if a==0x1c: return 0x4d424f58
                    if a==0x0c: return len(transcript)|((1<<18) if overflow else 0)
                    if a==4: return transcript.pop(0)
                    return 0
            fake=types.SimpleNamespace(__version__='MOCK_TEST_ONLY',MMIO=FakeMMIO,
                Clocks=types.SimpleNamespace(fclk0_mhz=clock,fclk1_mhz=25),
                Overlay=lambda *args,**kwargs:types.SimpleNamespace(ip_dict={
                    'control':{'phys_addr':0x40000000,'addr_range':4096},
                    'mailbox':{'phys_addr':0x40001000,'addr_range':4096}}))
            args=['capture.py','--bit',str(bit),'--manifest',str(m),'--out',str(d/'out')]
            sha_patch=(patch.object(cli,'INVALIDATED_BIT_SHA256',frozenset({bit_sha}))
                       if invalidated else patch.object(cli,'INVALIDATED_BIT_SHA256',frozenset()))
            with patch.object(sys,'argv',args),patch.dict(sys.modules,{'pynq':fake}),patch.object(cli.time,'sleep',lambda _:None),sha_patch:
                code=cli.main()
            return code,json.loads((d/'out/result.json').read_text())

    def test_ascii_success(self):
        code,r=self.invoke(); self.assertEqual(code,0); self.assertEqual(r['status'],'PASS')
        self.assertFalse(r['timing_signoff']); self.assertFalse(r['secure_boot'])
    def test_wrong_identity(self): self.assertEqual(self.invoke(identity=0)[0],1)
    def test_wrong_clock(self): self.assertEqual(self.invoke(clock=50)[0],1)
    def test_overflow(self): self.assertEqual(self.invoke(overflow=True)[0],1)
    def test_firmware_fail(self): self.assertEqual(self.invoke(firmware_fail=True)[0],1)
    def test_bit_pairing(self): self.assertEqual(self.invoke(mismatch=True)[0],1)
    def test_invalidated_bit(self):
        code,r=self.invoke(invalidated=True)
        self.assertEqual(code,1); self.assertEqual(r['status'],'FAIL')
        self.assertIn('invalidated',r['error'])


if __name__=='__main__': unittest.main()
