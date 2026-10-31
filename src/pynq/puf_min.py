"""PUF-MIN 主机侧驱动 + enroll / reconstruct / key / seal / stats 闭环。

对应任务 tasks/puf_fix_and_min_goal_20261030.md §4.3（寄存器 ABI）与 §4.6（软件闭环）。

边界声明（不得含糊上移）：
  * RAW 可以被任意读回，**没有保密性**；
  * 落盘的 helper 里直接保存 REF（响应比特），这只是演示用的 helper，不是安全 sketch，
    没有 ECC、没有熵证明、没有经过验证的提取器；
  * 派生密钥是 SHA-256 截断，仅用于"用同一密钥做一次可验证的密码操作"这个闭环演示；
  * 未测：温度/电压/老化可靠性、多板唯一性（inter-HD）、安全启动、防回滚。

寄存器（字节偏移，见 src/rtl/puf_min/puf_min_axil.v）：
  0x00 ID  0x04 VERSION  0x08 CTRL  0x0c STATUS  0x10 ERROR  0x14 TXN
  0x20..0x2c RAW[0..3]  0x30 DNA_LO  0x34 DNA_HI  0x40 CNT_SEL  0x44 CNT_VAL
"""
from __future__ import annotations

import hashlib
import json
import os
import time
from dataclasses import dataclass, field

ID_EXPECTED = 0x4E494D50          # "PMIN"
VERSION_EXPECTED = 1

R_ID = 0x00
R_VERSION = 0x04
R_CTRL = 0x08
R_STATUS = 0x0C
R_ERROR = 0x10
R_TXN = 0x14
R_RAW0 = 0x20
R_DNA_LO = 0x30
R_DNA_HI = 0x34
R_CNT_SEL = 0x40
R_CNT_VAL = 0x44

CTRL_START = 0x1
CTRL_CLEAR = 0x2

ST_BUSY = 1 << 0
ST_DONE = 1 << 1
ST_VALID = 1 << 2
ST_LOCKED = 1 << 3
ST_DNA_READY = 1 << 4

# 事件码（与 src/rtl/keys_v2/ro_puf_core_v2.v 的 error_code 一一对应）
ERROR_MEANING = {
    0x00: 'ok',
    0x01: 'ro watchdog: no ring edge seen before RO_DEADLINE',
    0x02: 'core deadline before completion',
    0x04: 'zero counter value in a ring pair',
    0x08: 'tied ring pair (equal counts)',
    0x10: 'counter saturation',
    0x20: 'all ring comparisons same direction',
    0x40: 'overlapping START while busy / already locked',
    0x81: 'key lifecycle error (not used by PUF-MIN)',
    0x85: 'internal timeout',
}

N_RINGS = 256
BITS = 128
BITS_PER_SAMPLE = BITS


class PufMinError(RuntimeError):
    def __init__(self, message, error_code=None, status=None):
        super().__init__(message)
        self.error_code = error_code
        self.status = status


