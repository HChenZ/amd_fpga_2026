"""Experimental DMA ABI v2. No UART compatibility or software fallback.

Adapters are injected; PynqSimpleDMA uses bounded MMIO polling, never wait().
The caller must exclusively own the DMA and endpoint (including other processes).
"""
import math
import secrets
import struct
import threading
import time
from dataclasses import dataclass

REQUEST = struct.Struct('<4sHHQQIIIIII')
RESPONSE = struct.Struct('<4sHHQQIIIIQ')
IDENTITY = 0x32414D44
VERSION = 2
MAX_BYTES = 1024
# Strong references survive an accidentally dropped backend object. The process
# must remain alive until a successful recovery or external hardware reset.
_QUARANTINED = []


class DMAError(RuntimeError):
    pass


class ProtocolError(DMAError):
    pass


class RemoteError(DMAError):
    def __init__(self, status):
        self.status = status
        super().__init__('DMA endpoint status %d' % status)


@dataclass(frozen=True)
class Result:
    payload: bytes
    cycles: object
    simulated: bool
    mode: int


def encode_request(epoch, request_id, operation, mode, key, nonce, ad, data, tag=b''):
    key, nonce, ad, data, tag = map(bytes, (key, nonce, ad, data, tag))
    if not (0 < epoch < 2**64 and 0 < request_id < 2**64):
        raise ValueError('invalid session identity')
    if operation not in (1, 2) or mode not in (1, 2, 3, 4):
        raise ValueError('unsupported operation or mode')
    if len(key) != 16 or len(nonce) != 16 or len(tag) != (16 if operation == 2 else 0):
        raise ValueError('invalid key/nonce/tag length')
    if max(len(ad), len(data)) > MAX_BYTES:
        raise ValueError('packet capacity exceeded')
    capacity = len(data) + (16 if operation == 1 else 0)
    return REQUEST.pack(b'D01Q', 2, 0, epoch, request_id, operation, mode,
                        len(ad), len(data), capacity, len(tag)) + key + nonce + ad + data + tag


def decode_response(packet, epoch, request_id, operation, mode, expected_length,
                    simulated=False):
    if len(packet) < 48:
        raise ProtocolError('short response')
    magic, version, flags, ep, rid, status, op, md, length, cycles = RESPONSE.unpack(packet[:48])
    if magic != b'D01R' or version != 2 or flags & ~3:
        raise ProtocolError('response ABI mismatch')
    if (ep, rid, op, md) != (epoch, request_id, operation, mode):
        raise ProtocolError('response identity mismatch')
    if status not in range(7) or len(packet) != 48 + length:
        raise ProtocolError('response status/length mismatch')
    if status:
        if length or flags or cycles or (status == 1 and operation != 2):
            raise ProtocolError('invalid failure response')
        raise RemoteError(status)
    if length != expected_length or bool(flags & 2) != simulated:
        raise ProtocolError('response capacity/evidence mismatch')
    if not flags & 1 and cycles:
        raise ProtocolError('invalid cycle field')
    return Result(bytes(packet[48:]), cycles if flags & 1 else None, simulated, mode)


