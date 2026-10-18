"""Y01 draft codec/ownership/recovery tests, with deterministic fake deadlines."""
from dataclasses import replace
import unittest
from unittest.mock import patch

from ascon_host_api import (AsconHost, AuthenticationError, BackendProtocolError,
                            BackendTimeoutError, BusError, InvalidLengthError)
from mailbox_backend import MailboxBackend, MailboxBusyError, MemoryTransport
from mailbox_protocol import (MAX_BYTES, REQUEST_HEADER, RESPONSE_HEADER,
                              UINT64_MAX, VERSION, Mode, Operation, Request, Response, Status)
from golden_checker import parse_kat


class Clock:
    def __init__(self):
        self.now = 0.0

    def __call__(self):
        return self.now

    def sleep(self, seconds):
        self.now += seconds


class MailboxTests(unittest.TestCase):
    def setUp(self):
        self.clock = Clock()
        self.peer = MemoryTransport(clock=self.clock, polls_to_complete=1)
        self.backend = MailboxBackend(self.peer, clock=self.clock, sleep=self.clock.sleep,
                                      poll_interval=0.01)
        self.host = AsconHost(self.backend)
        self.key, self.nonce = bytes(range(16)), bytes(range(16, 32))

    def request(self, **kwargs):
        return replace(Request(1, 1, Operation.ENCRYPT, Mode.ISE,
                               self.key, self.nonce, b"", b"message", 23), **kwargs)

    def exchange_raw(self, request):
        self.peer.submit(request.encode(), 10)
        self.assertIsNone(self.peer.poll(10))
        return Response.decode(self.peer.poll(10))

    def encrypt(self, **kwargs):
        return self.host.encrypt(self.key, self.nonce, b"", b"message", **kwargs)

    def test_codec_round_trip_and_little_endian(self):
        request = self.request(request_id=0x0102030405060708)
        packet = request.encode()
        self.assertEqual(REQUEST_HEADER.size, 48)
        self.assertEqual(RESPONSE_HEADER.size, 48)
        self.assertEqual(packet[16:24], bytes.fromhex("0807060504030201"))
        self.assertEqual(Request.decode(packet), request)
        for cycles in (None, 0, (1 << 32) + 17, UINT64_MAX):
            response = Response(1, 1, Operation.ENCRYPT, Mode.ISE, Status.OK, bytes(16), cycles)
            self.assertEqual(Response.decode(response.encode()), response)

    def test_packet_size_truncation_trailing_and_flags(self):
        request = self.request().encode()
        response = Response(1, 1, Operation.DECRYPT, Mode.ISE, Status.OK).encode()
        for packet, decoder in ((request, Request.decode), (response, Response.decode)):
            for bad in (b"", packet[:47], packet[:-1], packet + b"x", b"BAD!" + packet[4:]):
                with self.assertRaises(BackendProtocolError):
                    decoder(bad)
            for offset in (4, 6):  # Unknown version and reserved flag.
                bad = bytearray(packet)
                bad[offset] = 128
                with self.assertRaises(BackendProtocolError):
                    decoder(bytes(bad))

    def test_invalid_request_fields(self):
        for changes in ({"epoch": 0}, {"request_id": 0}, {"request_id": UINT64_MAX + 1},
                        {"operation": 99}, {"mode": 99}, {"key": bytes(15)},
                        {"nonce": "nonce"}, {"tag": bytes(16)}, {"output_capacity": -1}):
            with self.assertRaises(BackendProtocolError):
                self.request(**changes).encode()
        with self.assertRaises(InvalidLengthError):
            self.request(data=bytes(MAX_BYTES+1)).encode()
        with self.assertRaises(BackendProtocolError):
            self.request(operation=Operation.DECRYPT, tag=b"").encode()

    def test_decode_rejects_inconsistent_declared_length(self):
        packet = self.request().encode()
        header = list(REQUEST_HEADER.unpack_from(packet))
        header[8] += 1  # AD length cannot extend beyond the actual frame.
        with self.assertRaises(BackendProtocolError):
            Request.decode(REQUEST_HEADER.pack(*header) + packet[48:])

    def test_failed_response_cannot_publish_candidate_or_cycles(self):
        for status in (Status.AUTH_FAILED, Status.LENGTH, Status.UNSUPPORTED, Status.INTERNAL):
            for data, cycles in ((b"candidate plaintext", None), (b"", 1)):
                with self.assertRaises(BackendProtocolError):
                    Response(1, 1, Operation.DECRYPT, Mode.ISE, status, data, cycles).encode()
        packet = Response(1, 1, Operation.DECRYPT, Mode.ISE, Status.OK, b"candidate").encode()
        fields = list(RESPONSE_HEADER.unpack_from(packet))
        fields[5] = Status.AUTH_FAILED
        with self.assertRaises(BackendProtocolError):
            Response.decode(RESPONSE_HEADER.pack(*fields) + packet[48:])

    def test_absent_cycle_flag_and_range(self):
        packet = Response(1, 1, Operation.ENCRYPT, Mode.ISE, Status.OK).encode()
        fields = list(RESPONSE_HEADER.unpack(packet))
        fields[-1] = 1
        with self.assertRaises(BackendProtocolError):
            Response.decode(RESPONSE_HEADER.pack(*fields))
        for cycles in (-1, UINT64_MAX + 1):
            with self.assertRaises(BackendProtocolError):
                Response(1, 1, Operation.ENCRYPT, Mode.ISE, Status.OK, cycles=cycles).encode()

    def test_six_kat_vectors_in_all_modes(self):
        cases = parse_kat()
        for mode in ("sw", "hw", "ise"):
            host = AsconHost(MailboxBackend(MemoryTransport(polls_to_complete=0), mode))
            for m, a in ((0, 0), (1, 0), (16, 0), (16, 16), (17, 0), (32, 0)):
                c = next(c for c in cases if (len(c["PT"]), len(c["AD"])) == (m, a))
                with self.subTest(mode=mode, m=m, a=a):
                    enc = host.encrypt(c["Key"], c["Nonce"], c["AD"], c["PT"])
                    self.assertEqual(enc.ciphertext + enc.tag, c["CT"])
                    dec = host.decrypt(c["Key"], c["Nonce"], c["AD"], c["CT"][:-16], c["CT"][-16:])
                    self.assertEqual(dec.plaintext, c["PT"])
                    self.assertTrue(enc.simulated)
                    self.assertIsNone(enc.cycles)

    def test_busy_request_cannot_overwrite_slot(self):
        self.peer.submit(self.request().encode(), 10)
        with self.assertRaises(MailboxBusyError):
            self.peer.submit(self.request(request_id=2).encode(), 10)
        self.assertEqual(self.peer._request.request_id, 1)
        self.peer.poll(10)
        self.peer.poll(10)
        with self.assertRaises(MailboxBusyError):
            self.peer.submit(self.request(request_id=2).encode(), 10)

    def test_output_atomic_stable_and_exact_ack(self):
        response = self.exchange_raw(self.request())
        packet = response.encode()
        self.assertEqual(self.peer.poll(10), packet)
        with self.assertRaises(BackendProtocolError):
            self.peer.ack(1, 2, 10)
        self.assertEqual(self.peer.poll(10), packet)
        self.peer.ack(1, 1, 10)
        self.assertEqual(self.peer.state, "idle")
        self.assertIsNone(self.peer.poll(10))
        self.assertIsNone(self.peer._request)
        self.assertIsNone(self.peer._response)

    def test_duplicate_and_stale_request_rejected(self):
        self.exchange_raw(self.request())
        self.peer.ack(1, 1, 10)
        with self.assertRaises(BackendProtocolError):
            self.peer.submit(self.request().encode(), 10)
        self.peer.reset(10)
        with self.assertRaises(BackendProtocolError):
            self.peer.submit(self.request(request_id=2).encode(), 10)

    def test_negotiation_version_modes_and_capacity(self):
        for changes in ({"version": 2}, {"epoch": 0}, {"max_message_bytes": MAX_BYTES+1},
                        {"modes": ()}, {"modes": (Mode.SW, Mode.SW)}, {"firmware_id": ""}):
            with patch.object(self.peer, "hello", return_value=replace(self.peer.capabilities, **changes)):
                with self.assertRaises(BackendProtocolError):
                    MailboxBackend(self.peer)
        with self.assertRaises(BackendProtocolError):
            MailboxBackend(MemoryTransport(modes=(Mode.SW,)), "ise")
        self.assertEqual(self.backend.max_message_bytes, 32)
        with self.assertRaises(InvalidLengthError):
            self.host.encrypt(self.key, self.nonce, b"", bytes(33))
        self.assertEqual(self.peer.state, "idle")

    def test_peer_rejects_bad_output_capacity_and_length(self):
        for request in (self.request(output_capacity=22), self.request(data=bytes(33), output_capacity=49),
                        self.request(ad=bytes(33))):
            self.peer = MemoryTransport(clock=self.clock)
            response = self.exchange_raw(request)
            self.assertEqual((response.status, response.data, response.cycles), (Status.LENGTH, b"", None))

    def test_unsupported_mode_has_empty_error_response(self):
        peer = MemoryTransport(modes=(Mode.SW,), polls_to_complete=0)
        peer.submit(self.request().encode(), 10**12)
        response = Response.decode(peer.poll(10**12))
        self.assertEqual((response.status, response.data), (Status.UNSUPPORTED, b""))

    def test_authentication_failure_acked_without_plaintext(self):
        self.encrypt()
        with self.assertRaises(AuthenticationError) as error:
            self.host.decrypt(self.key, self.nonce, b"", b"message", bytes(16))
        self.assertEqual(error.exception.args, ("authentication failed",))
        self.assertFalse(hasattr(error.exception, "plaintext"))
        self.assertIsNone(self.peer._response)
        self.assertFalse(self.backend.needs_recovery)
        self.encrypt()  # Normal auth failure does not require channel reset.

    def test_stale_identity_mode_and_evidence_quarantine(self):
        original = self.peer.poll
        for changes in ({"epoch": 2}, {"request_id": 2}, {"operation": Operation.DECRYPT},
                        {"mode": Mode.SW}, {"simulated": False}, {"data": b"short"}):
            def faulty(deadline):
                packet = original(deadline)
                return replace(Response.decode(packet), **changes).encode() if packet else None
            with patch.object(self.peer, "poll", side_effect=faulty):
                with self.assertRaises(BackendProtocolError):
                    self.encrypt()
            self.assertTrue(self.backend.needs_recovery)
            with self.assertRaises(BackendProtocolError):
                self.encrypt()
            self.backend.recover()

    def test_timeout_requires_explicit_reset_no_auto_retry(self):
        self.peer.polls_to_complete = 100
        with self.assertRaises(BackendTimeoutError):
            self.encrypt(timeout_s=0.025)
        self.assertTrue(self.backend.needs_recovery)
        self.assertEqual(self.peer.state, "busy")
        with self.assertRaises(BackendProtocolError):
            self.encrypt()
        self.backend.recover()
        self.assertEqual(self.peer.capabilities.epoch, 2)
        self.assertIsNone(self.peer._request)
        self.peer.polls_to_complete = 0
        self.encrypt()

    def test_transport_errors_at_submit_poll_and_ack(self):
        for method in ("submit", "poll", "ack"):
            with patch.object(self.peer, method, side_effect=OSError("secret device detail")):
                with self.assertRaises(BusError) as error:
                    self.encrypt()
                self.assertNotIn("secret", str(error.exception))
            self.assertTrue(self.backend.needs_recovery)
            self.backend.recover()

    def test_reset_failure_and_unchanged_epoch_stay_quarantined(self):
        for result in (OSError("link down"), self.peer.capabilities):
            with patch.object(self.peer, "reset", side_effect=result if isinstance(result, Exception) else None,
                              return_value=result):
                with self.assertRaises((BusError, BackendProtocolError)):
                    self.backend.recover()
            self.assertTrue(self.backend.needs_recovery)
        self.backend.recover()
        self.encrypt()

    def test_concurrent_entry_rejected(self):
        self.backend._lock.acquire()
        try:
            with self.assertRaises(MailboxBusyError):
                self.encrypt()
            with self.assertRaises(MailboxBusyError):
                self.backend.recover()
        finally:
            self.backend._lock.release()

    def test_id_exhaustion_requires_new_epoch(self):
        self.backend._next_id = UINT64_MAX
        self.encrypt()
        with self.assertRaises(BackendProtocolError):
            self.encrypt()
        self.backend.recover()
        self.encrypt()

    def test_internal_failure_no_output(self):
        with patch.object(self.peer.reference, "encrypt", side_effect=RuntimeError("secret")):
            with self.assertRaises(BackendProtocolError):
                self.encrypt()
        self.assertIsNone(self.peer._response)
        self.assertFalse(self.backend.needs_recovery)

    def test_mutated_response_wire_rejected(self):
        original = self.peer.poll
        def truncated(deadline):
            packet = original(deadline)
            return packet[:-1] if packet else None
        with patch.object(self.peer, "poll", side_effect=truncated):
            with self.assertRaises(BackendProtocolError):
                self.encrypt()
        self.assertTrue(self.backend.needs_recovery)

    def test_simulated_u64_cycle_propagation(self):
        original = self.peer.poll
        def measured(deadline):
            packet = original(deadline)
            return replace(Response.decode(packet), cycles=(1 << 32) + 7).encode() if packet else None
        with patch.object(self.peer, "poll", side_effect=measured):
            result = self.encrypt()
        self.assertEqual(result.cycles, (1 << 32) + 7)
        self.assertEqual(result.cycle_info.status, "simulated")
        self.encrypt()
        self.assertIsNone(self.backend.cycle_info("encrypt", 7, 0).value)

    def test_deadline_covers_hello_and_ack(self):
        original = self.peer.ack
        def late_ack(*args):
            original(*args)
            self.clock.sleep(1)
        with patch.object(self.peer, "ack", side_effect=late_ack):
            with self.assertRaises(BackendTimeoutError):
                self.encrypt(timeout_s=0.1)
        self.assertTrue(self.backend.needs_recovery)
        original_hello = self.peer.hello
        def late_hello(deadline):
            caps = original_hello(deadline)
            self.clock.sleep(1)
            return caps
        with patch.object(self.peer, "hello", side_effect=late_hello):
            with self.assertRaises(BackendTimeoutError):
                MailboxBackend(self.peer, timeout_s=0.1, clock=self.clock)


if __name__ == "__main__":
    unittest.main(verbosity=2)