# ---------------------------------------------------------------------------
# 驱动
# ---------------------------------------------------------------------------
class PufMin:
    """极简 MMIO 驱动。任何带 read(offset)/write(offset, value) 的对象都能注入。"""

    def __init__(self, mmio, *, poll_timeout=0.5, settle_time=0.0):
        self.mmio = mmio
        self.poll_timeout = poll_timeout
        self.settle_time = settle_time

    # ---- 基础访问 ----
    def read(self, offset):
        return int(self.mmio.read(offset)) & 0xFFFFFFFF

    def write(self, offset, value):
        self.mmio.write(offset, int(value) & 0xFFFFFFFF)

    @classmethod
    def from_overlay(cls, bitstream, name='puf_core', **kwargs):
        """在 PYNQ 上从 .bit 加载并绑定 MEMRANGE 里那个寄存器窗口。"""
        import pynq  # 延迟导入：离线单测不需要 pynq

        overlay = pynq.Overlay(str(bitstream), download=True)
        if name not in overlay.ip_dict:
            raise PufMinError('HWH 里没有实例 %r；实际实例：%s'
                              % (name, sorted(overlay.ip_dict)))
        driver = overlay.ip_dict[name]
        mmio = pynq.MMIO(driver['phys_addr'], driver['addr_range'])
        obj = cls(mmio, **kwargs)
        obj.overlay = overlay
        return obj

    # ---- 身份 ----
    def identify(self):
        ident = self.read(R_ID)
        if ident != ID_EXPECTED:
            raise PufMinError('ID=0x%08x，期望 0x%08x ("PMIN")' % (ident, ID_EXPECTED))
        version = self.read(R_VERSION)
        if version != VERSION_EXPECTED:
            raise PufMinError('VERSION=%d，期望 %d' % (version, VERSION_EXPECTED))
        return {'id': ident, 'version': version}

    def status(self):
        return self.read(R_STATUS)

    def error_code(self):
        return self.read(R_ERROR)

    def transaction(self):
        return self.read(R_TXN)

    def dna(self):
        """等 dna_ready 后返回 57-bit DNA。位序需上板与 Hardware Manager 核对。"""
        deadline = time.monotonic() + self.poll_timeout
        while True:
            st = self.status()
            if st & ST_DNA_READY:
                break
            if time.monotonic() > deadline:
                raise PufMinError('dna_ready 超时 (status=0x%08x)' % st, status=st)
            time.sleep(0.0002)
        lo = self.read(R_DNA_LO)
        hi = self.read(R_DNA_HI) & 0x1FFFFFF
        return (hi << 32) | lo

    # ---- 采样 ----
    def clear(self):
        self.write(R_CTRL, CTRL_CLEAR)

    def sample(self, *, start=True, budget=None):
        """一次 START->done 采样，返回 128-bit 响应（整数，bit i 对应 RAW 的 bit i）。"""
        if start:
            self.write(R_CTRL, CTRL_START)
        deadline = time.monotonic() + self.poll_timeout
        polls = 0
        limit = budget if budget is not None else 1 << 22
        while True:
            st = self.status()
            if st & ST_DONE:
                break
            polls += 1
            if polls > limit or time.monotonic() > deadline:
                raise PufMinError('采样 done 超时 (status=0x%08x)' % st, status=st)
            if self.settle_time:
                time.sleep(self.settle_time)
        err = self.error_code()
        if not (st & ST_VALID) or err:
            raise PufMinError('采样失败：error=0x%02x (%s) status=0x%08x'
                              % (err, ERROR_MEANING.get(err, 'unknown'), st),
                              error_code=err, status=st)
        return self._read_raw()

    def _read_raw(self):
        words = [self.read(R_RAW0 + 4 * i) for i in range(4)]
        return sum(w << (32 * i) for i, w in enumerate(words))

    def raw_words(self):
        return [self.read(R_RAW0 + 4 * i) for i in range(4)]

    # ---- 诊断计数 ----
    def counters(self, n=N_RINGS):
        vals = []
        for i in range(n):
            self.write(R_CNT_SEL, i)
            vals.append(self.read(R_CNT_VAL))
        self.write(R_CNT_SEL, 0)
        return vals

    def health(self):
        """ID/VERSION/DNA + 计数分布统计。不宣称熵。"""
        ident = self.identify()
        dna = self.dna()
        self.clear()
        self.sample()
        counts = self.counters()
        pairs = [(counts[j], counts[j + BITS]) for j in range(BITS)]
        report = {
            'id': ident['id'],
            'version': ident['version'],
            'dna': dna,
            'dna_hex': '0x%015x' % dna,
            'count_min': min(counts),
            'count_max': max(counts),
            'count_mean': sum(counts) / len(counts),
            'zero_counters': sum(1 for c in counts if c == 0),
            'saturated_counters': sum(1 for c in counts if c == (1 << 20) - 1),
            'tied_pairs': sum(1 for a, b in pairs if a == b),
            'comparison_ones': sum(1 for a, b in pairs if a > b),
            'counts': counts,
            'note': 'counts are raw oscillator counts; no frequency bound is claimed',
        }
        return report


# ---------------------------------------------------------------------------
# 比特/统计工具
# ---------------------------------------------------------------------------
def bits_of(value, n=BITS):
    return [(value >> i) & 1 for i in range(n)]


def from_bits(bits):
    value = 0
    for i, b in enumerate(bits):
        if b:
            value |= 1 << i
    return value


def hamming(a, b, n=BITS):
    return bin((a ^ b) & ((1 << n) - 1)).count('1')


def masked_ber(a, b, mask):
    pop = bin(mask).count('1')
    if pop == 0:
        return 1.0, 0, 0
    dist = hamming(a & mask, b & mask)
    return dist / pop, dist, pop


def build_helper(samples, dna, build_sha, *, min_mask_bits=64):
    """K 次采样 -> 逐位多数表决 REF；所有样本一致的位构成 MASK。"""
    if not samples:
        raise ValueError('samples 不能为空')
    n = len(samples)
    ones = [0] * BITS
    for s in samples:
        for i in range(BITS):
            ones[i] += (s >> i) & 1
    ref = 0
    for i in range(BITS):
        if ones[i] * 2 >= n:
            ref |= 1 << i
    mask = 0
    for i in range(BITS):
        if ones[i] == n or ones[i] == 0:
            mask |= 1 << i
    pop = bin(mask).count('1')
    if pop < min_mask_bits:
        raise PufMinError('稳定位只有 %d bit，低于下限 %d；拒绝生成 helper'
                          % (pop, min_mask_bits))
    unstable = [i for i in range(BITS) if not (mask >> i) & 1]
    helper = {
        'schema': 'puf_min_helper_v1',
        'dna': '0x%015x' % dna,
        'build_sha': build_sha,
        'k': n,
        'ref': '0x%032x' % ref,
        'mask': '0x%032x' % mask,
        'mask_popcount': pop,
        'unstable_bits': unstable,
        'per_bit_ones': ones,
        'raw_samples': ['0x%032x' % s for s in samples],
        'secret_warning': 'REF 是响应比特，落盘即泄露响应；这是演示 helper，不是安全 sketch',
        'inter_hd': 'not_measured',
    }
    helper['sha256'] = helper_digest(helper)
    return helper


