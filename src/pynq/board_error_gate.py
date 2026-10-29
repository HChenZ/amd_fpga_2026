"""Hardware-only V03 error and recovery gate for the released PYNQ service."""
import argparse
import hashlib
import json
import time
from pathlib import Path

if __package__:
    from .ascon_host_api import BackendTimeoutError
    from .board_benchmark import summarize
    from .board_demo import prepare_hardware
    from .golden_checker import parse_kat
    from .mailbox_protocol import Mode, Operation, Request, Response, Status
else:
    from ascon_host_api import BackendTimeoutError
    from board_benchmark import summarize
    from board_demo import prepare_hardware
    from golden_checker import parse_kat
    from mailbox_protocol import Mode, Operation, Request, Response, Status


DEFAULT_RELEASE = "board/vivado_zynq7000_xc7z020_pynq/release"
DEFAULT_KAT = 529
DEFAULT_STRESS_PER_MODE = 50
MODES = (("sw", 1), ("hw", 2), ("ise", 3))


def _sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def _status_name(status):
    return Status(status).name


def _select_case(count=DEFAULT_KAT):
    case = next((case for case in parse_kat() if case["count"] == count), None)
    if case is None:
        raise ValueError("KAT case not found: %s" % count)
    if len(case["PT"]) != 16 or len(case["AD"]) != 0:
        raise ValueError("error-gate KAT must have PT=16 and AD=0")
    return case


def _make_request(backend, case, request_id, *, operation=Operation.ENCRYPT,
                  mode=Mode.ISE, ad=None, data=None, output_capacity=None,
                  epoch=None):
    ad = case["AD"] if ad is None else ad
    data = case["PT"] if data is None else data
    if operation == Operation.ENCRYPT:
        required = len(data) + 16
        tag = b""
    else:
        required = len(data)
        tag = case["CT"][-16:]
    return Request(
        backend.capabilities.epoch if epoch is None else epoch,
        request_id,
        operation,
        mode,
        case["Key"],
        case["Nonce"],
        ad,
        data,
        required if output_capacity is None else output_capacity,
        tag,
    )


def _raw_exchange(transport, request, timeout_s=10.0):
    deadline = time.monotonic() + timeout_s
    packet = request.encode()
    transport.submit(packet, deadline)
    raw = transport.poll(deadline)
    response = Response.decode(raw)
    if (response.epoch, response.request_id, response.operation, response.mode) != (
            request.epoch, request.request_id, request.operation, request.mode):
        raise AssertionError("raw response identity mismatch")
    transport.ack(response.epoch, response.request_id, deadline)
    return response


def _raw_header_exchange(transport, request, timeout_s=10.0):
    """Send only a header when its declared body is intentionally invalid."""
    deadline = time.monotonic() + timeout_s
    packet = request.encode()
    transport.submit(packet[:48], deadline)
    raw = transport.poll(deadline)
    response = Response.decode(raw)
    if (response.epoch, response.request_id, response.operation, response.mode) != (
            request.epoch, request.request_id, request.operation, request.mode):
        raise AssertionError("raw header response identity mismatch")
    transport.ack(response.epoch, response.request_id, deadline)
    return response


def _assert_failure(response, expected):
    if response.status != expected:
        raise AssertionError("expected %s, got %s" % (
            _status_name(expected), _status_name(response.status)))
    if response.data or response.cycles is not None or response.simulated:
        raise AssertionError("failed response exposed data, cycles or simulation flag")


def _healthy_kats(backend, case):
    """Run every mode after a fault; this is also the recovery postcondition."""
    results = {}
    for mode_name, mode_value in MODES:
        backend.mode = Mode(mode_value)
        backend.name = "mailbox-" + mode_name
        encrypted = backend.encrypt(
            case["Key"], case["Nonce"], case["AD"], case["PT"], timeout_s=10
        )
        ciphertext, tag = encrypted
        if ciphertext + tag != case["CT"]:
            raise AssertionError("%s encryption mismatch after fault" % mode_name)
        plaintext = backend.decrypt(
            case["Key"], case["Nonce"], case["AD"],
            case["CT"][:-16], case["CT"][-16:], timeout_s=10
        )
        if plaintext != case["PT"]:
            raise AssertionError("%s decryption mismatch after fault" % mode_name)
        if backend.simulated:
            raise AssertionError("%s unexpectedly ran in simulated mode" % mode_name)
        results[mode_name] = "PASS"
    return results


def _recover_and_verify(backend, case):
    old_epoch = backend.capabilities.epoch
    backend.recover(timeout_s=15)
    new_epoch = backend.capabilities.epoch
    if new_epoch == old_epoch:
        raise AssertionError("recovery did not change epoch")
    if backend.needs_recovery:
        raise AssertionError("backend remained quarantined after recovery")
    return {
        "old_epoch": old_epoch,
        "new_epoch": new_epoch,
        "kats": _healthy_kats(backend, case),
    }


