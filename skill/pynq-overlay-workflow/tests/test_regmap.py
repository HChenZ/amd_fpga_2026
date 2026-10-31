import os
import subprocess
import sys

import pytest
from conftest import EXAMPLES, FIXTURES, SKILL

from pynq_skill import hls_ctrl, hwh, regmap
from pynq_skill.fakes import FakeMMIO, ManualClock


@pytest.mark.parametrize('name', ['axi_gpio', 'hls_vadd', 'axi_dma_simple'])
def test_examples_are_valid(name):
    c = regmap.load_contract(str(EXAMPLES / ('%s.contract.json' % name)))
    assert c['registers']


@pytest.mark.parametrize('bad,msg', [
    ({'registers': [{'name': 'A', 'offset': 2}]}, 'not 4-byte aligned'),
    ({'registers': [{'name': 'A', 'offset': 0}, {'name': 'B', 'offset': 0}]}, 'overlaps'),
    ({'addr_range': 16, 'registers': [{'name': 'A', 'offset': 16}]}, 'outside addr_range'),
    ({'registers': [{'name': 'A', 'offset': 0, 'access': 'rx'}]}, 'access'),
    ({'registers': [{'name': 'A', 'offset': 0, 'fields': [{'name': 'X', 'lsb': 0, 'width': 4},
                                                         {'name': 'Y', 'lsb': 3, 'width': 1}]}]}, 'overlaps another field'),
    ({'registers': [{'name': 'A', 'offset': 0, 'width': 64}]}, 'use pairs'),
    ({'registers': []}, 'no registers'),
])
def test_invalid_contracts(bad, msg):
    with pytest.raises(regmap.ContractError, match=msg):
        regmap.load_contract(bad)


def test_access_rules_and_pairs():
    c = regmap.load_contract(str(EXAMPLES / 'hls_vadd.contract.json'))
    mm = FakeMMIO()
    r = regmap.RegisterMap(mm, c)
    with pytest.raises(regmap.AccessError, match='read-modify-write'):
        r.write_field('CTRL', 'AP_START', 1)      # would consume clear-on-read AP_DONE
    with pytest.raises(regmap.AccessError, match='clear-on-read'):
        r.read_field('CTRL', 'AP_DONE')
    with pytest.raises(regmap.AccessError, match='write-only'):
        r.read('A_LO')
    mm.poke(0x14, 0xDEAD)                          # stale high word from a previous run
    r.write_pair('A', 0x1000_0040)
    assert (mm.peek(0x10), mm.peek(0x14)) == (0x1000_0040, 0)
    mm.poke(0x00, 0b0110)
    assert r.fields('CTRL') == {'AP_START': 0, 'AP_DONE': 1, 'AP_IDLE': 1, 'AP_READY': 0, 'AUTO_RESTART': 0}


def test_gpio_field_rmw_allowed_on_plain_rw():
    r = regmap.RegisterMap(FakeMMIO(), regmap.load_contract(str(EXAMPLES / 'axi_gpio.contract.json')))
    r.write('IP_IER', 0b10)
    r.write_field('IP_IER', 'CH1', 1)
    assert r.read('IP_IER') == 0b11


def test_cross_check_with_hwh():
    info = hwh.parse_hwh(str(FIXTURES / 'mini_zynqmp.hwh'))
    c = regmap.load_contract(str(EXAMPLES / 'hls_vadd.contract.json'))
    assert regmap.cross_check_hwh(c, info['ips']['vadd_0']['registers']) == []
    bad = regmap.load_contract({'registers': [{'name': 'CTRL', 'offset': 0, 'fields': [
        {'name': 'AP_DONE', 'lsb': 2, 'width': 1}]}, {'name': 'X', 'offset': 0x40}]})
    problems = regmap.cross_check_hwh(bad, info['ips']['vadd_0']['registers'])
    assert any('AP_DONE' in p for p in problems) and any('0x40' in p for p in problems)
    assert 'custom RTL' in regmap.cross_check_hwh(c, {})[0]