def helper_digest(helper):
    body = {k: v for k, v in helper.items() if k != 'sha256'}
    blob = json.dumps(body, sort_keys=True, separators=(',', ':')).encode()
    return hashlib.sha256(blob).hexdigest()


def verify_helper(helper):
    if helper.get('schema') != 'puf_min_helper_v1':
        raise PufMinError('helper schema 不对：%r' % helper.get('schema'))
    if helper.get('sha256') != helper_digest(helper):
        raise PufMinError('helper sha256 校验失败（文件被改动？）')
    return True


def _as_int(value):
    """接受 int 或 '0x...' 字符串（helper JSON 里是十六进制字符串）。"""
    return int(value, 0) if isinstance(value, str) else int(value)


def derive_key(dna, mask, material):
    """key = SHA-256("PUF-MIN-v1" || DNA || (REF&MASK) || MASK)[:16]。非标准 KDF。"""
    payload = b'PUF-MIN-v1' + _as_int(dna).to_bytes(8, 'big')
    payload += _as_int(material).to_bytes(16, 'big')
    payload += _as_int(mask).to_bytes(16, 'big')
    return hashlib.sha256(payload).digest()[:16]


def key_from_helper(helper):
    verify_helper(helper)
    dna = int(helper['dna'], 0)
    mask = int(helper['mask'], 0)
    ref = int(helper['ref'], 0)
    return derive_key(dna, mask, ref & mask)


# ---------------------------------------------------------------------------
# Ascon-AEAD128 闭环
# ---------------------------------------------------------------------------
_DEMO_PT = b'PUF-MIN demo-msg'   # 16 字节固定明文
_DEMO_AD = b'PUF-MIN'


def _ascon():
    try:
        from ascon.pyascon.ascon import ascon_encrypt, ascon_decrypt  # 仓库内参考实现
    except ImportError:  # 作为独立脚本运行时的回落
        import sys
        from pathlib import Path
        sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
        from ascon.pyascon.ascon import ascon_encrypt, ascon_decrypt
    return ascon_encrypt, ascon_decrypt


def seal(key, *, plaintext=_DEMO_PT, ad=_DEMO_AD, nonce=None):
    """用 key 做一次 Ascon-AEAD128 加密；落盘 nonce/ct/tag，**key 不落盘**。"""
    enc, _ = _ascon()
    if nonce is None:
        nonce = os.urandom(16)   # PUF-MIN 不提供 TRNG；nonce 只是 AEAD 演示参数
    blob = enc(key, nonce, ad, plaintext, 'Ascon-AEAD128')
    ct, tag = blob[:len(plaintext)], blob[len(plaintext):]
    return {
        'schema': 'puf_min_sealed_v1',
        'aead': 'Ascon-AEAD128',
        'nonce': nonce.hex(),
        'ad': ad.hex(),
        'ciphertext': ct.hex(),
        'tag': tag.hex(),
        'plaintext_len': len(plaintext),
        'key_on_disk': False,
    }


def open_sealed(key, sealed):
    _, dec = _ascon()
    blob = bytes.fromhex(sealed['ciphertext']) + bytes.fromhex(sealed['tag'])
    return dec(key, bytes.fromhex(sealed['nonce']), bytes.fromhex(sealed['ad']),
               blob, 'Ascon-AEAD128')


def tamper(sealed):
    """把密文翻 1 bit，用于"篡改必须被拒"的负向测试。"""
    ct = bytearray(bytes.fromhex(sealed['ciphertext']))
    ct[0] ^= 0x01
    out = dict(sealed)
    out['ciphertext'] = bytes(ct).hex()
    return out