def _run_check(checks, name, function):
    print("START %s" % name, flush=True)
    try:
        detail = function()
    except Exception as exc:  # The evidence must retain the first real failure.
        checks.append({
            "name": name,
            "status": "FAIL",
            "error_type": type(exc).__name__,
            "error": str(exc),
        })
        print("FAIL  %s: %s: %s" % (
            name, type(exc).__name__, exc), flush=True)
        return False
    checks.append({"name": name, "status": "PASS", "detail": detail})
    print("PASS  %s" % name, flush=True)
    return True


def run_error_gate(release=DEFAULT_RELEASE, stress_per_mode=DEFAULT_STRESS_PER_MODE,
                   kat_count=DEFAULT_KAT):
    if stress_per_mode < 0:
        raise ValueError("stress_per_mode must be non-negative")
    case = _select_case(kat_count)
    print("V03 ERROR GATE START: release=%s kat=%d stress_per_mode=%d" % (
        release, kat_count, stress_per_mode), flush=True)
    backend, transport, overlay, release, manifest = prepare_hardware(release)
    checks = []
    reset_count = 0

    report = {
        "kind": "hardware_error_gate",
        "kat": kat_count,
        "measurement": "board_behavior",
        "stress_per_mode": stress_per_mode,
        "harness": {
            "path": str(Path(__file__).resolve()),
            "sha256": _sha256(__file__),
        },
        "release": {
            "path": str(release),
            "source_commit": manifest.get("source_commit"),
            "source_dirty": manifest.get("source_dirty"),
            "artifact_sha256": {
                name: info["sha256"]
                for name, info in manifest["artifacts"].items()
            },
        },
        "service_initial": transport.last_service,
        "cache_visibility": {
            "status": "NOT_APPLICABLE",
            "reason": "Y01 uses AXI-Lite FIFOs and RV32 UART at uncached MMIO 0x20000000; no shared cacheable data buffer",
        },
        "checks": checks,
        "board_validation": "NOT_RUN",
    }

    def recover():
        nonlocal reset_count
        detail = _recover_and_verify(backend, case)
        reset_count += 1
        return detail

    def initial_health():
        if backend.simulated or transport.last_service.get("simulated"):
            raise AssertionError("initial service reported simulated evidence")
        if transport.last_service.get("selftest_mask") != 7:
            raise AssertionError("initial service selftest mask is not 7")
        return {
            "firmware_id": backend.capabilities.firmware_id,
            "epoch": backend.capabilities.epoch,
            "max_message_bytes": backend.capabilities.max_message_bytes,
            "max_ad_bytes": backend.capabilities.max_ad_bytes,
            "kats": _healthy_kats(backend, case),
        }

    def over_capacity_data():
        request = _make_request(
            backend, case, 1000000, data=bytes(17),
            output_capacity=33, mode=Mode.ISE,
        )
        response = _raw_header_exchange(transport, request)
        _assert_failure(response, Status.LENGTH)
        return {
            "response_status": _status_name(response.status),
            "recovery": recover(),
        }

    def over_capacity_ad():
        request = _make_request(
            backend, case, 1000001, ad=bytes(17), mode=Mode.ISE,
        )
        response = _raw_header_exchange(transport, request)
        _assert_failure(response, Status.LENGTH)
        return {
            "response_status": _status_name(response.status),
            "recovery": recover(),
        }

    def half_frame():
        request = _make_request(
            backend, case, 1000002, data=case["PT"], mode=Mode.ISE,
        )
        packet = request.encode()
        partial = packet[:min(60, len(packet) - 1)]
        transport.regs.push(partial)
        time.sleep(0.25)
        remaining_rx = transport.regs.rx_level()
        if remaining_rx:
            raise AssertionError("half frame unexpectedly produced a response")
        return {
            "partial_bytes": len(partial),
            "response_absent_after_s": 0.25,
            "recovery": recover(),
        }

    def deadline_timeout():
        request = _make_request(backend, case, 1000003, mode=Mode.ISE)
        request_tx_start = transport.regs.bytes_moved()[0]
        try:
            transport.submit(request.encode(), time.monotonic() + 10.0)
            request_tx_end = transport.regs.bytes_moved()[0]
            transport.poll(time.monotonic() - 1.0)
        except BackendTimeoutError:
            pass
        else:
            raise AssertionError("short deadline did not raise BackendTimeoutError")
        return {
            "exception": "BackendTimeoutError",
            "request_bytes_pushed": (request_tx_end - request_tx_start) & 0xFFFF,
            "recovery": recover(),
        }

    def duplicate_request():
        request = _make_request(backend, case, 1000010, mode=Mode.ISE)
        first = _raw_exchange(transport, request)
        if first.status != Status.OK or first.data != case["CT"]:
            raise AssertionError("first duplicate-test request failed")
        second = _raw_exchange(transport, request)
        _assert_failure(second, Status.INTERNAL)
        return {
            "first_status": _status_name(first.status),
            "duplicate_status": _status_name(second.status),
            "recovery": recover(),
        }

    def stale_epoch():
        stale = backend.capabilities.epoch + 1
        request = _make_request(
            backend, case, 1000020, epoch=stale, mode=Mode.ISE,
        )
        response = _raw_exchange(transport, request)
        _assert_failure(response, Status.INTERNAL)
        return {
            "stale_epoch": stale,
            "current_epoch": backend.capabilities.epoch,
            "response_status": _status_name(response.status),
            "recovery": recover(),
        }

    def rx_overflow():
        epoch = backend.capabilities.epoch
        for offset in range(5):
            request = _make_request(
                backend, case, 1000100 + offset, epoch=epoch, mode=Mode.ISE,
            )
            transport.regs.push(request.encode())
            time.sleep(0.03)
        deadline = time.monotonic() + 3.0
        while not transport.regs.rx_overflow() and time.monotonic() < deadline:
            time.sleep(0.01)
        if not transport.regs.rx_overflow():
            raise AssertionError("RX overflow flag was not raised")
        return {
            "requests_without_drain": 5,
            "overflow_observed": True,
            "recovery": recover(),
        }

    def repeated_requests():
        results = {}
        for mode_name, mode_value in MODES:
            backend.mode = Mode(mode_value)
            backend.name = "mailbox-" + mode_name
            cycles = []
            for _ in range(stress_per_mode):
                ciphertext, tag = backend.encrypt(
                    case["Key"], case["Nonce"], case["AD"], case["PT"],
                    timeout_s=10,
                )
                if ciphertext + tag != case["CT"]:
                    raise AssertionError("%s repeated encryption mismatch" % mode_name)
                plaintext = backend.decrypt(
                    case["Key"], case["Nonce"], case["AD"],
                    case["CT"][:-16], case["CT"][-16:], timeout_s=10
                )
                if plaintext != case["PT"]:
                    raise AssertionError("%s repeated decryption mismatch" % mode_name)
                info = backend.cycle_info("encrypt", 16, 0)
                if info.value is not None:
                    cycles.append(info.value)
            results[mode_name] = {
                "encrypt_decrypt_pairs": stress_per_mode,
                "cycle_summary": summarize(cycles) if cycles else "NOT_MEASURED",
            }
        return results

    test_functions = (
        ("initial_health", initial_health),
        ("over_capacity_data_17B", over_capacity_data),
        ("over_capacity_ad_17B", over_capacity_ad),
        ("half_frame_requires_reset", half_frame),
        ("deadline_timeout_requires_recovery", deadline_timeout),
        ("duplicate_request_id_rejected", duplicate_request),
        ("stale_epoch_rejected", stale_epoch),
        ("rx_fifo_overflow_detected", rx_overflow),
        ("repeated_requests", repeated_requests),
    )

    for name, function in test_functions:
        if not _run_check(checks, name, function):
            try:
                reset_count += 1
                _recover_and_verify(backend, case)
            except Exception as recovery_error:
                checks.append({
                    "name": "emergency_recovery_after_failure",
                    "status": "FAIL",
                    "error_type": type(recovery_error).__name__,
                    "error": str(recovery_error),
                })
                break

    expected_reset_count = 7
    report["expected_reset_count"] = expected_reset_count
    report["reset_count"] = reset_count
    if reset_count != expected_reset_count:
        checks.append({
            "name": "expected_recovery_count",
            "status": "FAIL",
            "error_type": "AssertionError",
            "error": "expected %d resets, observed %d" % (
                expected_reset_count, reset_count),
        })
    report["service_final"] = transport.last_service
    report["board_validation"] = (
        "PASS" if all(item["status"] == "PASS" for item in checks) else "FAIL"
    )
    print("V03 ERROR GATE %s: checks=%d resets=%d" % (
        report["board_validation"], len(checks), reset_count), flush=True)
    return report


def write_report(report, output):
    output = Path(output).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return output


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--release", default=DEFAULT_RELEASE)
    parser.add_argument("--kat", type=int, default=DEFAULT_KAT)
    parser.add_argument("--stress-per-mode", type=int, default=DEFAULT_STRESS_PER_MODE)
    parser.add_argument("--out", required=True)
    args = parser.parse_args(argv)
    try:
        report = run_error_gate(
            args.release,
            stress_per_mode=args.stress_per_mode,
            kat_count=args.kat,
        )
    except Exception as exc:
        report = {
            "kind": "hardware_error_gate",
            "board_validation": "FAIL",
            "setup_error_type": type(exc).__name__,
            "setup_error": str(exc),
        }
    output = write_report(report, args.out)
    print("ERROR GATE %s: %s" % (report["board_validation"], output))
    return 0 if report["board_validation"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
