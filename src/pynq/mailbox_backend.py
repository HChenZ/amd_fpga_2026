"""Transport-neutral Y01 draft adapter and an explicitly simulated single-slot peer."""
from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass
import math
import threading
import time

if __package__:
    from .ascon_host_api import (AsconError, AuthenticationError, Backend, BackendProtocolError,
                                BackendTimeoutError, BusError, CycleInfo, InvalidLengthError,
                                SimulatedBackend)
    from .mailbox_protocol import (MAX_BYTES, UINT64_MAX, VERSION, Mode, Operation,
                                  Request, Response, Status, require)
else:
    from ascon_host_api import (AsconError, AuthenticationError, Backend, BackendProtocolError,
                               BackendTimeoutError, BusError, CycleInfo, InvalidLengthError,
                               SimulatedBackend)
    from mailbox_protocol import (MAX_BYTES, UINT64_MAX, VERSION, Mode, Operation,
                                 Request, Response, Status, require)


class MailboxBusyError(AsconError):
    pass


@dataclass(frozen=True)
class Capabilities:
    version: int
    epoch: int
    max_message_bytes: int
    max_ad_bytes: int
    modes: tuple[Mode, ...]
    simulated: bool
    firmware_id: str

    def validate(self):
        require(self.version == VERSION, "mailbox protocol version mismatch")
        require(type(self.epoch) is int and 1 <= self.epoch <= UINT64_MAX, "invalid handshake epoch")
        for value in (self.max_message_bytes, self.max_ad_bytes):
            require(type(value) is int and 0 <= value <= MAX_BYTES, "invalid advertised capacity")
        require(bool(self.modes) and len(set(self.modes)) == len(self.modes)
                and all(mode in tuple(Mode) for mode in self.modes), "invalid advertised modes")
        require(type(self.simulated) is bool and isinstance(self.firmware_id, str)
                and 0 < len(self.firmware_id) <= 128, "invalid firmware identity")


class Transport(ABC):
    """One adapter owns one slot. Every call MUST honor the absolute deadline.

    submit publishes an immutable request after release/flush; poll returns an
    atomic acquired response or None. ack releases/scrubs the slot. reset must
    quiesce old work and change epoch before allowing buffer reuse.
    """
    @abstractmethod
    def hello(self, deadline):
        pass

    @abstractmethod
    def submit(self, packet, deadline):
        pass

    @abstractmethod
    def poll(self, deadline):
        pass

    @abstractmethod
    def ack(self, epoch, request_id, deadline):
        pass

    @abstractmethod
    def reset(self, deadline):
        pass


