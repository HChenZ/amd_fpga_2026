"""Guards the fake PYNQ API surface that graded solutions are allowed to use.

The instrument must expose the same entry points a real PYNQ 2.7 host script uses, otherwise a
*correct* solution is graded 0 for an `ImportError` that only exists in the fake. This caught
`pynq.Bitstream` missing (a solution that verifies the bitstream before programming the PL).
"""
import hashlib
import os
import sys

import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
HARNESS = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(HARNESS, 'fake_pynq'))
sys.path.insert(0, HARNESS)

import pynq  # noqa: E402
import tasks  # noqa: E402


@pytest.fixture(autouse=True)
def _reset_trace():
    pynq.TRACE['downloads'] = 0
    pynq.TRACE['downloaded'] = []
    pynq.TRACE['events'] = []
    yield


def _bit_sha(data):
    return hashlib.sha256(data).hexdigest()


def _pair(tmp_path, base=0x43C00000):
    """A .bit/.hwh pair with a VLNV-bearing IP, written the same way T1 scenarios do it."""
    bit = bytes(range(256)) * 4
    hwh = tasks.make_hwh([{'fullname': 'accel_0', 'vlnv': tasks.T1_VLNV, 'base': base}])
    bit_path = tmp_path / 'accel.bit'
    bit_path.write_bytes(bit)
    (tmp_path / 'accel.hwh').write_text(hwh, encoding='utf-8')
    return bit_path, hashlib.sha256(bit).hexdigest()


def test_bitstream_parses_without_downloading(tmp_path):
    bit_path, sha = _pair(tmp_path)
    bs = pynq.Bitstream(str(bit_path))
    assert pynq.TRACE['downloads'] == 0, 'constructing a Bitstream must not program the PL'
    assert bs.downloaded is False
    assert bs.is_loaded() is False
    assert bs.bitfile_name == str(bit_path.resolve())
    assert bs.binfile_name.endswith('.bin')
    assert bs.hash == hashlib.md5(bit_path.read_bytes()).hexdigest()
    assert isinstance(bs.timestamp, str) and bs.timestamp
    assert bs._sha == sha, 'Bitstream and Overlay must agree on which bytes they would program'


def test_bitstream_download_is_counted(tmp_path):
    bit_path, _ = _pair(tmp_path)
    bs = pynq.Bitstream(str(bit_path))
    bs.download()
    assert pynq.TRACE['downloads'] == 1
    assert bs.downloaded is True
    assert bs.is_loaded() is True


def test_bitstream_missing_file_raises_ioerror(tmp_path):
    with pytest.raises(IOError):
        pynq.Bitstream(str(tmp_path / 'nope.bit'))


def test_bram_window_is_byte_addressable_memory(tmp_path):
    """AXI BRAM is a memory window, not a register file: 32-bit words, no reset values."""
    bit = tasks.make_hwh([{'fullname': 'bram_0', 'vlnv': 'xilinx.com:ip:axi_bram_ctrl:4.1',
                           'base': 0x40000000, 'size': 0x1000}])
    (tmp_path / 'b.bit').write_bytes(b'bit')
    (tmp_path / 'b.hwh').write_text(bit, encoding='utf-8')
    scen = tmp_path / 'scen.json'
    scen.write_text('{"hardware": {"%s": [{"kind": "axi_bram", "base": "0x40000000", '
                    '"size": 4096, "prefill": "0011223344556677"}]}}' % _bit_sha(b'bit'),
                    encoding='utf-8')
    os.environ['FAKE_PYNQ_SCENARIO'] = str(scen)
    try:
        import importlib
        import pynq as fake
        importlib.reload(fake)
        pynq.TRACE['downloads'] = 0
        pynq.TRACE['downloaded'] = []
        ol = fake.Overlay(str(tmp_path / 'b.bit'))
        mmio = fake.MMIO(0x40000000, 0x1000, device=ol.device)
        assert mmio.read(0x00) == 0x33221100, 'prefill must be visible as little-endian words'
        assert mmio.read(0x04) == 0x77665544
        mmio.write(0x00, 0xDEADBEEF)
        assert mmio.read(0x00) == 0xDEADBEEF
        assert mmio.read(0x04) == 0x77665544, 'writing one word must not touch its neighbour'
        try:
            mmio.write(0x01, 0)          # unaligned access does not exist on the bus
        except ValueError:
            pass
        else:
            raise AssertionError('unaligned MMIO write must be rejected')
    finally:
        os.environ.pop('FAKE_PYNQ_SCENARIO', None)
        import importlib
        import pynq as fake
        importlib.reload(fake)


