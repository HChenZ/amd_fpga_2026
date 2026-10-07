"""Verify that real validation catches corrupted output and returns nonzero."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


class HarnessRejectionTests(unittest.TestCase):
    def run_injected(self, injection):
        with tempfile.TemporaryDirectory() as directory:
            report = Path(directory) / "injected.json"
            program = (
                "import sys\n"
                f"sys.path.insert(0, {str(HERE)!r})\n"
                "import support, run_validation\n"
                + injection + "\n"
                f"raise SystemExit(run_validation.main(['--backends', 'repository-python', "
                f"'--report', {str(report)!r}]))\n"
            )
            result = subprocess.run([sys.executable, "-c", program], cwd=ROOT,
                                    text=True, capture_output=True)
            self.assertEqual(result.returncode, 1, result.stderr)
            saved = json.loads(report.read_text())
            self.assertGreater(saved["summary"]["failed"], 0)
            return result.stdout, saved

    def test_first_wrong_ciphertext_byte(self):
        output, saved = self.run_injected(
            "original = support.PythonBackend.encrypt\n"
            "injected = False\n"
            "def faulty(self, *args):\n"
            "    global injected\n"
            "    value = original(self, *args)\n"
            "    if not injected:\n"
            "        injected = True\n"
            "        return bytes([value[0] ^ 1]) + value[1:]\n"
            "    return value\n"
            "support.PythonBackend.encrypt = faulty")
        self.assertIn("FAIL repository-python/kat_0001/encrypt byte=0 expected=4f actual=4e", output)
        self.assertEqual(saved["summary"]["failed"], 1)

    def test_invalid_tags_must_not_be_accepted(self):
        output, _ = self.run_injected(
            "original = support.PythonBackend.decrypt\n"
            "def faulty(self, *args):\n"
            "    value = original(self, *args)\n"
            "    return b'' if value is None else value\n"
            "support.PythonBackend.decrypt = faulty")
        self.assertIn("FAIL repository-python/kat_0001/tag_first expected=fail actual=", output)

    def test_integrity_failure_is_not_skipped(self):
        output, saved = self.run_injected(
            "support.sha256 = lambda path: '0' * 64")
        self.assertIn("FAIL setup_or_integrity ValueError: SHA256", output)
        self.assertEqual(saved["summary"]["passed"], 0)


class GoldenInterfaceTests(unittest.TestCase):
    def test_cli_matches_frozen_expectations(self):
        data = ROOT / "data/ascon"
        rows = json.loads((data / "permutation_cases.json").read_text())["cases"]
        for operation, row in zip(("round", "p8", "p12"), (rows[0], rows[12], rows[13])):
            with self.subTest(operation=operation):
                result = subprocess.run([sys.executable, str(HERE / "golden.py"), operation,
                    "--state-bus", row["input_bus"], "--constant", row["constant"],
                    "--format", "hex"], cwd=ROOT, text=True, capture_output=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(result.stdout.strip(), row["expected_bus"])
        aead = json.loads((data / "aead_cases.json").read_text())["cases"][-1]
        result = subprocess.run([sys.executable, str(HERE / "golden.py"), "aead",
            "--case", aead["id"], "--format", "hex"], cwd=ROOT, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stdout.strip(), aead["ciphertext"] + aead["tag"])

    def test_readmemh_packing_matches_json_words(self):
        data = ROOT / "data/ascon"
        rows = json.loads((data / "permutation_cases.json").read_text())["cases"]
        lines = (data / "permutation.mem").read_text().splitlines()
        self.assertEqual(len(lines), len(rows))
        for line, row in zip(lines, rows):
            packed = int(line, 16)
            self.assertEqual(len(line), 164)
            self.assertEqual(packed >> 648, row["rounds"])
            self.assertEqual((packed >> 640) & 255, int(row["constant"], 16))
            for i in range(5):
                self.assertEqual((packed >> (320 + 64*i)) & ((1 << 64) - 1),
                                 int(row["input_words"][i], 16))
                self.assertEqual((packed >> (64*i)) & ((1 << 64) - 1),
                                 int(row["expected_words"][i], 16))


if __name__ == "__main__":
    unittest.main(verbosity=2)
