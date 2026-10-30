import pytest
from conftest import FIXTURES, REAL_UTIL

from pynq_skill import dma, golden, hwh, report
from pynq_skill.fakes import FakeAllocator, FakeAxiDma, FakeDDR, ManualClock


def make(fault=None, process=None, coherent=False):
    ddr = FakeDDR()
    clk = ManualClock()
    dev = FakeAxiDma(ddr, process=process, fault=fault)
    return dma.BoundedSimpleDMA(dev, clock=clk, sleep=clk.sleep), dev, FakeAllocator(ddr, coherent=coherent)


def test_fake_models_non_coherence():
    _, _, alloc = make()
    buf = alloc((8,))
    buf[:] = b'ABCDEFGH'
    assert buf.ddr.read(buf.physical_address, 8) == bytes(8)   # still only in CPU view
    buf.flush()
    assert buf.ddr.read(buf.physical_address, 8) == b'ABCDEFGH'


def test_roundtrip_with_cache_maintenance():
    d, dev, alloc = make(process=lambda b: bytes(x ^ 0xFF for x in b))
    tx, rx = alloc((64,)), alloc((64,))
    tx[:] = bytes(range(64))
    rx[:] = b'\xA5' * 64                                         # sentinel
    n = d.transfer(tx, rx, timeout_s=0.1)
    assert n == 64
    golden.check(bytes(rx)[:n], bytes(x ^ 0xFF for x in range(64)), sentinel=0xA5)
    assert tx.flushes == 1 and rx.invalidates == 1
    ops = [e[1] for e in dev.log if e[0] == 'w' and e[1] in (0x28, 0x58)]
    assert ops == [0x58, 0x28]                                   # receive armed before send


def test_short_packet_returns_actual_length():
    d, _, alloc = make(fault='short')
    tx, rx = alloc((32,)), alloc((32,))
    tx[:] = bytes(range(32))
    assert d.transfer(tx, rx, timeout_s=0.1) == 28


def test_missing_tlast_times_out_with_decoded_status():
    d, _, alloc = make(fault='no_tlast')
    tx, rx = alloc((16,)), alloc((16,))
    with pytest.raises(dma.DMAError, match='timeout waiting for transfer completion') as e:
        d.transfer(tx, rx, timeout_s=0.01)
    assert 'S2MM DMASR' in str(e.value)
    assert not d.retained                                         # reset proved halt -> safe to release


def test_slave_error_is_decoded():
    d, _, alloc = make(fault='slave_error')
    with pytest.raises(dma.DMAError, match='DMASlvErr'):
        d.transfer(alloc((16,)), alloc((16,)), timeout_s=0.1)


def test_rx_too_small_reports_internal_error():
    d, _, alloc = make()
    tx, rx = alloc((32,)), alloc((16,))
    with pytest.raises(dma.DMAError, match='DMAIntErr'):
        d.transfer(tx, rx, timeout_s=0.1)


def test_stuck_reset_quarantines_buffers():
    # transfer hangs (no TLAST) AND the reset never completes -> cannot prove the DMA stopped
    d, dev, alloc = make(fault='no_tlast')
    tx, rx = alloc((16,)), alloc((16,))
    plain_write = dev.write

    def write(off, val):
        if off == 0 and val & 4:
            dev.mem[0] = 4
            return
        plain_write(off, val)
    dev.write = write
    with pytest.raises(dma.DMAQuarantine):
        d.transfer(tx, rx, timeout_s=0.01)
    assert d.retained == [tx, rx]
    with pytest.raises(dma.DMAQuarantine):
        d.transfer(tx, rx, timeout_s=0.01)


def test_alignment_and_limits_from_hwh():
    info = hwh.parse_hwh(str(FIXTURES / 'mini_zynqmp.hwh'))
    cfg = dma.config_from_hwh(info['ips']['dma_hier/axi_dma_0']['parameters'])
    assert cfg == {'max_transfer': 16383, 'align': {0x00: 8, 0x30: 1}}
    d, dev, alloc = make()
    d.align = cfg['align']
    tx = alloc((16,))
    tx.physical_address += 4
    with pytest.raises(ValueError, match='not aligned to 8'):
        d.transfer(tx, alloc((16,)), timeout_s=0.1)
    with pytest.raises(dma.DMAError, match='scatter-gather'):
        dma.config_from_hwh({'c_include_sg': '1'})


@pytest.mark.parametrize('actual,expected,kw,hint', [
    (b'\xA5' * 8, b'12345678', {'sentinel': 0xA5}, 'all_sentinel'),
    (bytes(8), b'12345678', {}, 'all_zero'),
    (b'abcdefgh', b'12345678', {'previous': b'abcdefgh'}, 'equals_previous'),
    (b'43218765', b'12345678', {}, 'byte_swapped_words'),
    (b'\x00\x00' + bytes(range(1, 15)), bytes(range(1, 17)), {}, 'shifted_by_2'),
    (bytes(range(16))[:-1] + b'\xff', bytes(range(16)), {}, 'tail_only'),
    (bytes(range(12)), bytes(range(16)), {}, 'length_mismatch'),
])
def test_golden_hints(actual, expected, kw, hint):
    assert golden.compare(actual, expected, **kw)['hint'] == hint


def test_mutation_guard():
    assert golden.mutation_must_fail(golden.check, b'abc', b'abd')
    with pytest.raises(Exception, match='NOT detected'):
        golden.mutation_must_fail(lambda a, b: None, b'abc', b'abd')
    assert golden.boundary_lengths(16, 4) == [0, 1, 3, 4, 5, 15, 16]


def test_measure_cold_warm():
    t = iter(range(0, 10 ** 9, 1000))
    st = golden.measure(lambda: None, warmup=2, repeat=5, clock=lambda: next(t), label='noop', evidence='simulated')
    assert st['n'] == 5 and st['cold'] == 1.0 and st['evidence'] == 'simulated'


@pytest.mark.skipif(not REAL_UTIL.exists(), reason='real utilization report not available')
def test_real_utilization_report():
    u = report.parse_utilization(str(REAL_UTIL))
    assert u['header']['device'] == 'xc7z020clg400-1'
    assert u['summary']['Slice LUTs']['available'] == 53200
    assert u['summary']['Register as Latch']['used'] == 0


def test_report_requires_evidence_class(tmp_path):
    with pytest.raises(ValueError, match='evidence'):
        report.build_report(title='t', timings=[{'label': 'x', 'n': 1}])
    data, md = report.build_report(title='t', results=[golden.compare(b'a', b'a')],
                                   timings=[golden.measure(lambda: None, repeat=3, evidence='simulated')])
    report.write_report(str(tmp_path / 'r.md'), data, md)
    assert '1/1 passed' in md and 'not_measured' in md and (tmp_path / 'r.json').exists()