class MemoryTransport(Transport):
    """In-process peer, NOT RTL/cache/bus emulation or real hardware timing."""
    def __init__(self, *, max_message_bytes=32, max_ad_bytes=32,
                 modes=(Mode.SW, Mode.HW, Mode.ISE), polls_to_complete=1, clock=time.monotonic):
        require(type(polls_to_complete) is int and polls_to_complete >= 0, "invalid poll delay")
        self.clock = clock
        self.polls_to_complete = polls_to_complete
        self.capabilities = Capabilities(VERSION, 1, max_message_bytes, max_ad_bytes,
                                         tuple(modes), True, "simulated-locked-python-reference")
        self.capabilities.validate()
        self.reference = SimulatedBackend()
        self.state = "idle"
        self._request = self._response = None
        self._last_id = 0

    def _deadline(self, deadline):
        if self.clock() >= deadline:
            raise BackendTimeoutError("mailbox deadline expired")

    def hello(self, deadline):
        self._deadline(deadline)
        return self.capabilities

    def submit(self, packet, deadline):
        self._deadline(deadline)
        if self.state != "idle":
            raise MailboxBusyError("mailbox slot is owned by an unfinished request")
        request = Request.decode(packet)
        require(request.epoch == self.capabilities.epoch, "stale request epoch")
        require(request.request_id > self._last_id, "duplicate or reordered request id")
        self._last_id = request.request_id
        self._request = request
        self._response = None
        self._remaining = self.polls_to_complete
        self.state = "busy"

    def _complete(self):
        r = self._request
        status, output = Status.OK, b""
        required = len(r.data) + (16 if r.operation == Operation.ENCRYPT else 0)
        if r.mode not in self.capabilities.modes:
            status = Status.UNSUPPORTED
        elif (len(r.data) > self.capabilities.max_message_bytes or len(r.ad) > self.capabilities.max_ad_bytes
              or r.output_capacity < required):
            status = Status.LENGTH
        else:
            try:
                if r.operation == Operation.ENCRYPT:
                    ct, tag = self.reference.encrypt(r.key, r.nonce, r.ad, r.data, timeout_s=1)
                    output = ct + tag
                else:
                    output = self.reference.decrypt(r.key, r.nonce, r.ad, r.data, r.tag, timeout_s=1)
            except AuthenticationError:
                status = Status.AUTH_FAILED
            except Exception:
                status = Status.INTERNAL
        self._response = Response(r.epoch, r.request_id, r.operation, r.mode, status, output).encode()
        self._request = None  # No retained request in completed slot; Python cannot guarantee erasure.
        self.state = "complete"

    def poll(self, deadline):
        self._deadline(deadline)
        if self.state == "busy":
            if self._remaining:
                self._remaining -= 1
                return None
            self._complete()
        self._deadline(deadline)
        return self._response  # Complete response remains stable until exact matching ACK.

    def ack(self, epoch, request_id, deadline):
        self._deadline(deadline)
        require(self.state == "complete", "ACK without completion")
        response = Response.decode(self._response)
        require((epoch, request_id) == (response.epoch, response.request_id), "ACK identity mismatch")
        self._request = self._response = None
        self.state = "idle"

    def reset(self, deadline):
        self._deadline(deadline)
        require(self.capabilities.epoch < UINT64_MAX, "session epoch exhausted")
        self.capabilities = Capabilities(VERSION, self.capabilities.epoch + 1,
                                         self.capabilities.max_message_bytes, self.capabilities.max_ad_bytes,
                                         self.capabilities.modes, True, self.capabilities.firmware_id)
        self._request = self._response = None
        self._last_id = 0
        self.state = "idle"
        return self.capabilities


