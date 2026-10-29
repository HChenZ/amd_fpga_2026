"""Repeatable PYNQ warm benchmark for the released SW/HW/ISE service."""
import argparse
import json
import statistics
import time
from pathlib import Path

if __package__:
    from .board_demo import prepare_hardware
    from .ascon_host_api import AsconHost
    from .golden_checker import parse_kat
    from .mailbox_protocol import Mode
else:
    from board_demo import prepare_hardware
    from ascon_host_api import AsconHost
    from golden_checker import parse_kat
    from mailbox_protocol import Mode


DEFAULT_RELEASE = "board/vivado_zynq7000_xc7z020_pynq/release"
DEFAULT_KAT = 529
DEFAULT_WARMUP = 5
DEFAULT_REPETITIONS = 30
MODE_VALUES = (("sw", 1), ("hw", 2), ("ise", 3))


def summarize(values):
    """Return reproducible descriptive statistics while retaining raw values."""
    values = sorted(int(value) for value in values)
    if not values:
        raise ValueError("summary requires at least one sample")
    return {
        "n": len(values),
        "min": values[0],
        "median": statistics.median(values),
        "mean": round(statistics.mean(values), 3),
        "p95": values[int(0.95 * (len(values) - 1))],
        "max": values[-1],
    }


def select_kat_case(count=DEFAULT_KAT):
    """Select a deterministic 16-byte, AD=0 public official KAT."""
    case = next((case for case in parse_kat() if case["count"] == count), None)
    if case is None:
        raise ValueError("KAT case not found: %s" % count)
    if len(case["PT"]) != 16 or len(case["AD"]) != 0:
        raise ValueError("benchmark KAT must have PT=16 and AD=0")
    return case


def validate_options(warmup, repetitions):
    if warmup < 0:
        raise ValueError("warmup must be non-negative")
    if repetitions < 2:
        raise ValueError("repetitions must be at least 2")


def _run_once(host, case):
    key = case["Key"]
    nonce = case["Nonce"]
    ad = case["AD"]
    plaintext = case["PT"]
    expected = case["CT"]

    wall_start = time.perf_counter_ns()
    encrypted = host.encrypt(key, nonce, ad, plaintext, timeout_s=10)
    encrypt_wall_ns = time.perf_counter_ns() - wall_start
    if encrypted.simulated or encrypted.ciphertext + encrypted.tag != expected:
        raise AssertionError("encrypt output does not match locked KAT")
    if not isinstance(encrypted.cycles, int) or encrypted.cycles <= 0:
        raise AssertionError("encrypt mcycle evidence is missing")

    wall_start = time.perf_counter_ns()
    decrypted = host.decrypt(
        key, nonce, ad, expected[:-16], expected[-16:], timeout_s=10
    )
    decrypt_wall_ns = time.perf_counter_ns() - wall_start
    if decrypted.simulated or decrypted.plaintext != plaintext:
        raise AssertionError("decrypt output does not match locked KAT")
    if not isinstance(decrypted.cycles, int) or decrypted.cycles <= 0:
        raise AssertionError("decrypt mcycle evidence is missing")

    return {
        "encrypt_cycles": encrypted.cycles,
        "decrypt_cycles": decrypted.cycles,
        "encrypt_wall_ns": encrypt_wall_ns,
        "decrypt_wall_ns": decrypt_wall_ns,
    }


def run_benchmark(release=DEFAULT_RELEASE, warmup=DEFAULT_WARMUP,
                  repetitions=DEFAULT_REPETITIONS, kat_count=DEFAULT_KAT):
    """Execute the same public 16B KAT repeatedly in one live overlay session."""
    validate_options(warmup, repetitions)
    case = select_kat_case(kat_count)
    backend, transport, overlay, release, manifest = prepare_hardware(release)
    host = AsconHost(backend)

    report = {
        "kind": "hardware_warm_benchmark",
        "kat": kat_count,
        "plaintext_bytes": len(case["PT"]),
        "ad_bytes": len(case["AD"]),
        "warmup": warmup,
        "repetitions": repetitions,
        "measurement_scope": "firmware AEAD mcycle; excludes PS/UART",
        "wall_time_scope": "PS call around mailbox transaction; descriptive only",
        "release": {
            "path": str(release),
            "source_commit": manifest.get("source_commit"),
            "source_dirty": manifest.get("source_dirty"),
            "artifact_sha256": {
                name: info["sha256"]
                for name, info in manifest["artifacts"].items()
            },
        },
        "service": transport.last_service,
        "modes": {},
        "board_validation": "NOT_RUN",
    }

    for mode_name, mode_value in MODE_VALUES:
        backend.mode = Mode(mode_value)
        backend.name = "mailbox-" + mode_name

        for _ in range(warmup):
            _run_once(host, case)

        samples = [_run_once(host, case) for _ in range(repetitions)]
        encrypt_cycles = [sample["encrypt_cycles"] for sample in samples]
        decrypt_cycles = [sample["decrypt_cycles"] for sample in samples]
        encrypt_wall_ns = [sample["encrypt_wall_ns"] for sample in samples]
        decrypt_wall_ns = [sample["decrypt_wall_ns"] for sample in samples]
        report["modes"][mode_name] = {
            "encrypt": {
                "summary": summarize(encrypt_cycles),
                "cycles_per_byte_median": round(
                    statistics.median(encrypt_cycles) / len(case["PT"]), 3
                ),
                "raw_cycles": encrypt_cycles,
                "wall_ns_summary": summarize(encrypt_wall_ns),
                "raw_wall_ns": encrypt_wall_ns,
            },
            "decrypt": {
                "summary": summarize(decrypt_cycles),
                "cycles_per_byte_median": round(
                    statistics.median(decrypt_cycles) / len(case["PT"]), 3
                ),
                "raw_cycles": decrypt_cycles,
                "wall_ns_summary": summarize(decrypt_wall_ns),
                "raw_wall_ns": decrypt_wall_ns,
            },
        }
        print("%s encrypt median=%s, decrypt median=%s" % (
            mode_name,
            report["modes"][mode_name]["encrypt"]["summary"]["median"],
            report["modes"][mode_name]["decrypt"]["summary"]["median"],
        ), flush=True)

    software = report["modes"]["sw"]
    report["speedup_median_vs_sw"] = {}
    for mode_name in ("hw", "ise"):
        mode = report["modes"][mode_name]
        report["speedup_median_vs_sw"][mode_name] = {
            "encrypt": round(
                software["encrypt"]["summary"]["median"] /
                mode["encrypt"]["summary"]["median"], 3
            ),
            "decrypt": round(
                software["decrypt"]["summary"]["median"] /
                mode["decrypt"]["summary"]["median"], 3
            ),
        }

    report["board_validation"] = "PASS"
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
    parser.add_argument("--warmup", type=int, default=DEFAULT_WARMUP)
    parser.add_argument("--repetitions", type=int, default=DEFAULT_REPETITIONS)
    parser.add_argument("--out", required=True)
    args = parser.parse_args(argv)
    report = run_benchmark(
        args.release, warmup=args.warmup,
        repetitions=args.repetitions, kat_count=args.kat
    )
    output = write_report(report, args.out)
    print("WARM BENCHMARK PASS: %s" % output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