class DMATransport:
    """Single-slot synchronous backend, with explicit recover after transport errors.

    control: read(offset), write(offset,value).
    dma: start_receive(buffer,n), start_send(buffer,n), poll()->(done,rx_bytes),
         quiesce(absolute_deadline)->bool. Every adapter operation must be bounded.
    allocate: callable(shape=(n,),dtype='u1') returning PynqBuffer-like storage.
    Buffers stay strongly referenced in retained if quiescence cannot be proven.
    """
    def __init__(self, control, dma, allocate, *, timeout=2.0, simulated=False,
                 clock=time.monotonic, sleep=time.sleep):
        self.control, self.dma, self.allocate = control, dma, allocate
        self.clock, self.sleep = clock, sleep
        self.timeout = self._budget(timeout)
        self.simulated = simulated
        self.lock = threading.Lock()
        self.retained = []
        self.needs_recovery = True
        self.epoch = 0
        self.request_id = 0
        self.capacities = {}
        self.closed = False
        if getattr(dma, '_transport_owner', None) is not None:
            raise DMAError('DMA already owned by another transport')
        dma._transport_owner = self

    @staticmethod
    def _budget(value):
        if not math.isfinite(value) or value <= 0:
            raise ValueError('finite positive timeout required')
        return value

    def _check(self, deadline):
        if self.clock() >= deadline:
            raise TimeoutError('DMA deadline')

    def _caps(self):
        c = self.control
        if c.read(0) != IDENTITY or c.read(4) != VERSION:
            raise ProtocolError('control ABI mismatch')
        mm, ma, mask = c.read(0x14), c.read(0x18), c.read(0x1c)
        if not mask or mask & ~15 or max(mm, ma) > MAX_BYTES:
            raise ProtocolError('invalid capabilities')
        caps = {}
        for mode in range(1, 5):
            if mask & (1 << (mode - 1)):
                offset = 0x30 + (mode - 1) * 8
                m, a = c.read(offset), c.read(offset + 4)
                if m > mm or a > ma:
                    raise ProtocolError('invalid mode capacities')
                caps[mode] = (m, a)
        return caps

    def _epoch(self):
        return self.control.read(0x0c) | self.control.read(0x10) << 32

    def _wait_ready(self, deadline, epoch=None):
        """Completion includes endpoint scrubbing, not only DMA TLAST."""
        expected = self.epoch if epoch is None else epoch
        try:
            while True:
                self._check(deadline)
                status = self.control.read(0x20)
                if self._epoch() != expected or status & ~7 or status & 4 or status == 3:
                    raise ProtocolError('endpoint fault/session/status mismatch')
                if status == 1:
                    self._check(deadline)
                    return
                self.sleep(min(0.001, max(0, deadline - self.clock())))
        except Exception:
            self.needs_recovery = True
            raise

    @staticmethod
    def _release(buffers):
        for b in buffers:
            b[:] = 0
            b.flush()
            b.freebuffer()

    def recover(self, timeout=None, epoch=None):
        if not self.lock.acquire(False):
            raise DMAError('single client busy')
        try:
            if self.closed:
                raise DMAError('transport is closed')
            deadline = self.clock() + self._budget(self.timeout if timeout is None else timeout)
            self.needs_recovery = True
            caps = self._caps()
            self.control.write(8, 1)  # abort CPU/endpoint before resetting DMA
            if not self.dma.quiesce(deadline):
                raise DMAError('DMA did not quiesce; buffers retained')
            self._check(deadline)
            self._release(self.retained)
            self.retained = []
            if self in _QUARANTINED:
                _QUARANTINED.remove(self)
            new_epoch = secrets.randbits(64) if epoch is None else epoch
            if not 0 < new_epoch < 2**64 or new_epoch in (self.epoch, self._epoch()):
                raise ValueError('fresh nonzero epoch required')
            self.control.write(0x0c, new_epoch & 0xffffffff)
            self.control.write(0x10, new_epoch >> 32)
            self.control.write(8, 0)
            self._wait_ready(deadline, new_epoch)
            self.epoch, self.request_id, self.capacities = new_epoch, 0, caps
            self.needs_recovery = False
            return dict(caps)
        finally:
            self.lock.release()

    def transact(self, operation, mode, key, nonce, ad, data, tag=b'', timeout=None):
        if not self.lock.acquire(False):
            raise DMAError('single client busy')
        buffers = []
        started = False
        try:
            if self.closed or self.needs_recovery:
                raise DMAError('explicit recovery required')
            deadline = self.clock() + self._budget(self.timeout if timeout is None else timeout)
            # Freeze byte lengths and contents before any injected callback can
            # mutate caller storage; buffer sizing must match the encoded packet.
            key, nonce, ad, data, tag = map(bytes, (key, nonce, ad, data, tag))
            if mode not in self.capacities:
                raise ValueError('mode not supported by endpoint')
            mm, ma = self.capacities[mode]
            if len(data) > mm or len(ad) > ma:
                raise ValueError('mode capacity exceeded')
            packet = encode_request(self.epoch, self.request_id + 1, operation, mode,
                                    key, nonce, ad, data, tag)
            self._wait_ready(deadline)
            self.request_id += 1
            expected = len(data) + (16 if operation == 1 else 0)
            tx = self.allocate(shape=(len(packet),), dtype='u1')
            buffers.append(tx)
            rx = self.allocate(shape=(48 + expected,), dtype='u1')
            buffers.append(rx)
            tx[:] = list(packet)
            rx[:] = 0
            tx.flush()
            rx.flush()
            self._check(deadline)
            started = True  # even a failing start may have published an address
            self.dma.start_receive(rx, len(rx))
            self.dma.start_send(tx, len(tx))
            while True:
                self._check(deadline)
                if self.control.read(0x20) & 4 or self._epoch() != self.epoch:
                    raise ProtocolError('endpoint fault/session change')
                done, length = self.dma.poll()
                if done:
                    break
                self.sleep(min(0.001, max(0, deadline - self.clock())))
            if not 48 <= length <= len(rx):
                raise ProtocolError('DMA receive length invalid')
            rx.invalidate()
            response = bytes(rx[:length])
            remote_error = None
            try:
                result = decode_response(response, self.epoch, self.request_id, operation,
                                         mode, expected, self.simulated)
            except RemoteError as error:
                remote_error = error
            self._wait_ready(deadline)  # direct core may scrub for ~1024 clocks
            self._check(deadline)
            if remote_error is not None:
                raise remote_error
            return result
        except RemoteError:
            raise
        except BaseException:
            if started:
                self.needs_recovery = True
            raise
        finally:
            try:
                if buffers:
                    # Errors require reset/halted proof before memory release.
                    safe = not started
                    if started:
                        try:
                            if self.needs_recovery:
                                self.control.write(8, 1)
                            safe = self.dma.quiesce(self.clock() + self.timeout)
                        except BaseException:
                            safe = False
                    if safe:
                        self._release(buffers)
                    else:
                        self.retained.extend(buffers)
                        self.needs_recovery = True
                        if self not in _QUARANTINED:
                            _QUARANTINED.append(self)
                        raise DMAError('DMA did not quiesce; buffers retained')
            finally:
                self.lock.release()

    def close(self, timeout=None):
        """Abort, prove DMA halted, free retained buffers, then release process lock.

        On failure this object remains quarantined and close must be retried;
        an unverified hardware reset is never treated as proof of quiescence.
        """
        if not self.lock.acquire(False):
            raise DMAError('single client busy')
        try:
            if self.closed:
                return
            self.needs_recovery = True
            deadline = self.clock() + self._budget(self.timeout if timeout is None else timeout)
            self.control.write(8, 1)
            if not self.dma.quiesce(deadline):
                raise DMAError('DMA did not quiesce; close refused')
            self._release(self.retained)
            self.retained = []
            if self in _QUARANTINED:
                _QUARANTINED.remove(self)
            if hasattr(self, '_lock_fd'):
                import os
                os.close(self._lock_fd)
                del self._lock_fd
            self.closed = True
            self.dma._transport_owner = None
        finally:
            self.lock.release()