class MailboxBackend(Backend):
    """Draft message adapter. No PYNQ registers, firmware loader or physical link."""
    def __init__(self, transport, mode="ise", *, timeout_s=5.0, poll_interval=0.001,
                 clock=time.monotonic, sleep=time.sleep):
        require(mode in ("sw", "hw", "ise"), "unknown mailbox mode")
        require(isinstance(poll_interval, (int, float)) and math.isfinite(poll_interval)
                and poll_interval > 0, "invalid poll interval")
        self.transport, self.clock, self.sleep = transport, clock, sleep
        self.poll_interval = poll_interval
        self.mode = {"sw": Mode.SW, "hw": Mode.HW, "ise": Mode.ISE}[mode]
        self._lock = threading.Lock()
        self._local = threading.local()
        self._next_id = 1
        self.needs_recovery = False
        caps = self._io(transport.hello, self._budget(timeout_s))
        self._set_caps(caps)

    def _budget(self, timeout_s):
        if (isinstance(timeout_s, bool) or not isinstance(timeout_s, (int, float))
                or not math.isfinite(timeout_s) or timeout_s <= 0):
            raise ValueError("timeout_s must be finite and positive")
        return self.clock() + timeout_s

    def _io(self, call, *args):
        try:
            if self.clock() >= args[-1]:
                raise BackendTimeoutError("mailbox deadline expired")
            result = call(*args)
            if self.clock() >= args[-1]:
                raise BackendTimeoutError("mailbox deadline expired")
            return result
        except AsconError:
            raise
        except TimeoutError:
            raise BackendTimeoutError("mailbox deadline expired") from None
        except OSError:
            raise BusError("mailbox transport failed") from None

    def _set_caps(self, caps):
        require(isinstance(caps, Capabilities), "malformed handshake")
        caps.validate()
        require(self.mode in caps.modes, "requested implementation mode unavailable")
        self.capabilities = caps
        self.max_message_bytes, self.max_ad_bytes = caps.max_message_bytes, caps.max_ad_bytes
        self.simulated = caps.simulated
        self.name = ("simulated-" if caps.simulated else "") + "mailbox-" + self.mode.name.lower()

    def recover(self, *, timeout_s=5.0):
        if not self._lock.acquire(blocking=False):
            raise MailboxBusyError("mailbox operation already in progress")
        try:
            self.needs_recovery = True
            self._local.info = CycleInfo()
            old_epoch = self.capabilities.epoch
            deadline = self._budget(timeout_s)
            caps = self._io(self.transport.reset, deadline)
            require(isinstance(caps, Capabilities) and caps.epoch != old_epoch, "reset did not change epoch")
            self._set_caps(caps)
            require(self.clock() < deadline, "reset completed after deadline")
            self._next_id = 1
            self._local.info = CycleInfo()
            self.needs_recovery = False
        finally:
            self._lock.release()

    def _exchange(self, operation, key, nonce, ad, data, tag, timeout_s):
        deadline = self._budget(timeout_s)
        if not self._lock.acquire(blocking=False):
            raise MailboxBusyError("mailbox operation already in progress")
        try:
            self._local.info = CycleInfo()
            require(not self.needs_recovery, "mailbox requires explicit recover before reuse")
            require(self._next_id <= UINT64_MAX, "request ids exhausted; recover required")
            if len(data) > self.max_message_bytes or len(ad) > self.max_ad_bytes:
                raise InvalidLengthError("input exceeds advertised mailbox capacity")
            rid = self._next_id
            request = Request(self.capabilities.epoch, rid, operation, self.mode, key, nonce, ad, data,
                              len(data) + (16 if operation == Operation.ENCRYPT else 0), tag)
            packet = request.encode()
            self._next_id += 1
            # Any uncertain submit/poll/ACK outcome quarantines the channel. Never auto-retry crypto.
            self.needs_recovery = True
            self._io(self.transport.submit, packet, deadline)
            while True:
                if self.clock() >= deadline:
                    raise BackendTimeoutError("mailbox deadline expired")
                packet = self._io(self.transport.poll, deadline)
                if packet is not None:
                    break
                self.sleep(min(self.poll_interval, max(0, deadline - self.clock())))
            response = Response.decode(packet)
            require((response.epoch, response.request_id, response.operation, response.mode)
                    == (request.epoch, rid, operation, self.mode), "stale or mismatched mailbox response")
            require(response.simulated == self.simulated, "response evidence kind mismatch")
            if response.status == Status.OK:
                require(len(response.data) == request.output_capacity, "mailbox output size mismatch")
            require(response.status != Status.AUTH_FAILED or operation == Operation.DECRYPT,
                    "authentication status on encryption")
            self._io(self.transport.ack, request.epoch, rid, deadline)
            if self.clock() >= deadline:
                raise BackendTimeoutError("mailbox deadline expired")
            self.needs_recovery = False
            if response.status == Status.AUTH_FAILED:
                raise AuthenticationError("authentication failed")
            if response.status == Status.LENGTH:
                raise InvalidLengthError("peer rejected input/output length")
            if response.status != Status.OK:
                raise BackendProtocolError("peer reported operation failure")
            if response.cycles is not None:
                self._local.info = CycleInfo(response.cycles, "simulated" if self.simulated else "hardware_measured",
                                             f"mailbox epoch={response.epoch} request={rid}",
                                             "peer-reported AEAD mcycle delta; excludes PS transport")
            return response.data
        finally:
            self._lock.release()

    def encrypt(self, key, nonce, ad, plaintext, *, timeout_s):
        output = self._exchange(Operation.ENCRYPT, key, nonce, ad, plaintext, b"", timeout_s)
        return output[:-16], output[-16:]

    def decrypt(self, key, nonce, ad, ciphertext, tag, *, timeout_s):
        return self._exchange(Operation.DECRYPT, key, nonce, ad, ciphertext, tag, timeout_s)

    def cycle_info(self, operation, message_bytes, ad_bytes):
        return getattr(self._local, "info", CycleInfo())
