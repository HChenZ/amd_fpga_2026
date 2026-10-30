import json
import shutil

import pytest
from conftest import FIXTURES, REAL_RELEASE

from pynq_skill import artifacts, hwh, overlay_check
from pynq_skill.fakes import FakeMMIO, FakeOverlay


def _pair(tmp_path, bit=b'BIT', hwh_text=None):
    (tmp_path / 'd.bit').write_bytes(bit)
    (tmp_path / 'd.hwh').write_text(hwh_text or (FIXTURES / 'mini_zynqmp.hwh').read_text(), encoding='utf-8')
    return tmp_path / 'd.bit'


def test_artifacts_ok_and_manifest(tmp_path):
    bit = _pair(tmp_path)
    m = artifacts.write_manifest([bit, tmp_path / 'd.hwh'], tmp_path / 'm.json', source='unit')
    res = artifacts.check_artifacts(bit, manifest=tmp_path / 'm.json')
    assert set(res['sha256']) == {'d.bit', 'd.hwh'}
    assert m['artifacts']['d.bit']['bytes'] == 3


def test_artifacts_detect_stale_hwh(tmp_path):
    bit = _pair(tmp_path)
    artifacts.write_manifest([bit, tmp_path / 'd.hwh'], tmp_path / 'm.json')
    (tmp_path / 'd.hwh').write_text('<EDKSYSTEM/>', encoding='utf-8')   # rebuilt hwh not matching bit
    with pytest.raises(artifacts.ArtifactError, match='d.hwh sha256'):
        artifacts.check_artifacts(bit, manifest=tmp_path / 'm.json')


def test_artifacts_reject_non_sibling_hwh(tmp_path):
    bit = _pair(tmp_path)
    shutil.copy(tmp_path / 'd.hwh', tmp_path / 'other.hwh')
    with pytest.raises(artifacts.ArtifactError, match='not the sibling'):
        artifacts.check_artifacts(bit, hwh_path=tmp_path / 'other.hwh')


def test_artifacts_missing(tmp_path):
    (tmp_path / 'x.bit').write_bytes(b'1')
    with pytest.raises(artifacts.ArtifactError, match='missing file'):
        artifacts.check_artifacts(tmp_path / 'x.bit')


def test_parse_synthetic_zynqmp_hwh():
    info = hwh.parse_hwh(str(FIXTURES / 'mini_zynqmp.hwh'))
    assert info['ps'] == 'zynq_ultra_ps_e_0'
    assert info['clocks']['fclk0_mhz'] == pytest.approx(99.999001)
    vadd = info['ips']['vadd_0']
    assert (vadd['phys_addr'], vadd['addr_range']) == (0xA0000000, 0x10000)
    assert vadd['registers']['CTRL']['fields']['AP_DONE'] == {'lsb': 1, 'width': 1, 'access': None}
    assert 'dma_hier/axi_dma_0' in info['ips']          # hierarchical key like PYNQ ip_dict


@pytest.mark.skipif(not (REAL_RELEASE / 'pynq.hwh').exists(), reason='real release not available')
def test_real_xc7z020_release():
    res = artifacts.check_artifacts(REAL_RELEASE / 'pynq.bit', manifest=REAL_RELEASE / 'manifest.json')
    info = hwh.parse_hwh(res['hwh'])
    assert info['ps'] == 'ps7'
    assert info['clocks']['fclk0_mhz'] == 100
    assert info['ps_ref_clk_mhz'] == pytest.approx(33.333333)
    assert info['ips']['pynq_ctl_0']['phys_addr'] == 0x40000000
    assert info['ips']['pynq_mbox_0']['phys_addr'] == 0x40001000
    assert info['ips']['pynq_ctl_0']['registers'] == {}  # module_ref: no register_map metadata


def _ol(info, **override):
    ip_dict = {k: {'phys_addr': v['phys_addr'], 'addr_range': v['addr_range'], 'type': v['vlnv'],
                   'parameters': v['parameters']} for k, v in info['ips'].items()}
    for k, v in override.items():
        ip_dict[k].update(v)
    return FakeOverlay(ip_dict)


class Clocks:
    fclk0_mhz = 100.0


def test_verify_overlay_ok_and_identity():
    info = hwh.parse_hwh(str(FIXTURES / 'mini_zynqmp.hwh'))
    mm = FakeMMIO()
    mm.poke(0x10, 0x12345678)
    rep = overlay_check.verify_overlay(_ol(info), info, required={'vadd_0': 'xilinx.com:hls:vadd:1.0'},
                                       identity=[('vadd_0', 0x10, 0x12345678)], clocks=Clocks(),
                                       mmio_factory=lambda a, r: mm)
    assert rep['identity'][0]['value'] == 0x12345678


def test_verify_overlay_reports_all_problems():
    info = hwh.parse_hwh(str(FIXTURES / 'mini_zynqmp.hwh'))
    ol = _ol(info, vadd_0={'phys_addr': 0x43C00000})
    class Slow:
        fclk0_mhz = 66.67   # e.g. wrong PS reference-clock assumption
    with pytest.raises(overlay_check.OverlayCheckError) as e:
        overlay_check.verify_overlay(ol, info, required=['vadd_0', 'axi_dma_0'],
                                     identity=[('vadd_0', 0x10, 1)], clocks=Slow(),
                                     mmio_factory=lambda a, r: FakeMMIO())
    text = str(e.value)
    assert 'stale or foreign hwh' in text
    assert "did you mean ['dma_hier/axi_dma_0']" in text
    assert 'identity' in text and 'fclk0_mhz' in text


def test_unloaded_overlay_rejected():
    with pytest.raises(overlay_check.OverlayCheckError, match='not loaded'):
        overlay_check.verify_overlay(FakeOverlay({}, loaded=False))


def test_load_overlay_order(tmp_path):
    bit = _pair(tmp_path)
    artifacts.write_manifest([bit, tmp_path / 'd.hwh'], tmp_path / 'm.json')
    info = hwh.parse_hwh(str(tmp_path / 'd.hwh'))
    created = []

    def overlay_cls(path, download=True):
        created.append(path)
        return _ol(info)
    ol, _, rep = overlay_check.load_overlay(bit, manifest=tmp_path / 'm.json', overlay_cls=overlay_cls,
                                            required=['vadd_0'])
    assert created and rep['artifacts']['sha256']
    data = json.loads((tmp_path / 'm.json').read_text())
    data['artifacts']['d.bit']['sha256'] = '0' * 64
    (tmp_path / 'm.json').write_text(json.dumps(data))
    created.clear()
    with pytest.raises(artifacts.ArtifactError):
        overlay_check.load_overlay(bit, manifest=tmp_path / 'm.json', overlay_cls=overlay_cls)
    assert not created   # never downloads a bitstream that failed the hash gate
