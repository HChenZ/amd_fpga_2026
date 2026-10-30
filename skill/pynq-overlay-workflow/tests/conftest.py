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
REAL_UTIL = pathlib.Path(os.environ.get(
    'PYNQ_SKILL_REAL_UTIL', SKILL.parents[1] / 'board' / 'vivado_zynq7000_xc7z020_pynq_puf' / 'candidate'
    / 'reports' / 'utilization.rpt'))