class PynqSimpleDMA:
    """PYNQ 2.7 AXI DMA simple-mode register adapter (SG unsupported).

    Pass raw MMIO made from HWH; avoid the standard DMA driver's constructor.
    No channel.wait()/stop()/start() spin loops.
    On errors reset both channels and prove halted before buffers are released.
    """
    def __init__(self, mmio, clock=time.monotonic, sleep=time.sleep, *,
                 max_transfer=16383, tx_alignment=4, rx_alignment=4):
        self.mmio, self.clock, self.sleep = mmio, clock, sleep
        self.max_transfer = max_transfer
        self.alignments = {0: tx_alignment, 0x30: rx_alignment}
        self.active = set()

    def _start(self, base, buffer, n):
        address = int(buffer.physical_address)
        if address % self.alignments[base] or not 0 < n <= min(len(buffer), self.max_transfer):
            raise ValueError('DMA alignment/length')
        if base in self.active:
            raise DMAError('DMA channel already owns a transfer')
        status = self.mmio.read(base + 4)
        if status & 8:
            raise DMAError('scatter-gather DMA unsupported')
        self.mmio.write(base + 4, 0x7000)
        self.mmio.write(base, 1)
        self.mmio.write(base + 0x18, address & 0xffffffff)
        self.mmio.write(base + 0x1c, address >> 32)
        self.active.add(base)
        self.mmio.write(base + 0x28, n)

    def start_receive(self, buffer, n):
        self._start(0x30, buffer, n)

    def start_send(self, buffer, n):
        self._start(0, buffer, n)

    def poll(self):
        if self.active != {0, 0x30}:
            raise DMAError('both channels must own this transfer')
        tx, rx = self.mmio.read(4), self.mmio.read(0x34)
        if (tx | rx) & 0x770:
            raise DMAError('DMA channel error')
        if (tx | rx) & 1:
            raise DMAError('DMA channel halted before completion')
        done = (tx & 0x1002) == 0x1002 and (rx & 0x1002) == 0x1002
        return done, self.mmio.read(0x58) if done else 0

    def quiesce(self, deadline):
        self.mmio.write(0, 4)
        while self.clock() < deadline:
            if not self.mmio.read(0) & 4 and self.mmio.read(4) & 1 and self.mmio.read(0x34) & 1:
                self.active.clear()
                return True
            self.sleep(min(0.001, max(0, deadline - self.clock())))
        return False


