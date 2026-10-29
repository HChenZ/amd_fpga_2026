"""Offline tests for the permanent V03 hardware error-gate harness."""
import contextlib
import io
import json
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import patch

try:
    from . import board_error_gate as gate_module
    from .board_error_gate import (
        _assert_failure, _make_request, _raw_header_exchange,
        _select_case, _status_name,
    )
    from .mailbox_protocol import Mode, Response, Status
except ImportError:
    import board_error_gate as gate_module
    from board_error_gate import (
        _assert_failure, _make_request, _raw_header_exchange,
        _select_case, _status_name,
    )
    from mailbox_protocol import Mode, Response, Status


HERE = Path(__file__).resolve().parent


class BoardErrorGateTests(unittest.TestCase):
    def test_kat_selection_is_fixed_16_byte_without_ad(self):
        case = _select_case()
        self.assertEqual(case["count"], 529)
        self.assertEqual(len(case["PT"]), 16)
        self.assertEqual(len(case["AD"]), 0)

    def test_failure_status_names_are_stable(self):
        self.assertEqual(_status_name(Status.LENGTH), "LENGTH")
        self.assertEqual(_status_name(Status.INTERNAL), "INTERNAL")

    def test_over_capacity_request_is_encodable_for_header_only_injection(self):
        backend = SimpleNamespace(capabilities=SimpleNamespace(epoch=7))
        request = _make_request(
            backend, _select_case(), 99, data=bytes(17),
            output_capacity=33, mode=Mode.ISE,
        )
        packet = request.encode()
        self.assertEqual(int.from_bytes(packet[36:40], "little"), 17)
        self.assertGreater(len(packet), 48)

    def test_header_exchange_sends_only_48_bytes(self):
        case = _select_case()
        backend = SimpleNamespace(capabilities=SimpleNamespace(epoch=9))
        request = _make_request(
            backend, case, 100, ad=bytes(17), mode=Mode.ISE,
        )

        class StubTransport:
            def __init__(self):
                self.sent = None
                self.acked = None

            def submit(self, packet, deadline):
                self.sent = packet

            def poll(self, deadline):
                return Response(
                    request.epoch, request.request_id, request.operation,
                    request.mode, Status.LENGTH, simulated=False,
                ).encode()

            def ack(self, epoch, request_id, deadline):
                self.acked = (epoch, request_id)

        transport = StubTransport()
        response = _raw_header_exchange(transport, request)
        self.assertEqual(len(transport.sent), 48)
        self.assertEqual(transport.acked, (9, 100))
        self.assertEqual(response.status, Status.LENGTH)
        _assert_failure(response, Status.LENGTH)

    def test_notebook_uses_permanent_harness_and_repository_output(self):
        notebook = json.loads(
            (HERE / "pynq_board_error_gate.ipynb").read_text(encoding="utf-8")
        )
        source = "\n".join(
            "".join(cell["source"])
            for cell in notebook["cells"]
            if cell["cell_type"] == "code"
        )
        self.assertIn("board_error_gate import run_error_gate", source)
        self.assertIn("/home/xilinx/jupyter_notebooks/amd_fpga_2026", source)
        self.assertIn('repo / "data/pynq"', source)
        self.assertIn('("error_gate_" + run_id)', source)
        self.assertNotIn("/tmp/", source)

    def test_harness_emits_auditable_progress_lines(self):
        source = (HERE / "board_error_gate.py").read_text(encoding="utf-8")
        self.assertIn('print("START %s" % name', source)
        self.assertIn('print("PASS  %s" % name', source)
        self.assertIn('print("FAIL  %s:', source)
        self.assertIn('print("V03 ERROR GATE %s:', source)

    def test_cli_writes_failure_report_and_returns_nonzero(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "failure.json"
            with patch.object(gate_module, "run_error_gate", return_value={
                    "kind": "hardware_error_gate",
                    "board_validation": "FAIL",
                    "checks": [{"name": "injected", "status": "FAIL"}],
            }):
                with contextlib.redirect_stdout(io.StringIO()):
                    result = gate_module.main(["--out", str(output)])
            self.assertEqual(result, 1)
            report = json.loads(output.read_text(encoding="utf-8"))
            self.assertEqual(report["board_validation"], "FAIL")


if __name__ == "__main__":
    unittest.main(verbosity=2)
