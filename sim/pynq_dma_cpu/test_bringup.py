"""Offline CLI orchestration tests. Explicit reference adapter, no board claims."""
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock
import types

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from src.pynq.dma_transport import Result,RemoteError
from src.pynq.ascon_host_api import load_python,REFERENCE_PATH,REFERENCE_SHA256
from src.pynq.golden_checker import parse_kat
spec=importlib.util.spec_from_file_location('dma_bringup',ROOT/'board/vivado_zynq7000_xc7z020_pynq_dma_cpu/bringup.py')
cli=importlib.util.module_from_spec(spec)
spec.loader.exec_module(cli)


class ReferenceTransport:
    simulated=True
    needs_recovery=False
    epoch=17
    def __init__(self):
        self.capacities={1:(32,32),2:(16,16),3:(32,32),4:(1024,1024)}
        self.reference=load_python(REFERENCE_PATH,REFERENCE_SHA256)
        self.retained=[];self.closed=False;self.corrupt=False;self.accept_bad=False;self.calls=0
    def recover(self,timeout=None):return self.capacities
    def close(self,timeout=None):self.closed=True
    def transact(self,op,mode,key,nonce,ad,data,tag=b'',timeout=None):
        self.calls+=1
        if op==1:payload=self.reference.ascon_encrypt(key,nonce,ad,data,'Ascon-AEAD128')
        else:
            payload=self.reference.ascon_decrypt(key,nonce,ad,data+tag,'Ascon-AEAD128')
            if payload is None:
                if self.accept_bad:payload=b''
                else:raise RemoteError(1)
        if self.corrupt:payload=payload+b'\x00'
        return Result(payload,None,True,mode)