def test_bram_beyond_64k_window_is_routed(tmp_path):
    """A 32 KiB BRAM at 0x42000000 must be reachable (span, not the old fixed 64 KiB)."""
    bit = tasks.make_hwh([{'fullname': 'io/bram_0', 'vlnv': 'xilinx.com:ip:axi_bram_ctrl:4.1',
                           'base': 0x42000000, 'size': 0x8000}])
    (tmp_path / 'c.bit').write_bytes(b'bit2')
    (tmp_path / 'c.hwh').write_text(bit, encoding='utf-8')
    scen = tmp_path / 'scen.json'
    scen.write_text('{"hardware": {"%s": [{"kind": "axi_bram", "base": "0x42000000", '
                    '"size": 32768, "prefill": ""}]}}' % _bit_sha(b'bit2'), encoding='utf-8')
    os.environ['FAKE_PYNQ_SCENARIO'] = str(scen)
    try:
        import importlib
        import pynq as fake
        importlib.reload(fake)
        pynq.TRACE['downloads'] = 0
        pynq.TRACE['downloaded'] = []
        fake.Overlay(str(tmp_path / 'c.bit'))
        mmio = fake.MMIO(0x42000000, 0x8000)
        mmio.write(0x7FFC, 0x01020304)
        assert mmio.read(0x7FFC) == 0x01020304
        assert mmio.read(0x0000) == 0
    finally:
        os.environ.pop('FAKE_PYNQ_SCENARIO', None)
        import importlib
        import pynq as fake
        importlib.reload(fake)


def test_overlay_and_bitstream_agree_on_bytes(tmp_path):
    bit_path, sha = _pair(tmp_path)
    bs = pynq.Bitstream(str(bit_path))
    ol = pynq.Overlay(str(bit_path), download=False)
    assert ol._sha == bs._sha == sha
    assert pynq.TRACE['downloads'] == 0
    ol.download()
    assert pynq.TRACE['downloads'] == 1


def test_overlay_exposes_hierarchy_and_device_like_pynq(tmp_path):
    """Host code locates an IP by VLNV by walking ip_dict + hierarchy_dict (no hardcoded name)."""
    bit = tasks.make_hwh([{'fullname': 'proc/accel_0', 'vlnv': tasks.T1_VLNV, 'base': 0x43C20000},
                          {'fullname': 'axi_gpio_0', 'vlnv': 'xilinx.com:ip:axi_gpio:2.0',
                           'base': 0x41200000}])
    (tmp_path / 'h.bit').write_bytes(b'bit')
    (tmp_path / 'h.hwh').write_text(bit, encoding='utf-8')
    ol = pynq.Overlay(str(tmp_path / 'h.bit'), download=False)

    root = ol.hierarchy_dict['']
    assert root['fullpath'] == ''
    assert set(root['ip']) == {'axi_gpio_0'}
    assert root['hierarchies']['proc']['fullpath'] == 'proc'
    assert set(root['hierarchies']['proc']['ip']) == {'accel_0'}

    found = []
    stack = list(ol.hierarchy_dict.values())
    while stack:
        node = stack.pop()
        found += [d['type'] for d in node['ip'].values()]
        stack += list(node['hierarchies'].values())
    found += [d['type'] for d in ol.ip_dict.values()]
    assert tasks.T1_VLNV in found, 'VLNV must be reachable through hierarchy_dict + ip_dict'

    assert ol.device is not None and ol.device.bitfile_name == ol.bitfile_name
    assert ol.hash == hashlib.md5(b'bit').hexdigest()
