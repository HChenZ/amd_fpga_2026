"""Diagnostic full-reference helper persistence. NOT a secure sketch.

SHA-256 detects accidental corruption, not malicious replacement. Caller-supplied
board/build/parameters must come from trusted live configuration, not this file.
"""
import hashlib
import json
import os
from pathlib import Path
import tempfile

VERSION = 2
PARAMETERS = {"counter_bits", "window_cycles", "samples", "min_bits"}


def _canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode("ascii")


def _hex(value, length):
    return isinstance(value, str) and len(value) == length and all(c in "0123456789abcdef" for c in value)


def _validate(payload):
    if not isinstance(payload, dict) or set(payload) != {
        "interface_version", "purpose", "board_id", "build_sha256", "parameters", "reference", "mask"
    }:
        raise ValueError("invalid helper schema")
    if type(payload["interface_version"]) is not int or payload["interface_version"] != VERSION:
        raise ValueError("unsupported interface version")
    if payload["purpose"] != "diagnostic_full_reference_not_secret":
        raise ValueError("not a diagnostic helper")
    if not isinstance(payload["board_id"], str) or not 1 <= len(payload["board_id"]) <= 128:
        raise ValueError("invalid board identity")
    if not _hex(payload["build_sha256"], 64):
        raise ValueError("invalid build SHA-256")
    for name in ("reference", "mask"):
        if not _hex(payload[name], 32):
            raise ValueError("invalid " + name)
    params = payload["parameters"]
    if not isinstance(params, dict) or set(params) != PARAMETERS:
        raise ValueError("invalid sampling parameters")
    if any(type(v) is not int or v <= 0 for v in params.values()):
        raise ValueError("parameters must be positive integers")
    if not 2 <= params["counter_bits"] <= 32 or not 1 <= params["min_bits"] <= 128:
        raise ValueError("parameters out of range")
    if bin(int(payload["mask"], 16)).count("1") < params["min_bits"]:
        raise ValueError("insufficient selected bits")


def save_helper(path, *, board_id, build_sha256, parameters, reference, mask):
    payload = dict(interface_version=VERSION, purpose="diagnostic_full_reference_not_secret",
                   board_id=board_id, build_sha256=build_sha256, parameters=dict(parameters),
                   reference=reference, mask=mask)
    _validate(payload)
    envelope = {"payload": payload, "sha256": hashlib.sha256(_canonical(payload)).hexdigest()}
    path = Path(path)
    fd, temporary = tempfile.mkstemp(prefix=path.name + ".", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="ascii", newline="\n") as stream:
            json.dump(envelope, stream, sort_keys=True, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def _unique_object(pairs):
    result = {}
    for k, v in pairs:
        if k in result:
            raise ValueError("duplicate JSON key")
        result[k] = v
    return result


def load_helper(path, *, board_id, build_sha256, parameters):
    raw = Path(path).read_bytes()
    if len(raw) > 8192:
        raise ValueError("oversized helper")
    envelope = json.loads(raw, object_pairs_hook=_unique_object)
    if not isinstance(envelope, dict) or set(envelope) != {"payload", "sha256"}:
        raise ValueError("invalid envelope")
    payload = envelope["payload"]
    _validate(payload)
    if envelope["sha256"] != hashlib.sha256(_canonical(payload)).hexdigest():
        raise ValueError("helper checksum mismatch")
    if (payload["board_id"], payload["build_sha256"], payload["parameters"]) != (board_id, build_sha256, parameters):
        raise ValueError("helper board/build/parameter binding mismatch")
    return payload
