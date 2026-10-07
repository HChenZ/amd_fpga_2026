"""Byte-oriented adapters; expected answers are never produced by these tests."""
import ctypes
from collections import defaultdict
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / "data/ascon"
HERE = Path(__file__).resolve().parent
RC12 = (0xF0, 0xE1, 0xD2, 0xC3, 0xB4, 0xA5,
        0x96, 0x87, 0x78, 0x69, 0x5A, 0x4B)


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def verify_sources(derived=True):
    manifest = json.loads((DATA / "provenance.json").read_text(encoding="utf-8"))
    records = list(manifest["files"])
    if derived:
        records += json.loads((DATA / "derived_integrity.json").read_text())["files"]
    for row in records:
        actual = sha256(ROOT / row["path"])
        if actual != row["sha256"]:
            raise ValueError(f"SHA256 {row['path']} expected={row['sha256']} actual={actual}")
    return manifest


def parse_kat():
    text = (DATA / "kat/asconaead128.txt").read_text(encoding="ascii")
    cases = []
    for block in text.strip().split("\n\n"):
        fields = dict(line.split(" =", 1) for line in block.splitlines())
        fields = {k: v.strip() for k, v in fields.items()}
        case = dict(id=f"kat_{int(fields['Count']):04d}", origin="upstream_kat",
                    count=int(fields["Count"]), key=fields["Key"].lower(),
                    nonce=fields["Nonce"].lower(), plaintext=fields["PT"].lower(),
                    ad=fields["AD"].lower())
        ct = bytes.fromhex(fields["CT"])
        mlen = len(bytes.fromhex(case["plaintext"]))
        adlen = len(bytes.fromhex(case["ad"]))
        if len(ct) != mlen + 16:
            raise ValueError(f"Invalid KAT length {case['id']}")
        case.update(plaintext_bytes=mlen, ad_bytes=adlen,
                    ciphertext=ct[:-16].hex(), tag=ct[-16:].hex())
        cases.append(case)
    # This pinned corpus has every pair of lengths 0..32 exactly once.
    if [c["count"] for c in cases] != list(range(1, 1090)):
        raise ValueError("Incomplete/reordered locked KAT corpus")
    if {(c["plaintext_bytes"], c["ad_bytes"]) for c in cases} != {
            (m, a) for m in range(33) for a in range(33)}:
        raise ValueError("Incomplete KAT length matrix")
    return cases