def reconstruct(driver, helper, samples=15, *, sealed=None, plaintext=_DEMO_PT):
    """重载 bitstream / 重启后的重建：多数表决 -> 与 REF 比对 -> 重新派生 key -> 解密验 tag。"""
    verify_helper(helper)
    dna = driver.dna()
    mask = int(helper['mask'], 0)
    ref = int(helper['ref'], 0)
    driver.clear()
    raws = [driver.sample() for _ in range(samples)]
    ones = [0] * BITS
    for s in raws:
        for i in range(BITS):
            ones[i] += (s >> i) & 1
    voted = 0
    for i in range(BITS):
        if ones[i] * 2 >= samples:
            voted |= 1 << i
    ber, dist, pop = masked_ber(ref, voted, mask)
    maskable = ref & mask
    voted_maskable = voted & mask
    mask_stable = maskable == voted_maskable
    result = {
        'samples': samples,
        'dna_now': '0x%015x' % dna,
        'dna_matches_helper': ('0x%015x' % dna) == helper['dna'],
        'mask_popcount': pop,
        'masked_ber': ber,
        'masked_hamming': dist,
        'masked_bits_stable': mask_stable,
        'helper_k': helper['k'],
        'raw': ['0x%032x' % s for s in raws],
        'inter_hd': 'not_measured',
        'entropy_claim': 'none',
    }
    result['key_available'] = mask_stable
    verdict = {'dna_binding': result['dna_matches_helper'],
               'mask_bits_stable': mask_stable}
    if sealed is not None:
        if not mask_stable:
            result['aead_tag_ok'] = False
            result['closed_loop'] = 'FAIL: MASK 内的位不一致，key 不可复现'
        else:
            key = derive_key(dna, mask, voted_maskable)
            pt = open_sealed(key, sealed)
            result['aead_tag_ok'] = pt is not None
            result['plaintext_matches'] = (pt == plaintext)
            tampered = tamper(sealed)
            result['tampered_rejected'] = open_sealed(key, tampered) is None
            verdict['aead_tag_ok'] = result['aead_tag_ok']
            verdict['tampered_rejected'] = result['tampered_rejected']
        result['closed_loop'] = 'PASS' if all(verdict.values()) else 'FAIL'
    result['verdict'] = verdict
    return result


def enroll(driver, *, k=15, build_sha='unversioned', min_mask_bits=64):
    driver.identify()
    dna = driver.dna()
    driver.clear()
    samples = [driver.sample() for _ in range(k)]
    helper = build_helper(samples, dna, build_sha, min_mask_bits=min_mask_bits)
    intra = max((hamming(a, b) for a in samples for b in samples), default=0)
    helper['intra_hd_max'] = intra
    helper['intra_hd_max_ratio'] = intra / BITS
    helper['sha256'] = helper_digest(helper)
    return helper


def raw_stats(samples):
    """统计工具：汉明重量/均匀度/稳定位比例/两两汉明距离。"""
    n = len(samples)
    if n == 0:
        return {'samples': 0}
    weights = [bin(s & ((1 << BITS) - 1)).count('1') for s in samples]
    ones = [0] * BITS
    for s in samples:
        for i in range(BITS):
            ones[i] += (s >> i) & 1
    stable = sum(1 for c in ones if c == n or c == 0)
    dists = [hamming(a, b) for i, a in enumerate(samples) for b in samples[i + 1:]]
    return {
        'samples': n,
        'hamming_weight': weights,
        'hamming_weight_mean': sum(weights) / n,
        'balance_ratio': sum(weights) / (n * BITS),
        'stable_bits': stable,
        'stable_ratio': stable / BITS,
        'intra_hd_mean': (sum(dists) / len(dists)) if dists else 0,
        'intra_hd_max': max(dists) if dists else 0,
        'inter_hd': 'not_measured',
        'entropy_claim': 'none',
    }


def main(argv=None):
    import argparse

    p = argparse.ArgumentParser(description='PUF-MIN host demo')
    p.add_argument('--bit', required=True, help='puf_min .bit 路径')
    p.add_argument('--instance', default='puf_core')
    p.add_argument('--cmd', default='health',
                   choices=['health', 'enroll', 'reconstruct', 'stats'])
    p.add_argument('--helper', help='enroll 输出 / reconstruct 输入')
    p.add_argument('--sealed', help='seal JSON')
    p.add_argument('--k', type=int, default=15)
    p.add_argument('--out')
    a = p.parse_args(argv)

    drv = PufMin.from_overlay(a.bit, a.instance)
    if a.cmd == 'health':
        out = drv.health()
    elif a.cmd == 'stats':
        drv.clear()
        out = raw_stats([drv.sample() for _ in range(a.k)])
    elif a.cmd == 'enroll':
        helper = enroll(drv, k=a.k)
        key = key_from_helper(helper)
        plan = {'helper': helper, 'sealed': seal(key)}
        plan['sealed']['helper_sha256'] = helper['sha256']
        out = plan
    else:
        helper = json.loads(open(a.helper, encoding='utf-8').read())
        sealed = json.loads(open(a.sealed, encoding='utf-8').read())
        out = reconstruct(drv, helper, samples=a.k, sealed=sealed)
    text = json.dumps(out, indent=2, sort_keys=True, default=str)
    if a.out:
        with open(a.out, 'w', encoding='utf-8') as f:
            f.write(text + '\n')
    print(text)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
