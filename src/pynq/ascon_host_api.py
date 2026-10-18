"""Board-independent Ascon-AEAD128 API. No PYNQ package or register map assumed."""
from abc import ABC, abstractmethod
from dataclasses import dataclass
import hashlib
import math
from pathlib import Path
import time
from types import ModuleType

ROOT = Path(__file__).resolve().parents[2]
REFERENCE_PATH = "sim/ascon/reference/pyascon/ascon.py"
REFERENCE_SHA256 = "b799653fc09e56fc4eb72c90b3574b967b3ead4c337b2402123148d5b1873eda"
KAT_PATH = "data/ascon/kat/asconaead128.txt"
KAT_SHA256 = "bbbc34692fe05e5fda0a3b025585622ab3e3747495e5e3655b29aae8c2a4bd33"


class AsconError(Exception):
    """Base class for explicit host failures (messages never include secrets)."""


class InvalidLengthError(AsconError, ValueError):
    pass


class AuthenticationError(AsconError):
    pass


class BackendTimeoutError(AsconError, TimeoutError):
    pass


class BusError(AsconError, OSError):
    pass


class BackendProtocolError(AsconError):
    pass


class ReferenceIntegrityError(AsconError):
    pass


def checked_bytes(relative_path, expected_hash):
    value = (ROOT / relative_path).read_bytes()
    if hashlib.sha256(value).hexdigest() != expected_hash:
        raise ReferenceIntegrityError(f"SHA256 mismatch: {relative_path}")
    return value


def load_python(relative_path, expected_hash=None):
    """Read/execute locally, without creating bytecode in read-only source trees."""
    source = (checked_bytes(relative_path, expected_hash) if expected_hash
              else (ROOT / relative_path).read_bytes())
    module = ModuleType("ascon_host_reference")
    module.__file__ = str(ROOT / relative_path)
    exec(compile(source, module.__file__, "exec"), module.__dict__)
    module.debug = module.debugpermutation = False
    return module


@dataclass(frozen=True)
class CycleInfo:
    value: int | None = None
    status: str = "not_measured"
    source: str | None = None
    scope: str = "not_measured"


@dataclass(frozen=True)
class EncryptionResult:
    ciphertext: bytes
    tag: bytes
    cycles: int | None
    cycle_info: CycleInfo
    backend: str
    simulated: bool


@dataclass(frozen=True)
class DecryptionResult:
    plaintext: bytes
    cycles: int | None
    cycle_info: CycleInfo
    backend: str
    simulated: bool


def cycle_table():
    """Historical warm RV32 mcycle samples, NOT measurements of this Python call."""
    base = "data/ascon/results/key_lifecycle/"
    return {
        mode: CycleInfo(value, "simulated", base + stem + ".log",
                        "warm RV32 16B encrypt, AD=0; " + scope)
        for mode, value, stem, scope in (
            ("sw", 17353, "sw_timing_acb_sw", "software AEAD"),
            ("hw", 670, "hw_timing_acb_hw", "full MMIO round trip"),
            ("ise", 2496, "ise_timing_acb_ise", "CPU AEAD with permutation ISE"))
    }


class Backend(ABC):
    """An authenticated, bounded operation; future hardware must enforce deadlines.

    max_message_bytes/max_ad_bytes are actual backend capacities, not port widths.
    decrypt must raise AuthenticationError before returning any failed plaintext.
    timeout_s is a finite positive deadline budget, including transport/polling.
    """
    name = "backend"
    simulated = False
    max_message_bytes = 16
    max_ad_bytes = 16

    @abstractmethod
    def encrypt(self, key, nonce, ad, plaintext, *, timeout_s):
        """Return (ciphertext: bytes, tag: bytes), or raise a specific exception."""

    @abstractmethod
    def decrypt(self, key, nonce, ad, ciphertext, tag, *, timeout_s):
        """Return authenticated bytes only; never return a failure candidate."""

    def cycle_info(self, operation, message_bytes, ad_bytes):
        return CycleInfo()