def load_python(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.debug = module.debugpermutation = False
    return module


class PythonBackend:
    def __init__(self, name, path):
        self.name = name
        self.module = load_python(path, name.replace("-", "_"))
        self.metadata = dict(path=str(path.relative_to(ROOT)), sha256=sha256(path))

    def encrypt(self, key, nonce, ad, plaintext):
        return self.module.ascon_encrypt(key, nonce, ad, plaintext, "Ascon-AEAD128")

    def decrypt(self, key, nonce, ad, combined):
        if len(combined) < 16:
            # The repository API asserts on truncated input; report rejection.
            try:
                return self.module.ascon_decrypt(key, nonce, ad, combined, "Ascon-AEAD128")
            except AssertionError:
                return None
        return self.module.ascon_decrypt(key, nonce, ad, combined, "Ascon-AEAD128")

    def permute(self, words, rounds, constant=0):
        state = list(words)
        if rounds == 1:
            # Upstream's one-round API always adds 4b. Pre-XOR changes only
            # the constant-addition input so its S-box/diffusion stay upstream.
            state[2] ^= constant ^ 0x4B
        self.module.ascon_permutation(state, rounds)
        return state


class CBackend:
    def __init__(self, name, source, cc="gcc"):
        self.name = name
        build = ROOT / "build/local/ascon_kat"
        build.mkdir(parents=True, exist_ok=True)
        # Distinct validation/golden callers must never link the same library.
        self.build_directory = tempfile.TemporaryDirectory(prefix=name + "-", dir=build)
        target = Path(self.build_directory.name) / (name + (".dll" if os.name == "nt" else ".so"))
        command = [cc, "-std=c99", "-O2", "-Wall", "-Wextra", "-Werror",
                   "-shared", "-fPIC", "-I", str(source),
                   str(source / "aead.c"), str(HERE / "c_bridge.c"), "-o", str(target)]
        version = subprocess.run([cc, "--version"], capture_output=True, text=True, check=True)
        result = subprocess.run(command, capture_output=True, text=True)
        self.metadata = dict(compiler=version.stdout.splitlines()[0],
                             command=command, exit_code=result.returncode,
                             output=result.stdout + result.stderr,
                             source_hashes={str(p.relative_to(ROOT)): sha256(p)
                                            for p in sorted(source.glob("*")) if p.is_file()},
                             bridge_sha256=sha256(HERE / "c_bridge.c"))
        if result.returncode:
            raise RuntimeError(f"C compile {name}: {result.stdout}{result.stderr}")
        self.metadata["binary_sha256"] = sha256(target)
        self.lib = ctypes.CDLL(str(target))
        ptr = ctypes.POINTER(ctypes.c_ubyte)
        length = ctypes.POINTER(ctypes.c_ulonglong)
        self.lib.crypto_aead_encrypt.argtypes = [ptr, length, ptr, ctypes.c_ulonglong,
                                                ptr, ctypes.c_ulonglong, ptr, ptr, ptr]
        self.lib.crypto_aead_decrypt.argtypes = [ptr, length, ptr, ptr, ctypes.c_ulonglong,
                                                ptr, ctypes.c_ulonglong, ptr, ptr]
        self.lib.crypto_aead_encrypt.restype = ctypes.c_int
        self.lib.crypto_aead_decrypt.restype = ctypes.c_int
        word_ptr = ctypes.POINTER(ctypes.c_uint64)
        self.lib.golden_permute.argtypes = [word_ptr, word_ptr, ctypes.c_int, ctypes.c_ubyte]
        self.lib.golden_permute.restype = None

    @staticmethod
    def buffer(value):
        result = (ctypes.c_ubyte * max(1, len(value)))()
        result[:len(value)] = value
        return result

    def encrypt(self, key, nonce, ad, plaintext):
        out = (ctypes.c_ubyte * (len(plaintext) + 16))()
        length = ctypes.c_ulonglong()
        status = self.lib.crypto_aead_encrypt(out, ctypes.byref(length), self.buffer(plaintext),
                    len(plaintext), self.buffer(ad), len(ad), None,
                    self.buffer(nonce), self.buffer(key))
        if status != 0 or length.value != len(out):
            raise ValueError(f"encrypt rc={status} length={length.value} expected={len(out)}")
        return bytes(out)

    def decrypt_raw(self, key, nonce, ad, combined):
        capacity = max(1, len(combined))
        out = (ctypes.c_ubyte * capacity)(*([0xA5] * capacity))
        length = ctypes.c_ulonglong(0)
        status = self.lib.crypto_aead_decrypt(out, ctypes.byref(length), None,
                    self.buffer(combined), len(combined), self.buffer(ad), len(ad),
                    self.buffer(nonce), self.buffer(key))
        if length.value > capacity:
            raise ValueError("C returned an out-of-bounds length")
        return status, length.value, bytes(out[:length.value])

    def decrypt(self, key, nonce, ad, combined):
        status, _, candidate = self.decrypt_raw(key, nonce, ad, combined)
        # Test adapter only: never expose a candidate when authentication fails.
        return candidate if status == 0 else None

    def permute(self, words, rounds, constant=0):
        if rounds not in (1, 8, 12) or not 0 <= constant <= 255:
            raise ValueError("Expected round, P8 or P12")
        inp = (ctypes.c_uint64 * 5)(*words)
        out = (ctypes.c_uint64 * 5)()
        self.lib.golden_permute(out, inp, rounds, constant)
        return list(out)


BACKENDS = ("upstream-c", "upstream-python", "repository-c", "repository-python")


def backend(name, cc="gcc"):
    if name == "upstream-c":
        return CBackend(name, HERE / "reference/ascon_c", cc)
    if name == "repository-c":
        return CBackend(name, ROOT / "ascon/ascon_c/aead", cc)
    if name == "upstream-python":
        return PythonBackend(name, HERE / "reference/pyascon/ascon.py")
    if name == "repository-python":
        return PythonBackend(name, ROOT / "ascon/pyascon/ascon.py")
    raise ValueError(name)


def first_difference(expected, actual):
    if actual is None:
        return "expected=authenticated plaintext actual=authentication failure"
    for i in range(max(len(expected), len(actual))):
        e = f"{expected[i]:02x}" if i < len(expected) else "<end>"
        a = f"{actual[i]:02x}" if i < len(actual) else "<end>"
        if e != a:
            return f"byte={i} expected={e} actual={a} (zero-based)"
    return None


def negative_cases(case):
    combined = bytes.fromhex(case["ciphertext"] + case["tag"])
    positions = [("tag_first", len(combined) - 16), ("tag_last", len(combined) - 1)]
    if case["plaintext_bytes"]:
        positions += [("ciphertext_first", 0), ("ciphertext_last", len(combined) - 17)]
    rows = []
    for kind, offset in positions:
        bad = bytearray(combined)
        bad[offset] ^= 1
        rows.append(dict(kind=kind, byte_offset=offset, xor_mask="01",
                         ciphertext_and_tag=bad.hex(), expected="fail"))
    return rows


class Report:
    def __init__(self):
        self.lines = []
        self.results = []
        self.metadata = dict(python=sys.version, platform=platform.platform(),
            evidence_kind="host_software", source_head=subprocess.check_output(
                ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip())
        self.metadata["validation_source_hashes"] = {
            str(p.relative_to(ROOT)): sha256(p) for p in sorted(HERE.glob("*.py"))}

    def record(self, name, detail=None):
        status = "FAIL" if detail else "PASS"
        line = f"{status} {name}" + (f" {detail}" if detail else "")
        print(line)
        self.lines.append(line)
        self.results.append(dict(name=name, status=status, detail=detail))

    def save(self, path):
        path = Path(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        failed = sum(r["status"] == "FAIL" for r in self.results)
        summary = dict(passed=len(self.results) - failed, failed=failed,
                       exit_code=1 if failed else 0)
        line = f"{'FAIL' if failed else 'PASS'} SUMMARY {summary}"
        print(line)
        groups = defaultdict(lambda: dict(passed=0, failed=0))
        for row in self.results:
            group = row["name"].split("/", 1)[0]
            groups[group]["failed" if row["status"] == "FAIL" else "passed"] += 1
        path.write_text(json.dumps(dict(metadata=self.metadata, summary=summary,
                            groups=dict(groups), failures=[r for r in self.results
                            if r["status"] == "FAIL"]), indent=2) + "\n", encoding="utf-8")
        path.with_suffix(".log").write_text("\n".join(self.lines + [line]) + "\n",
                                            encoding="utf-8")
        return summary["exit_code"]


def check_aead(report, impl, cases, negatives=True):
    for case in cases:
        name = f"{impl.name}/{case['id']}"
        k, n, ad, pt = (bytes.fromhex(case[f]) for f in ("key", "nonce", "ad", "plaintext"))
        if len(k) != 16 or len(n) != 16 or len(pt) != case["plaintext_bytes"] or len(ad) != case["ad_bytes"]:
            raise ValueError(f"Invalid explicit length {name}")
        expected = bytes.fromhex(case["ciphertext"] + case["tag"])
        if len(expected) != len(pt) + 16:
            raise ValueError(f"Invalid ciphertext/tag length {name}")
        for op, answer, call in [("encrypt", expected, lambda: impl.encrypt(k, n, ad, pt)),
                                 ("decrypt_verify", pt, lambda: impl.decrypt(k, n, ad, expected))]:
            try:
                report.record(f"{name}/{op}", first_difference(answer, call()))
            except Exception as exc:
                report.record(f"{name}/{op}", f"{type(exc).__name__}: {exc}")
        if negatives:
            for negative in case.get("negative", negative_cases(case)):
                try:
                    value = impl.decrypt(k, n, ad, bytes.fromhex(negative["ciphertext_and_tag"]))
                    report.record(f"{name}/{negative['kind']}",
                                  None if value is None else f"expected=fail actual={value.hex()}")
                except Exception as exc:
                    report.record(f"{name}/{negative['kind']}", f"{type(exc).__name__}: {exc}")
