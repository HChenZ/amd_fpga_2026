"""PUF-MIN 主机闭环离线单测（不需要 PYNQ、不需要板卡）。

用 MockMmio 精确复刻 src/rtl/puf_min/puf_min_axil.v 的寄存器语义：
粘滞 done/valid、busy 时 START -> error 0x40 + locked、CLEAR 清状态、
valid=0 时 RAW/CNT_VAL 读 0、CNT_SEL 选择计数器。
RO 响应是**人为构造**的确定性值 + 可控噪声位，不代表任何物理 PUF 属性。
"""
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / 'src/pynq'))

import puf_min as pm  # noqa: E402

DNA = 0x0123456789ABCDE
TRUE_RESPONSE = 0x0F0E0D0C0B0A09080706050403020100


class MockMmio:
    """行为级寄存器模型。latency 表示 START 之后需要几次寄存器读才 done。"""

    def __init__(self, *, true_response=TRUE_RESPONSE, noisy_bits=(), dna=DNA,
                 seed=1234, latency=3, fail_on_sample=None, id_value=pm.ID_EXPECTED):
        self.true_response = true_response
        self.noisy_bits = tuple(noisy_bits)
        self.dna = dna
        self.seed = seed
        self._rng = __import__('random').Random(seed)
        self.latency = latency
        self.fail_on_sample = fail_on_sample
        self.id_value = id_value
        self.txn = 0
        self.busy = 0
        self.done = 0
        self.valid = 0
        self.locked = 0
        self.error = 0
        self.raw = 0
        self.counts = [0] * pm.N_RINGS
        self._pending = None
        self._cnt_sel = 0
        self.samples = 0

    # --- 内部 ---
    def _respond(self):
        value = self.true_response
        for bit in self.noisy_bits:
            if self._rng.getrandbits(1):
                value ^= (1 << bit)
        self.raw = value
        self.valid = 1
        self.done = 1
        self.busy = 0
        for j in range(pm.BITS):
            a = self._rng.getrandbits(12) + 100
            # noisy 位让"比较方向"翻转，掩盖真实响应位
            b = a + (1 if ((value >> j) & 1) else -1)
            self.counts[j] = a
            self.counts[j + pm.BITS] = max(b, 0)

    def _tick(self):
        if self._pending is None:
            return
        self._pending -= 1
        if self._pending <= 0:
            self._pending = None
            if self.fail_on_sample:
                self.busy = 0
                self.done = 1
                self.valid = 0
                self.error = self.fail_on_sample
                self.locked = 1
            else:
                self._respond()

    # --- MMIO ---
    def read(self, offset):
        self._tick()
        if offset == pm.R_ID:
            return self.id_value
        if offset == pm.R_VERSION:
            return pm.VERSION_EXPECTED
        if offset == pm.R_STATUS:
            return (self.busy | (self.done << 1) | (self.valid << 2)
                    | (self.locked << 3) | (1 << 4))
        if offset == pm.R_ERROR:
            return self.error
        if offset == pm.R_TXN:
            return self.txn
        if pm.R_RAW0 <= offset <= pm.R_RAW0 + 12:
            if not self.valid:
                return 0
            return (self.raw >> (32 * ((offset - pm.R_RAW0) // 4))) & 0xFFFFFFFF
        if offset == pm.R_DNA_LO:
            return self.dna & 0xFFFFFFFF
        if offset == pm.R_DNA_HI:
            return (self.dna >> 32) & 0x1FFFFFF
        if offset == pm.R_CNT_VAL:
            return self.counts[self._cnt_sel & 0xFF] if self.valid else 0
        raise AssertionError('illegal read 0x%02x' % offset)

    def write(self, offset, value):
        self._tick()
        if offset == pm.R_CNT_SEL:
            self._cnt_sel = value & 0xFF
            return
        if offset != pm.R_CTRL:
            raise AssertionError('illegal write 0x%02x' % offset)
        if value & pm.CTRL_CLEAR:
            self.busy = self.done = self.valid = self.locked = 0
            self.error = 0
            self.raw = 0
            self._pending = None
            return
        if value & pm.CTRL_START:
            self.txn += 1
            self.done = self.valid = 0
            self.raw = 0
            if self.busy or self.locked:
                self.busy = 0
                self.done = 1
                self.error = 0x40
                self.locked = 1
                return
            self.busy = 1
            self.error = 0
            self._pending = self.latency
            self.samples += 1


def driver(mmio):
    return pm.PufMin(mmio, poll_timeout=5.0)


class DriverTests(unittest.TestCase):
    def test_identify_ok(self):
        self.assertEqual(driver(MockMmio()).identify()['id'], pm.ID_EXPECTED)

    def test_wrong_id_rejected(self):
        with self.assertRaises(pm.PufMinError):
            driver(MockMmio(id_value=0xDEADBEEF)).identify()

    def test_dna(self):
        self.assertEqual(driver(MockMmio()).dna(), DNA)

    def test_sample_and_sticky_raw(self):
        d = driver(MockMmio())
        first = d.sample()
        self.assertEqual(first, TRUE_RESPONSE)
        # 不重新 START 也能重复读同一结果
        self.assertEqual(d._read_raw(), TRUE_RESPONSE)
        self.assertTrue(d.status() & pm.ST_VALID)

    def test_clear_zeroes_raw(self):
        d = driver(MockMmio())
        d.sample()
        d.clear()
        self.assertEqual(d._read_raw(), 0)
        self.assertFalse(d.status() & (pm.ST_DONE | pm.ST_VALID))

    def test_busy_start_locks(self):
        m = MockMmio(latency=50)
        d = driver(m)
        d.write(pm.R_CTRL, pm.CTRL_START)
        d.write(pm.R_CTRL, pm.CTRL_START)          # 采样未完成时再次 START
        self.assertTrue(d.status() & pm.ST_LOCKED)
        self.assertEqual(d.error_code(), 0x40)
        d.clear()
        self.assertFalse(d.status() & pm.ST_LOCKED)

    def test_sample_error_raises(self):
        with self.assertRaises(pm.PufMinError) as ctx:
            driver(MockMmio(fail_on_sample=0x08)).sample()
        self.assertEqual(ctx.exception.error_code, 0x08)

    def test_counters_selected(self):
        m = MockMmio()
        d = driver(m)
        d.sample()
        c = d.counters(8)
        self.assertEqual(c, m.counts[:8])
        self.assertNotEqual(c[0], c[4])
        # CNT_SEL 的选择必须真的换到别的计数器，而不是总返回同一个
        d.write(pm.R_CNT_SEL, 200)
        self.assertEqual(d.read(pm.R_CNT_VAL), m.counts[200])

    def test_health_report(self):
        d = driver(MockMmio())
        rep = d.health()
        self.assertEqual(rep['dna'], DNA)
        self.assertEqual(rep['zero_counters'], 0)
        self.assertEqual(len(rep['counts']), pm.N_RINGS)
        self.assertIn('no frequency bound is claimed', rep['note'])


class HelperTests(unittest.TestCase):
    def test_enroll_mask_and_digest(self):
        m = MockMmio(noisy_bits=(5, 17, 99))
        helper = pm.enroll(driver(m), k=15, build_sha='test-sha')
        self.assertGreaterEqual(helper['mask_popcount'], 64)
        for bit in (5, 17, 99):
            self.assertNotIn(bit, [i for i in range(pm.BITS)
                                   if (int(helper['mask'], 0) >> i) & 1])
        self.assertTrue(pm.verify_helper(helper))
        self.assertEqual(helper['inter_hd'], 'not_measured')

    def test_helper_tamper_detected(self):
        helper = pm.enroll(driver(MockMmio()), k=9, build_sha='x')
        helper['ref'] = '0x%032x' % (int(helper['ref'], 0) ^ 1)
        with self.assertRaises(pm.PufMinError):
            pm.verify_helper(helper)

    def test_mask_too_small_rejected(self):
        # 128 位全都带噪声 -> 稳定位不足 64
        m = MockMmio(noisy_bits=tuple(range(pm.BITS)), seed=7)
        with self.assertRaises(pm.PufMinError):
            pm.enroll(driver(m), k=15)

    def test_key_deterministic_and_bound_to_dna(self):
        helper = pm.enroll(driver(MockMmio()), k=9, build_sha='x')
        k1 = pm.key_from_helper(helper)
        k2 = pm.key_from_helper(helper)
        self.assertEqual(k1, k2)
        self.assertEqual(len(k1), 16)
        other = pm.derive_key(DNA ^ 1, int(helper['mask'], 0),
                              int(helper['ref'], 0) & int(helper['mask'], 0))
        self.assertNotEqual(k1, other)

    def test_helper_json_has_no_key(self):
        helper = pm.enroll(driver(MockMmio()), k=9, build_sha='x')
        key = pm.key_from_helper(helper)
        blob = json.dumps(helper)
        self.assertNotIn(key.hex(), blob)
        self.assertIn('secret_warning', helper)


class ClosedLoopTests(unittest.TestCase):
    """enroll -> seal -> reconstruct：tag 验证通过才算闭环 PASS。"""

    def _plan(self, **mock_kwargs):
        helper = pm.enroll(driver(MockMmio(**mock_kwargs)), k=15, build_sha='b1')
        sealed = pm.seal(pm.key_from_helper(helper), nonce=bytes(range(16)))
        sealed['helper_sha256'] = helper['sha256']
        return helper, sealed

    def test_closed_loop_pass(self):
        helper, sealed = self._plan(noisy_bits=(3, 44))
        res = pm.reconstruct(driver(MockMmio(noisy_bits=(3, 44))), helper,
                             samples=15, sealed=sealed)
        self.assertEqual(res['closed_loop'], 'PASS')
        self.assertTrue(res['aead_tag_ok'])
        self.assertTrue(res['plaintext_matches'])
        self.assertTrue(res['tampered_rejected'])
        self.assertEqual(res['masked_ber'], 0.0)
        self.assertTrue(res['dna_matches_helper'])

    def test_tampered_ciphertext_rejected(self):
        helper, sealed = self._plan()
        key = pm.key_from_helper(helper)
        self.assertIsNotNone(pm.open_sealed(key, sealed))
        self.assertIsNone(pm.open_sealed(key, pm.tamper(sealed)))

    def test_wrong_dna_breaks_loop(self):
        helper, sealed = self._plan()
        res = pm.reconstruct(driver(MockMmio(dna=DNA ^ 0x5)), helper,
                             samples=15, sealed=sealed)
        self.assertFalse(res['dna_matches_helper'])
        self.assertEqual(res['closed_loop'], 'FAIL')

    def test_noise_inside_mask_breaks_loop(self):
        helper, sealed = self._plan()            # 无噪声 enroll -> MASK 覆盖全部 128 位
        masked_noise = (0, 1, 2, 3, 4, 5, 6, 7)
        res = pm.reconstruct(driver(MockMmio(noisy_bits=masked_noise)), helper,
                             samples=15, sealed=sealed)
        self.assertEqual(res['closed_loop'], 'FAIL')
        self.assertGreater(res['masked_ber'], 0.0)
        self.assertFalse(res['aead_tag_ok'])

    def test_seal_does_not_store_key(self):
        helper, sealed = self._plan()
        key = pm.key_from_helper(helper)
        blob = json.dumps(sealed)
        self.assertNotIn(key.hex(), blob)
        self.assertFalse(sealed['key_on_disk'])


class StatsTests(unittest.TestCase):
    def test_raw_stats(self):
        st = pm.raw_stats([TRUE_RESPONSE, TRUE_RESPONSE])
        self.assertEqual(st['samples'], 2)
        self.assertEqual(st['stable_bits'], pm.BITS)
        self.assertEqual(st['intra_hd_max'], 0)
        self.assertEqual(st['inter_hd'], 'not_measured')

    def test_hamming_helpers(self):
        self.assertEqual(pm.hamming(0, 0xFF), 8)
        ber, dist, pop = pm.masked_ber(0b1010, 0b0010, 0b1111)
        self.assertEqual((dist, pop), (1, 4))
        self.assertAlmostEqual(ber, 0.25)


class AsconTests(unittest.TestCase):
    """E5：仓库内 pyascon 可用性与往返一致性。标准 KAT 证据见 data/ascon/results/host_validation.log。"""

    def test_import_and_roundtrip(self):
        key = bytes(range(16))
        nonce = bytes(range(16))
        ad = b'ad'
        pt = b'0123456789abcdef'
        sealed = pm.seal(key, plaintext=pt, ad=ad, nonce=nonce)
        self.assertEqual(pm.open_sealed(key, sealed), pt)
        self.assertIsNone(pm.open_sealed(bytes(16), sealed))

    def test_pinned_vector(self):
        # 回归钉子：同一输入必须永远产生同一密文/标签（防止参考实现被静默替换）
        vec = json.loads((Path(__file__).with_name('puf_min_ascon_vector.json'))
                         .read_text(encoding='utf-8'))
        sealed = pm.seal(bytes.fromhex(vec['key']),
                        plaintext=bytes.fromhex(vec['plaintext']),
                        ad=bytes.fromhex(vec['ad']),
                        nonce=bytes.fromhex(vec['nonce']))
        self.assertEqual(sealed['ciphertext'] + sealed['tag'], vec['ciphertext_and_tag'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
