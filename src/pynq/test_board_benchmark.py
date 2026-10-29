"""Offline tests for the permanent PYNQ benchmark harness."""
import json
from pathlib import Path
import unittest

try:
    from .board_benchmark import select_kat_case, summarize, validate_options
except ImportError:
    from board_benchmark import select_kat_case, summarize, validate_options


HERE = Path(__file__).resolve().parent


class BenchmarkTests(unittest.TestCase):
    def test_summary_keeps_raw_sample_count_and_percentile_policy(self):
        result = summarize(range(1, 21))
        self.assertEqual(result["n"], 20)
        self.assertEqual(result["min"], 1)
        self.assertEqual(result["median"], 10.5)
        self.assertEqual(result["p95"], 19)
        self.assertEqual(result["max"], 20)

    def test_empty_summary_is_rejected(self):
        with self.assertRaises(ValueError):
            summarize([])

    def test_default_kat_is_16_byte_without_ad(self):
        case = select_kat_case()
        self.assertEqual(case["count"], 529)
        self.assertEqual(len(case["PT"]), 16)
        self.assertEqual(len(case["AD"]), 0)
        self.assertEqual(len(case["CT"]), 32)

    def test_invalid_options_are_rejected(self):
        for warmup, repetitions in ((-1, 30), (5, 1), (5, 0)):
            with self.subTest(warmup=warmup, repetitions=repetitions):
                with self.assertRaises(ValueError):
                    validate_options(warmup, repetitions)

    def test_notebook_uses_repository_benchmark(self):
        notebook = json.loads(
            (HERE / "pynq_board_demo.ipynb").read_text(encoding="utf-8")
        )
        source = "\n".join(
            "".join(cell["source"])
            for cell in notebook["cells"]
            if cell["cell_type"] == "code"
        )
        self.assertIn("board_benchmark import run_benchmark", source)
        self.assertIn("/home/xilinx/jupyter_notebooks/amd_fpga_2026", source)
        self.assertIn('repo / "data/pynq"', source)
        self.assertIn('("notebook_" + run_id)', source)
        self.assertNotIn("/tmp/", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
