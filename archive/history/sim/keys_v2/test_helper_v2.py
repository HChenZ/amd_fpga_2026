import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("helper", ROOT / "src/pynq/puf_helper_v2.py")
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


class HelperTests(unittest.TestCase):
    def test_roundtrip_and_rejections(self):
        binding = dict(board_id="test-board", build_sha256="a" * 64,
                       parameters=dict(counter_bits=20, window_cycles=1024, samples=3, min_bits=64))
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "helper.json"
            helper.save_helper(path, **binding, reference="5" * 32, mask="f" * 32)
            pristine = path.read_bytes()
            self.assertEqual(helper.load_helper(path, **binding)["reference"], "5" * 32)
            for field, bad in (("board_id", "other"), ("build_sha256", "b" * 64),
                               ("parameters", dict(binding["parameters"], samples=5))):
                with self.assertRaises(ValueError):
                    helper.load_helper(path, **dict(binding, **{field: bad}))
            for field, value in (("reference", "a" * 32), ("interface_version", 1),
                                 ("mask", "0" * 32), ("extra", "bad")):
                envelope = json.loads(pristine)
                envelope["payload"][field] = value
                path.write_text(json.dumps(envelope), encoding="ascii")
                with self.assertRaises(ValueError):
                    helper.load_helper(path, **binding)
            for raw in (b'{"payload":{},"payload":{}}', b"{}", b"x" * 8193):
                path.write_bytes(raw)
                with self.assertRaises(ValueError):
                    helper.load_helper(path, **binding)
            path.write_bytes(pristine)
            self.assertEqual(helper.load_helper(path, **binding)["mask"], "f" * 32)


if __name__ == "__main__":
    unittest.main()