class BringupTests(unittest.TestCase):
    def test_full_official_counts_all_modes(self):
        t=ReferenceTransport()
        r=cli.run_checks(t,modes=[1,2,3,4],full=True)
        self.assertTrue(r['passed'])
        self.assertEqual(r['evidence_kind'],'simulated_adapter')
        self.assertEqual([v['vectors_passed'] for v in r['tests']],[1089,289,1089,1089])
        self.assertEqual(t.calls,3*(1089*3+289))
        for v in r['tests']:
            self.assertEqual(v['vectors_passed'],v['encrypt_passed'])
            self.assertEqual(v['vectors_passed'],v['decrypt_passed'])
            self.assertEqual(v['vectors_passed'],v['badtag_rejected'])

    def test_benchmark_records_only_actual_results(self):
        t=ReferenceTransport()
        r=cli.run_checks(t,modes=[4],benchmark=3,message_bytes=1024,ad_bytes=1024)
        samples=r['benchmarks'][0]['samples']
        self.assertEqual(len(samples),3)
        self.assertTrue(all(s['cycles'] is None and s['simulated'] and s['wall_seconds']>=0 for s in samples))
        self.assertEqual(r['benchmarks'][0]['cycle_scope'],'PL computation')
        self.assertEqual(t.calls,4)

    def test_capacity_and_mode_rejection_no_fallback(self):
        t=ReferenceTransport()
        with self.assertRaises(ValueError):cli.run_checks(t,modes=[2],benchmark=1,message_bytes=17)
        self.assertEqual(t.calls,0)
        for text in ('5','1,1','0',''):
            with self.subTest(text=text),self.assertRaises(ValueError):cli.select_modes(text,t.capacities)

    def test_mismatch_and_badtag_acceptance_fail(self):
        cases=list(parse_kat())[:1]
        t=ReferenceTransport();t.corrupt=True
        with self.assertRaises(AssertionError):cli.run_checks(t,modes=[1],full=True,cases=cases)
        t=ReferenceTransport();t.accept_bad=True
        with self.assertRaises(AssertionError):cli.run_checks(t,modes=[1],full=True,cases=cases)

    def cli_run(self,mode='4',firmware=False,corrupt=False):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);bit=root/'image.bit';hwh=root/'image.hwh';fw=root/'service.bin';out=root/'result.json'
            bit.write_bytes(b'public-test-bit');hwh.write_bytes(b'public-test-hwh');fw.write_bytes(b'public-test-fw')
            t=ReferenceTransport();t.corrupt=corrupt
            args=['--bit',str(bit),'--hwh',str(hwh),'--use-loaded','--modes',mode,'--smoke','--output',str(out)]
            if firmware:args+=['--firmware',str(fw)]
            code=cli.main(args,factory=lambda args,report:t)
            report=json.loads(out.read_text(encoding='utf-8'))
            return code,report,t.closed

    def test_cli_success_identity_and_direct_no_firmware(self):
        code,r,closed=self.cli_run()
        self.assertEqual(code,0);self.assertTrue(closed)
        self.assertTrue(r['passed']);self.assertEqual(r['firmware_binding'],'not_applicable_direct_hardware')
        self.assertEqual(set(r['artifacts']),{'bit','hwh'})
        self.assertEqual(r['measurements']['evidence_kind'],'simulated_adapter')

    def test_cli_cpu_requires_firmware_and_closes(self):
        code,r,closed=self.cli_run(mode='1')
        self.assertEqual(code,1);self.assertTrue(closed);self.assertFalse(r['passed'])
        code,r,closed=self.cli_run(mode='1',firmware=True)
        self.assertEqual(code,0);self.assertTrue(closed)
        self.assertIn('firmware',r['artifacts'])
        self.assertEqual(r['firmware_binding'],'supplied_build_artifact_not_readback_verified')

    def test_cli_failure_is_nonzero_without_measurement_claim(self):
        code,r,closed=self.cli_run(corrupt=True)
        self.assertEqual(code,1);self.assertTrue(closed)
        self.assertFalse(r['passed']);self.assertIn('AssertionError',r['errors'])
        self.assertFalse(r['measurements']['passed'])

    def test_identity_mismatch_prevents_opening_board(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);bit=root/'a.bit';hwh=root/'a.hwh';out=root/'r.json'
            bit.write_bytes(b'x');hwh.write_bytes(b'y')
            def factory(*args):self.fail('board must not be opened after identity failure')
            code=cli.main(['--bit',str(bit),'--hwh',str(hwh),'--bit-sha256','0'*64,
                           '--use-loaded','--output',str(out)],factory=factory)
            self.assertEqual(code,1)
            self.assertIsNone(json.loads(out.read_text())['measurements'])

    def test_raw_mmio_factory_does_not_instantiate_dma_driver(self):
        parameters=dict(c_include_sg='0',c_micro_dma='0',c_include_mm2s='1',c_include_s2mm='1',
            c_sg_length_width='14',c_m_axi_mm2s_data_width='64',c_m_axi_s2mm_data_width='64',
            c_include_mm2s_dre='0',c_include_s2mm_dre='0')
        events=[]
        class Overlay:
            def __init__(self,path,download):
                events.append(('overlay',download));self.path=path
                self.ip_dict={'ctl':{'phys_addr':0x1000,'addr_range':4096},
                    'dma':{'phys_addr':0x2000,'addr_range':4096,'type':'xilinx.com:ip:axi_dma:7.1',
                           'parameters':parameters}}
            def download(self):events.append('download')
            def __getattr__(self,name):raise AssertionError('IP driver constructor accessed')
        class MMIO:
            def __init__(self,base,size):self.base=base;events.append(('mmio',base))
            def read(self,o):return 1 if self.base==0x2000 and o in (4,0x34) else 0
            def write(self,o,v):events.append(('write',self.base,o,v))
        pynq=types.SimpleNamespace(__version__='2.7.0',Overlay=Overlay,MMIO=MMIO,
                                  PL=types.SimpleNamespace(bitfile_name=None),
                                  Clocks=types.SimpleNamespace(fclk0_mhz=80.0,_instance=types.SimpleNamespace(_ref_clk_mhz=50.0)),allocate=lambda **kw:None)
        fcntl=types.SimpleNamespace(LOCK_EX=2,LOCK_NB=4,flock=lambda fd,op:events.append('lock'))
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);bit=root/'x.bit';hwh=root/'x.hwh'
            bit.write_bytes(b'x');hwh.write_bytes(b'y')
            args=cli.parser().parse_args(['--bit',str(bit),'--hwh',str(hwh),'--download',
                '--control-ip','ctl','--dma-ip','dma','--output',str(root/'r.json'),'--lock-path',str(root/'lock')])
            with mock.patch.dict(sys.modules,{'pynq':pynq,'fcntl':fcntl}):
                report={}
                transport=cli.open_board(args,report)
                transport.close()
            self.assertEqual(report['fclk0_mhz_register_readback'],80.0)
            self.assertEqual(report['pynq_reference_clock_mhz_assumed'],50.0)
            self.assertLess(events.index('lock'),events.index(('overlay',False)))
            self.assertIn('download',events)
            self.assertIn(('mmio',0x1000),events);self.assertIn(('mmio',0x2000),events)

    def test_quarantine_keeps_owner_until_verified_close(self):
        class Transport:
            def __init__(self):self.retained=[object()];self.attempts=0
            def close(self):
                self.attempts+=1
                if self.attempts<3:raise RuntimeError('still active')
                self.retained=[]
        t=Transport();report={'passed':False}
        with tempfile.TemporaryDirectory() as directory:
            cli.quarantine(t,report,Path(directory)/'result.json',sleep=lambda _:None)
        self.assertEqual(t.attempts,3)
        self.assertFalse(report['quarantined'])
        self.assertEqual(report['exit_code_when_safe'],1)


if __name__=='__main__':unittest.main(verbosity=2)
