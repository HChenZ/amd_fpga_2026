"""A missing/partial implementation artifact must never count as matching."""
from pathlib import Path
import tempfile
import unittest
from evidence_snapshot import checked_rtl_snapshot


class SnapshotGate(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.source = Path(self.temp.name)/'rtl'
        self.snapshot = Path(self.temp.name)/'snapshot'
        for folder in (self.source, self.snapshot):
            (folder/'ascon').mkdir(parents=True)
            (folder/'top.v').write_bytes(b'module top; endmodule\n')
            (folder/'ascon/key.vh').write_bytes(b'`define PUBLIC_TEST 1\n')

    def test_matching_snapshot(self):
        self.assertEqual(set(checked_rtl_snapshot(self.snapshot, self.source)),
                         {'top.v', 'ascon/key.vh'})

    def test_missing_snapshot(self):
        with self.assertRaises(ValueError):
            checked_rtl_snapshot(self.snapshot/'absent', self.source)

    def test_empty_snapshot(self):
        empty = self.snapshot/'empty'
        empty.mkdir()
        with self.assertRaises(ValueError):
            checked_rtl_snapshot(empty, self.source)

    def test_partial_snapshot(self):
        (self.snapshot/'ascon/key.vh').unlink()
        with self.assertRaises(ValueError):
            checked_rtl_snapshot(self.snapshot, self.source)

    def test_changed_snapshot(self):
        (self.snapshot/'top.v').write_bytes(b'module different; endmodule\n')
        with self.assertRaises(ValueError):
            checked_rtl_snapshot(self.snapshot, self.source)


if __name__ == '__main__':
    unittest.main(verbosity=2)