@pytest.mark.parametrize('name', ['axi_gpio', 'hls_vadd', 'axi_dma_simple'])
def test_generated_driver_and_skeleton_pass(tmp_path, name):
    # Exactly what SKILL.md tells a user to do: gen, then `python -m pytest <out>` - no PYTHONPATH,
    # run from an unrelated working directory.
    out_dir = tmp_path / 'out'
    out = subprocess.run([sys.executable, str(_CLI), 'gen', str(EXAMPLES / ('%s.contract.json' % name)),
                          '-o', str(out_dir)], capture_output=True, text=True)
    assert out.returncode == 0, out.stderr
    assert (out_dir / 'pynq_skill' / 'regmap.py').exists() and 'self-contained' in out.stdout
    res = subprocess.run([sys.executable, '-m', 'pytest', '-q', '-p', 'no:cacheprovider', str(out_dir)],
                         capture_output=True, text=True, env=_clean_env(), cwd=str(tmp_path))
    assert res.returncode == 0, res.stdout + res.stderr
    assert 'passed' in res.stdout


_CLI = SKILL / 'scripts' / 'pynq_skill_cli.py'


def _clean_env():
    env = dict(os.environ)
    env.pop('PYTHONPATH', None)
    return env


def test_gen_no_vendor_prints_working_pythonpath(tmp_path):
    out_dir = tmp_path / 'out'
    out = subprocess.run([sys.executable, str(_CLI), 'gen', str(EXAMPLES / 'axi_gpio.contract.json'), '-o', str(out_dir),
                          '--no-vendor'], capture_output=True, text=True)
    assert out.returncode == 0 and not (out_dir / 'pynq_skill').exists()
    bare = subprocess.run([sys.executable, '-m', 'pytest', '-q', '-p', 'no:cacheprovider', str(out_dir)],
                          capture_output=True, text=True, env=_clean_env(), cwd=str(tmp_path))
    assert bare.returncode != 0                      # without the printed PYTHONPATH it cannot import
    path = out.stdout.split('PYTHONPATH=')[1].split(' python')[0]
    res = subprocess.run([sys.executable, '-m', 'pytest', '-q', '-p', 'no:cacheprovider', str(out_dir)],
                         capture_output=True, text=True, env=dict(_clean_env(), PYTHONPATH=path), cwd=str(tmp_path))
    assert res.returncode == 0, res.stdout + res.stderr


class FakeKernel(FakeMMIO):
    """HLS control register where ap_done is clear-on-read; finishes `latency` reads after start."""

    def __init__(self, latency=3, stale_done=False, never=False):
        super().__init__()
        self.state, self.left, self.never = 'idle', latency, never
        self.done_pending = stale_done   # COR bit stays set until someone reads CTRL
        self.latency = latency

    def read(self, offset, length=4):
        if offset:
            return super().read(offset)
        if self.state == 'run':
            self.left -= 1
            if self.left <= 0 and not self.never:
                self.state, self.done_pending = 'idle', True
        value = (hls_ctrl.AP_IDLE if self.state == 'idle' else 0) | (hls_ctrl.AP_DONE if self.done_pending else 0)
        self.done_pending = False
        return value

    def write(self, offset, value):
        super().write(offset, value)
        if offset == 0 and value & 1:
            self.state, self.left = 'run', self.latency


def test_hls_run_once_handles_clear_on_read_and_stale_done():
    clk = ManualClock()
    k = FakeKernel(stale_done=True)
    res = hls_ctrl.run_once(k, clock=clk, sleep=clk.sleep)
    assert k.state == 'idle' and k.left <= 0, 'returned on the stale done before the kernel finished'
    writes = [e for e in k.log if e[0] == 'w']
    assert writes == [('w', 0, 1)]
    assert res['ctrl_trace'][0] & hls_ctrl.AP_DONE        # stale done seen BEFORE start, not counted
    assert res['ctrl_trace'][-1] & hls_ctrl.AP_DONE


def test_hls_run_once_times_out_without_hanging():
    clk = ManualClock()
    with pytest.raises(hls_ctrl.KernelTimeout, match='did not complete'):
        hls_ctrl.run_once(FakeKernel(never=True), timeout_s=0.01, clock=clk, sleep=clk.sleep)