class SimulatedBackend(Backend):
    """Locked upstream Python reference; mode only selects historical cycle data."""
    simulated = True
    max_message_bytes = 65536
    max_ad_bytes = 65536

    def __init__(self, mode="ise"):
        if mode not in cycle_table():
            raise ValueError("mode must be sw, hw or ise")
        self.mode = mode
        self.name = "simulated-" + mode
        self.reference = load_python(REFERENCE_PATH, REFERENCE_SHA256)

    def encrypt(self, key, nonce, ad, plaintext, *, timeout_s):
        combined = self.reference.ascon_encrypt(key, nonce, ad, plaintext, "Ascon-AEAD128")
        return combined[:-16], combined[-16:]

    def decrypt(self, key, nonce, ad, ciphertext, tag, *, timeout_s):
        plaintext = self.reference.ascon_decrypt(key, nonce, ad, ciphertext + tag,
                                                "Ascon-AEAD128")
        if plaintext is None:
            raise AuthenticationError("authentication failed")
        return plaintext

    def cycle_info(self, operation, message_bytes, ad_bytes):
        if (operation, message_bytes, ad_bytes) == ("encrypt", 16, 0):
            return cycle_table()[self.mode]
        return CycleInfo()


class AsconHost:
    def __init__(self, backend=None):
        self.backend = backend if backend is not None else SimulatedBackend()

    def _validate(self, key, nonce, ad, data, timeout_s):
        for name, value in (("key", key), ("nonce", nonce), ("ad", ad), ("data", data)):
            if not isinstance(value, bytes):
                raise TypeError(f"{name} must be bytes")
        if len(key) != 16 or len(nonce) != 16:
            raise InvalidLengthError("key and nonce must each be 16 bytes")
        if len(ad) > self.backend.max_ad_bytes or len(data) > self.backend.max_message_bytes:
            raise InvalidLengthError("input exceeds backend capacity")
        if (isinstance(timeout_s, bool) or not isinstance(timeout_s, (int, float))
                or not math.isfinite(timeout_s) or timeout_s <= 0):
            raise ValueError("timeout_s must be finite and positive")

    def _call(self, method, *args, timeout_s):
        start = time.monotonic()
        try:
            result = method(*args, timeout_s=timeout_s)
        except AsconError:
            raise
        except TimeoutError:
            raise BackendTimeoutError("backend deadline expired") from None
        except OSError:
            raise BusError("backend transport failed") from None
        # Synchronous simulation cannot preempt Python. Discard a late result.
        if time.monotonic() - start > timeout_s:
            raise BackendTimeoutError("backend deadline expired")
        return result

    def encrypt(self, key, nonce, ad, plaintext, *, timeout_s=5.0):
        self._validate(key, nonce, ad, plaintext, timeout_s)
        result = self._call(self.backend.encrypt, key, nonce, ad, plaintext,
                            timeout_s=timeout_s)
        if not isinstance(result, tuple) or len(result) != 2:
            raise BackendProtocolError("malformed encryption response")
        ciphertext, tag = result
        if (not isinstance(ciphertext, bytes) or not isinstance(tag, bytes)
                or len(ciphertext) != len(plaintext) or len(tag) != 16):
            raise BackendProtocolError("invalid ciphertext/tag length or type")
        info = self.backend.cycle_info("encrypt", len(plaintext), len(ad))
        return EncryptionResult(ciphertext, tag, info.value, info,
                                self.backend.name, self.backend.simulated)

    def decrypt(self, key, nonce, ad, ciphertext, tag, *, timeout_s=5.0):
        self._validate(key, nonce, ad, ciphertext, timeout_s)
        if not isinstance(tag, bytes):
            raise TypeError("tag must be bytes")
        if len(tag) != 16:
            raise InvalidLengthError("tag must be 16 bytes")
        plaintext = self._call(self.backend.decrypt, key, nonce, ad, ciphertext, tag,
                               timeout_s=timeout_s)
        if not isinstance(plaintext, bytes) or len(plaintext) != len(ciphertext):
            raise BackendProtocolError("invalid authenticated plaintext response")
        info = self.backend.cycle_info("decrypt", len(ciphertext), len(ad))
        return DecryptionResult(plaintext, info.value, info,
                                self.backend.name, self.backend.simulated)
