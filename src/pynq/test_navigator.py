"""Adapter contract tests; all peers and overlay objects below are mocks."""
from dataclasses import replace
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import time
import unittest

sys.path.insert(0,str(Path(__file__).resolve().parent))
from ascon_host_api import AsconHost, AuthenticationError, BackendProtocolError, BackendTimeoutError, BusError
from mailbox_backend import MailboxBackend, MemoryTransport
from navigator_backend import NavigatorTransport, NotConfiguredError, read_profile, validate_overlay


class NavigatorTests(unittest.TestCase):
    def test_not_configured_has_no_fallback(self):
        transport = NavigatorTransport()
        for call,args in ((transport.hello,()),(transport.submit,(b'abc',)),(transport.poll,()),
                          (transport.ack,(1,1)),(transport.reset,())):
            with self.assertRaises(NotConfiguredError):
                call(*args,time.monotonic()+5)
        with self.assertRaises(NotConfiguredError):
            MailboxBackend(transport)

    def test_existing_host_all_modes_auth_and_unmeasured_cycles(self):
        for mode in ('sw','hw','ise'):
            host = AsconHost(MailboxBackend(NavigatorTransport({'status':'mock'},driver=MemoryTransport()),mode))
            k,n = bytes(range(16)),bytes(range(16,32))
            result = host.encrypt(k,n,b'ad',b'0123456789abcdef')
            self.assertTrue(result.simulated)
            self.assertIsNone(result.cycles)
            self.assertEqual(host.decrypt(k,n,b'ad',result.ciphertext,result.tag).plaintext,b'0123456789abcdef')
            with self.assertRaises(AuthenticationError):
                host.decrypt(k,n,b'ad',result.ciphertext,bytes(16))

    def test_mock_cannot_become_hardware(self):
        peer = MemoryTransport()
        peer.capabilities = replace(peer.capabilities,simulated=False)
        with self.assertRaises(BackendProtocolError):
            NavigatorTransport({'status':'mock'},driver=peer).hello(time.monotonic()+5)

    def test_timeout_and_bus_error_use_existing_recovery(self):
        class Broken(MemoryTransport):
            def poll(self,deadline):
                raise OSError('injected private device details')
        backend = MailboxBackend(NavigatorTransport({'status':'mock'},driver=Broken()))
        with self.assertRaises(BusError) as error:
            backend.encrypt(bytes(16),bytes(16),b'',b'',timeout_s=1)
        self.assertNotIn('private',str(error.exception))
        self.assertTrue(backend.needs_recovery)
        backend.recover()
        self.assertFalse(backend.needs_recovery)
        with self.assertRaises(BackendTimeoutError):
            NavigatorTransport().hello(time.monotonic()-1)

    def test_real_profile_requires_overlay_and_manifest(self):
        with self.assertRaises(NotConfiguredError):
            validate_overlay({'status':'configured'},None)
        with self.assertRaises(NotConfiguredError):
            validate_overlay({'status':'not_configured'},object())

    def test_manifest_and_hwh_binding_checks(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            artifacts = {}
            for kind,name in (('bit','mock.bit'),('hwh','mock.hwh'),('firmware','mock.bin')):
                path = root/name
                path.write_bytes(b'mock, never load')
                artifacts[kind] = dict(path=str(path),sha256=hashlib.sha256(path.read_bytes()).hexdigest())
            # Synthetic addresses ONLY in this mock test, never in the board profile.
            bindings = {'control':dict(name='mock_control',phys_addr=0,addr_range=4096),
                        'mailbox':dict(name='mock_mailbox',phys_addr=4096,addr_range=4096)}
            profile = dict(status='configured',part='xc7z020clg400-1',firmware_id='mock-firmware-id',
                           design_source='mock fixture',protocol_revision='mock-v1',
                           artifacts=artifacts,ip_bindings=bindings)
            class Overlay:
                bitfile_name = str(root/'mock.bit')
                ip_dict = {v['name']:dict(v) for v in bindings.values()}
                def is_loaded(self): return True
            overlay = Overlay()
            validate_overlay(profile,overlay)
            overlay.ip_dict['mock_control']['phys_addr'] = 8
            with self.assertRaises(BackendProtocolError):
                validate_overlay(profile,overlay)
            overlay.ip_dict['mock_control']['phys_addr'] = 0
            (root/'mock.bit').write_bytes(b'changed')
            with self.assertRaises(BackendProtocolError):
                validate_overlay(profile,overlay)

    def test_board_profile_keeps_minus_one(self):
        root = Path(__file__).resolve().parents[2]
        profile = read_profile(root/'board/atk_navigator_7020/backend_profile.json')
        self.assertEqual(profile['part'],'xc7z020clg400-1')
        self.assertEqual(profile['status'],'not_configured')

    def test_notebook_runs_offline_without_hardware_calls(self):
        path = Path(__file__).with_name('navigator_demo.ipynb')
        notebook = json.loads(path.read_text(encoding='utf-8'))
        namespace = {'__name__':'__main__'}
        for cell in notebook['cells']:
            if cell['cell_type']=='code':
                exec(compile(''.join(cell['source']),str(path),'exec'),namespace)
        self.assertTrue(all(r.simulated and r.cycles is None for r in namespace['results'].values()))


if __name__ == '__main__':
    unittest.main()
