"""Y01 draft v1 message codec. Byte offsets here are NOT hardware addresses."""
from __future__ import annotations

from dataclasses import dataclass, field
from enum import IntEnum
import struct

if __package__:
    from .ascon_host_api import BackendProtocolError, InvalidLengthError
else:
    from ascon_host_api import BackendProtocolError, InvalidLengthError

VERSION = 1
UINT64_MAX = (1 << 64) - 1
MAX_BYTES = 65536
REQUEST_HEADER = struct.Struct("<4sHHQQIIIIII")
RESPONSE_HEADER = struct.Struct("<4sHHQQIIIIQ")
SIMULATED = 2
CYCLES_VALID = 1


class Operation(IntEnum):
    ENCRYPT = 1
    DECRYPT = 2


class Mode(IntEnum):
    SW = 1
    HW = 2
    ISE = 3


class Status(IntEnum):
    OK = 0
    AUTH_FAILED = 1
    LENGTH = 2
    UNSUPPORTED = 3
    INTERNAL = 4


def require(condition, message):
    if not condition:
        raise BackendProtocolError(message)


def identity(epoch, request_id):
    require(type(epoch) is int and 1 <= epoch <= UINT64_MAX, "invalid session epoch")
    require(type(request_id) is int and 1 <= request_id <= UINT64_MAX, "invalid request id")


def enums(operation, mode):
    require(operation in tuple(Operation) and mode in tuple(Mode), "unknown operation or mode")


@dataclass(frozen=True)
class Request:
    epoch: int
    request_id: int
    operation: Operation
    mode: Mode
    key: bytes = field(repr=False)
    nonce: bytes = field(repr=False)
    ad: bytes = field(repr=False)
    data: bytes = field(repr=False)
    output_capacity: int
    tag: bytes = field(default=b"", repr=False)

    def encode(self):
        identity(self.epoch, self.request_id)
        enums(self.operation, self.mode)
        require(all(isinstance(x, bytes) for x in (self.key, self.nonce, self.ad, self.data, self.tag)),
                "request fields must be bytes")
        require(len(self.key) == len(self.nonce) == 16, "invalid key/nonce length")
        require(len(self.tag) == (16 if self.operation == Operation.DECRYPT else 0), "invalid tag length")
        if len(self.ad) > MAX_BYTES or len(self.data) > MAX_BYTES:
            raise InvalidLengthError("draft packet capacity exceeded")
        require(type(self.output_capacity) is int and 0 <= self.output_capacity <= MAX_BYTES + 16,
                "invalid output capacity")
        return REQUEST_HEADER.pack(b"Y01Q", VERSION, 0, self.epoch, self.request_id,
                                   self.operation, self.mode, len(self.ad), len(self.data),
                                   self.output_capacity, len(self.tag)) + self.key + self.nonce + self.ad + self.data + self.tag

    @classmethod
    def decode(cls, packet):
        require(isinstance(packet, bytes) and REQUEST_HEADER.size <= len(packet) <= REQUEST_HEADER.size + 32 + 2*MAX_BYTES + 16,
                "invalid request packet size")
        magic, version, flags, epoch, rid, op, mode, alen, dlen, capacity, tlen = REQUEST_HEADER.unpack_from(packet)
        require(magic == b"Y01Q" and version == VERSION and flags == 0, "request version/magic/flags mismatch")
        require(alen <= MAX_BYTES and dlen <= MAX_BYTES and tlen in (0, 16), "invalid request lengths")
        require(len(packet) == REQUEST_HEADER.size + 32 + alen + dlen + tlen, "request size mismatch")
        body = packet[REQUEST_HEADER.size:]
        request = cls(epoch, rid, op, mode, body[:16], body[16:32], body[32:32+alen],
                      body[32+alen:32+alen+dlen], capacity, body[32+alen+dlen:])
        request.encode()  # Same strict validation for locally and remotely supplied fields.
        return request


@dataclass(frozen=True)
class Response:
    epoch: int
    request_id: int
    operation: Operation
    mode: Mode
    status: Status
    data: bytes = field(default=b"", repr=False)
    cycles: int | None = None
    simulated: bool = True

    def encode(self):
        identity(self.epoch, self.request_id)
        enums(self.operation, self.mode)
        require(self.status in tuple(Status), "unknown response status")
        require(isinstance(self.data, bytes) and len(self.data) <= MAX_BYTES + 16, "invalid response payload")
        require(self.status == Status.OK or (not self.data and self.cycles is None),
                "failed response must not contain data or cycles")
        require(self.cycles is None or (type(self.cycles) is int and 0 <= self.cycles <= UINT64_MAX), "invalid cycles")
        flags = (SIMULATED if self.simulated else 0) | (CYCLES_VALID if self.cycles is not None else 0)
        return RESPONSE_HEADER.pack(b"Y01R", VERSION, flags, self.epoch, self.request_id,
                                    self.status, self.operation, self.mode, len(self.data),
                                    self.cycles or 0) + self.data

    @classmethod
    def decode(cls, packet):
        require(isinstance(packet, bytes) and RESPONSE_HEADER.size <= len(packet) <= RESPONSE_HEADER.size + MAX_BYTES + 16,
                "invalid response packet size")
        magic, version, flags, epoch, rid, status, op, mode, size, cycles = RESPONSE_HEADER.unpack_from(packet)
        require(magic == b"Y01R" and version == VERSION and flags & ~3 == 0, "response version/magic/flags mismatch")
        require(size == len(packet) - RESPONSE_HEADER.size, "response size mismatch")
        require(flags & CYCLES_VALID or cycles == 0, "invalid absent cycle value")
        response = cls(epoch, rid, op, mode, status, packet[RESPONSE_HEADER.size:],
                       cycles if flags & CYCLES_VALID else None, bool(flags & SIMULATED))
        response.encode()
        return response
