"""Standard-library acceptance tests; all writes stay in src/pynq bytecode cache."""
import contextlib
import io
import json
from pathlib import Path
import re
import subprocess
import sys
import unittest
from unittest.mock import patch

from ascon_host_api import (AsconHost, AuthenticationError, Backend,
                            BackendProtocolError, BackendTimeoutError, BusError,
                            InvalidLengthError, ReferenceIntegrityError,
                            ROOT, SimulatedBackend, cycle_table)
import golden_checker

HERE = Path(__file__).resolve().parent


class HostTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cases = golden_checker.parse_kat()

    def setUp(self):
        self.backend = SimulatedBackend()
        self.host = AsconHost(self.backend)
        self.key = bytes(range(16))
        self.nonce = bytes(range(16, 32))

    def test_six_representatives_in_all_modes(self):
        for mode in ("sw", "hw", "ise"):
            host = AsconHost(SimulatedBackend(mode))
            for m, a in ((0, 0), (1, 0), (16, 0), (16, 16), (17, 0), (32, 0)):
                c = next(c for c in self.cases if (len(c["PT"]), len(c["AD"])) == (m, a))
                with self.subTest(mode=mode, message=m, ad=a):
                    enc = host.encrypt(c["Key"], c["Nonce"], c["AD"], c["PT"])
                    self.assertEqual(enc.ciphertext + enc.tag, c["CT"])
                    dec = host.decrypt(c["Key"], c["Nonce"], c["AD"], c["CT"][:-16], c["CT"][-16:])
                    self.assertEqual(dec.plaintext, c["PT"])
                    self.assertTrue(enc.simulated)

    def test_invalid_lengths_and_types(self):
        for size in (0, 15, 17):
            with self.assertRaises(InvalidLengthError):
                self.host.encrypt(bytes(size), self.nonce, b"", b"")
            with self.assertRaises(InvalidLengthError):
                self.host.encrypt(self.key, bytes(size), b"", b"")
            with self.assertRaises(InvalidLengthError):
                self.host.decrypt(self.key, self.nonce, b"", b"", bytes(size))
        for args in (("key", self.nonce, b"", b""),
                     (self.key, self.nonce, bytearray(), b""),
                     (self.key, self.nonce, b"", "message")):
            with self.assertRaises(TypeError):
                self.host.encrypt(*args)

    def test_capacity_checked_before_backend(self):
        with patch.object(self.backend, "encrypt") as call:
            for ad, msg in ((bytes(65537), b""), (b"", bytes(65537))):
                with self.assertRaises(InvalidLengthError):
                    self.host.encrypt(self.key, self.nonce, ad, msg)
            call.assert_not_called()
        self.backend.max_message_bytes = self.backend.max_ad_bytes = 0
        self.host.encrypt(self.key, self.nonce, b"", b"")
        with self.assertRaises(InvalidLengthError):
            self.host.encrypt(self.key, self.nonce, b"", b"x")

    def test_bad_timeout_values(self):
        for value in (0, -1, float("inf"), float("nan"), True, "5"):
            with self.assertRaises(ValueError):
                self.host.encrypt(self.key, self.nonce, b"", b"", timeout_s=value)

    def test_transport_failure_and_timeout(self):
        for op in ("encrypt", "decrypt"):
            args = (self.key, self.nonce, b"", b"") + ((bytes(16),) if op == "decrypt" else ())
            for original, expected in ((OSError("private transport detail"), BusError),
                                       (TimeoutError("private detail"), BackendTimeoutError)):
                with patch.object(self.backend, op, side_effect=original):
                    with self.assertRaises(expected) as error:
                        getattr(self.host, op)(*args)
                    self.assertNotIn("private", str(error.exception))

    def test_late_response_discarded(self):
        with patch("ascon_host_api.time.monotonic", side_effect=(1.0, 3.0)):
            with self.assertRaises(BackendTimeoutError):
                self.host.encrypt(self.key, self.nonce, b"", b"", timeout_s=1)

    def test_malformed_responses_rejected(self):
        for result in (None, (b"",), (b"x", bytes(16)), (b"", bytes(15)), (b"", "tag")):
            with patch.object(self.backend, "encrypt", return_value=result):
                with self.assertRaises(BackendProtocolError):
                    self.host.encrypt(self.key, self.nonce, b"", b"")
        for result in (None, b"x", ""):
            with patch.object(self.backend, "decrypt", return_value=result):
                with self.assertRaises(BackendProtocolError):
                    self.host.decrypt(self.key, self.nonce, b"", b"", bytes(16))

    def test_no_failed_plaintext_returned(self):
        c = next(c for c in self.cases if len(c["PT"]) == 17 and not c["AD"])
        expected = c["CT"]
        for position in (0, 16, 17, len(expected)-1):
            bad = expected[:position] + bytes([expected[position] ^ 1]) + expected[position+1:]
            with self.assertRaises(AuthenticationError) as error:
                self.host.decrypt(c["Key"], c["Nonce"], b"", bad[:-16], bad[-16:])
            self.assertEqual(error.exception.args, ("authentication failed",))
            self.assertFalse(hasattr(error.exception, "plaintext"))

    def test_wrong_key_nonce_ad_rejected(self):
        enc = self.host.encrypt(self.key, self.nonce, b"ad", b"message")
        for k, n, ad in ((bytes(16), self.nonce, b"ad"),
                         (self.key, bytes(16), b"ad"), (self.key, self.nonce, b"bad")):
            with self.assertRaises(AuthenticationError):
                self.host.decrypt(k, n, ad, enc.ciphertext, enc.tag)

    def test_cycles_not_extrapolated(self):
        for m, a in ((0, 0), (1, 0), (16, 16), (17, 0), (32, 0)):
            enc = self.host.encrypt(self.key, self.nonce, bytes(a), bytes(m))
            self.assertIsNone(enc.cycles)
            self.assertEqual(enc.cycle_info.status, "not_measured")
        enc = self.host.encrypt(self.key, self.nonce, b"", bytes(16))
        self.assertEqual(enc.cycles, 2496)
        self.assertEqual(enc.cycle_info.status, "simulated")
        self.assertIsNone(self.host.decrypt(self.key, self.nonce, b"", enc.ciphertext, enc.tag).cycles)

    def test_cycle_sources(self):
        patterns = {"sw": r"enc 16B\s*:\s*(\d+) cycles",
                    "hw": r"full MMIO\s*:\s*(\d+) cycles", "ise": r"ISE cycles\s*:\s*(\d+)"}
        for mode, info in cycle_table().items():
            source = ROOT / info.source
            meta = json.loads(source.with_suffix(".json").read_text(encoding="utf-8"))
            self.assertEqual((meta["kind"], meta["status"], meta["mode"]), ("simulation", "PASS", mode))
            values = re.findall(patterns[mode], source.read_text(encoding="utf-8"))
            self.assertEqual(values, [str(info.value)])

    def test_integrity_failure(self):
        with patch("ascon_host_api.hashlib.sha256") as sha:
            sha.return_value.hexdigest.return_value = "0" * 64
            with self.assertRaises(ReferenceIntegrityError):
                SimulatedBackend()
            with self.assertRaises(ReferenceIntegrityError):
                golden_checker.parse_kat()

    def test_first_difference(self):
        self.assertIn("byte=0", golden_checker.first_difference(b"a", b"b"))
        self.assertIn("byte=1", golden_checker.first_difference(b"a", b"ab"))
        self.assertIn("<end>", golden_checker.first_difference(b"a", b""))
        self.assertIsNone(golden_checker.first_difference(b"", b""))

    def test_injected_cli_exits_nonzero(self):
        for injection in ("tag", "ciphertext"):
            result = subprocess.run([sys.executable, str(HERE / "golden_checker.py"),
                                     "--inject", injection], cwd=ROOT,
                                    capture_output=True, text=True, timeout=120)
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertIn("KAT PASS 1088 / FAIL 1", result.stdout)
            self.assertIn("byte=0", result.stdout)

    def test_checker_catches_false_authentication(self):
        with patch.object(self.backend, "decrypt", return_value=b""), contextlib.redirect_stdout(io.StringIO()):
            result = golden_checker.check_all(self.host)
        self.assertGreater(result["failed"], 0)

    def test_notebook_in_order(self):
        notebook = json.loads((HERE / "jupyter_demo.ipynb").read_text(encoding="utf-8"))
        namespace = {"__name__": "__main__"}
        with contextlib.redirect_stdout(io.StringIO()):
            for cell in notebook["cells"]:
                if cell["cell_type"] == "code":
                    exec(compile("".join(cell["source"]), "jupyter_demo.ipynb", "exec"), namespace)
        self.assertEqual(namespace["summary"]["passed"], 1089)

    def test_backend_contract_is_abstract(self):
        with self.assertRaises(TypeError):
            Backend()
        with self.assertRaises(ValueError):
            SimulatedBackend("unknown")


if __name__ == "__main__":
    unittest.main(verbosity=2)
