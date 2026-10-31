import os
import pathlib
import sys

SKILL = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SKILL / 'scripts'))

FIXTURES = SKILL / 'tests' / 'fixtures'
EXAMPLES = SKILL / 'examples'
# Optional real artifacts (this repository's PYNQ-Z2 release). Override with PYNQ_SKILL_REAL_RELEASE.
REAL_RELEASE = pathlib.Path(os.environ.get(
    'PYNQ_SKILL_REAL_RELEASE', SKILL.parents[1] / 'board' / 'vivado_zynq7000_xc7z020_pynq' / 'release'))
# Non-Ascon AXI DMA loopback overlay reports and its L3 board result (S04 example data).
REAL_LOOPBACK_REPORTS = pathlib.Path(os.environ.get(
    'PYNQ_SKILL_LOOPBACK_REPORTS', SKILL.parents[1] / 'board' / 'vivado_zynq7000_xc7z020_axi_dma_loopback'
    / 'candidate' / 'reports'))
REAL_L3_DMA = pathlib.Path(os.environ.get(
    'PYNQ_SKILL_L3_DMA', SKILL.parents[1] / 'data' / 'skill' / 'l3_20261031_063709' / '30_non_ascon_dma.json'))
REAL_UTIL = pathlib.Path(os.environ.get(
    'PYNQ_SKILL_REAL_UTIL', SKILL.parents[1] / 'board' / 'vivado_zynq7000_xc7z020_pynq_puf' / 'candidate'
    / 'reports' / 'utilization.rpt'))