def pynq_backend(control, dma, *, parameters=None, lock_path='/tmp/ascon_dma_v2.lock',
                 lock_fd=None, **kwargs):
    """Acquire a Linux process lock before accessing the real PYNQ DMA.

    All clients of the same device must use the same lock path. Keep the backend
    and notebook process alive if retained buffers cannot yet be quiesced.
    """
    import fcntl
    import os
    from pynq import allocate
    fd = lock_fd if lock_fd is not None else os.open(lock_path, os.O_CREAT | os.O_RDWR, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if parameters is None:
            parameters = getattr(dma, 'description', {}).get('parameters')
        config = dma_configuration(parameters)
        # Passing raw MMIO avoids PYNQ DMA.__init__ -> _SDMAChannel.start spin.
        mmio = getattr(dma, 'mmio', dma)
        transport = DMATransport(control, PynqSimpleDMA(mmio, **config), allocate, **kwargs)
    except BaseException:
        os.close(fd)
        raise
    transport._lock_fd = fd
    return transport


def dma_configuration(parameters):
    """Validate PYNQ 2.7 HWH parameters without instantiating DMA channel drivers."""
    if not parameters:
        raise DMAError('DMA HWH parameters required')
    def number(name):
        try:
            value = str(parameters[name])
            return int(value, 16 if value.lower().startswith('0x') else 10)
        except (KeyError, TypeError, ValueError):
            raise DMAError('missing/invalid DMA HWH parameter: '+name) from None
    if number('c_include_sg') or number('c_micro_dma'):
        raise DMAError('only non-micro simple DMA is supported')
    if number('c_include_mm2s') != 1 or number('c_include_s2mm') != 1:
        raise DMAError('both DMA channels required')
    width = number('c_sg_length_width')
    if not 8 <= width <= 26:
        raise DMAError('invalid DMA transfer length width')
    align = []
    for channel in ('mm2s','s2mm'):
        bits = number('c_m_axi_'+channel+'_data_width')
        if bits not in (32,64,128,256,512,1024):
            raise DMAError('unsupported DMA memory bus width')
        align.append(1 if number('c_include_'+channel+'_dre') else bits//8)
    return dict(max_transfer=(1<<width)-1, tx_alignment=align[0], rx_alignment=align[1])


class DMABackend:
    """AsconHost-compatible adapter. Mode 4 is named hw_direct explicitly."""
    def __init__(self, transport, mode='ise'):
        modes = {'sw': 1, 'hw': 2, 'ise': 3, 'hw_direct': 4}
        self.transport = transport
        self.mode = modes[mode]
        if transport.needs_recovery or self.mode not in transport.capacities:
            raise DMAError('recover transport and select an advertised mode first')
        self.max_message_bytes, self.max_ad_bytes = transport.capacities[self.mode]
        self.name = 'dma-v2-' + mode
        self.simulated = transport.simulated
        self.local = threading.local()

    def _call(self, op, key, nonce, ad, data, tag, timeout):
        from .ascon_host_api import AuthenticationError, InvalidLengthError, BackendProtocolError, BackendTimeoutError
        self.local.result = None
        try:
            result = self.transport.transact(op, self.mode, key, nonce, ad, data, tag, timeout)
        except RemoteError as e:
            if e.status == 1:
                raise AuthenticationError('authentication failed') from None
            if e.status == 2:
                raise InvalidLengthError('endpoint capacity exceeded') from None
            raise BackendProtocolError('endpoint rejected request') from None
        except TimeoutError:
            raise BackendTimeoutError('DMA deadline') from None
        except ValueError:
            raise InvalidLengthError('invalid request') from None
        except DMAError:
            raise BackendProtocolError('DMA transport failure') from None
        self.local.result = result
        return result.payload

    def encrypt(self, key, nonce, ad, plaintext, *, timeout_s):
        value = self._call(1, key, nonce, ad, plaintext, b'', timeout_s)
        return value[:-16], value[-16:]

    def decrypt(self, key, nonce, ad, ciphertext, tag, *, timeout_s):
        return self._call(2, key, nonce, ad, ciphertext, tag, timeout_s)

    def cycle_info(self, operation, message_bytes, ad_bytes):
        from .ascon_host_api import CycleInfo
        result = getattr(self.local, 'result', None)
        if result is None or result.cycles is None:
            return CycleInfo()
        return CycleInfo(result.cycles, 'simulated' if result.simulated else 'measured',
                         self.name, 'PL computation cycles' if self.mode == 4 else 'RV32 AEAD mcycle')
