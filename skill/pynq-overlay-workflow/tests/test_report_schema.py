import json
import subprocess
import sys

import pytest
from conftest import EXAMPLES, REAL_L3_DMA, REAL_LOOPBACK_REPORTS, SKILL

from pynq_skill import report

UTIL_RPT = """| Design       : demo_wrapper
| Device       : xc7z020clg400-1
| Design State : Routed
+-------------------------+------+-------+------------+-----------+-------+
|        Site Type        | Used | Fixed | Prohibited | Available | Util% |
+-------------------------+------+-------+------------+-----------+-------+
| Slice LUTs              |  120 |     0 |          0 |     53200 |  0.23 |
| Slice Registers         |  300 |     0 |          0 |    106400 |  0.28 |
|   Register as Latch     |    0 |     0 |          0 |    106400 |  0.00 |
+-------------------------+------+-------+------------+-----------+-------+
"""

SCHEMA = {
    'title': 'demo',
    'sources': {'util': {'kind': 'utilization', 'evidence': 'tool_report'},
                'run': {'kind': 'json', 'evidence': 'measured'}},
    'metrics': [
        {'name': 'LUT', 'unit': 'cells', 'source': 'util', 'path': 'all.Slice LUTs.used', 'required': True},
        {'name': 'cases', 'source': 'run', 'path': 'cases.*.ok', 'agg': 'count', 'required': True},
        {'name': 'all ok', 'source': 'run', 'path': 'cases.*.ok', 'agg': 'all_true'},
        {'name': 'mean us', 'unit': 'us', 'source': 'run', 'path': 'cases.*.us', 'agg': 'mean'},
        {'name': 'first case', 'source': 'run', 'path': 'cases.0.name'},
        {'name': 'power', 'unit': 'W', 'source': 'run', 'path': 'power_w'},
        {'name': 'peak', 'unit': 'MB/s', 'value': 400, 'evidence': 'estimated', 'basis': '100 MHz x 4 B'},
    ]}


def _files(tmp_path, run=None):
    (tmp_path / 'u.rpt').write_text(UTIL_RPT, encoding='utf-8')
    (tmp_path / 'r.json').write_text(json.dumps(run or {'cases': [
        {'name': 'a', 'ok': True, 'us': 10}, {'name': 'b', 'ok': True, 'us': 30}]}), encoding='utf-8')
    return {'util': str(tmp_path / 'u.rpt'), 'run': str(tmp_path / 'r.json')}


def test_collect_values_aggregates_and_missing(tmp_path):
    recs, problems = report.collect_metrics(SCHEMA, _files(tmp_path))
    by = {r['name']: r for r in recs}
    assert by['LUT']['value'] == 120 and by['LUT']['evidence'] == 'tool_report'
    assert (by['cases']['value'], by['all ok']['value'], by['mean us']['value']) == (2, True, 20)
    assert by['first case']['value'] == 'a' and by['cases']['evidence'] == 'measured'
    assert by['power']['status'] == 'missing' and by['power']['evidence'] == 'not_measured'
    assert by['power']['value'] is None and 'not found' in by['power']['note']
    assert by['peak']['evidence'] == 'estimated' and by['peak']['basis']
    assert problems == []                       # power is optional
    assert by['LUT']['source_sha256'] and by['cases']['source_file'].endswith('r.json')


def test_all_true_is_false_when_any_case_fails(tmp_path):
    recs, _ = report.collect_metrics(SCHEMA, _files(tmp_path, {'cases': [{'ok': True}, {'ok': False}]}))
    assert {r['name']: r['value'] for r in recs}['all ok'] is False


def test_missing_source_makes_metrics_not_measured_and_required_fails(tmp_path):
    files = _files(tmp_path)
    del files['run']
    recs, problems = report.collect_metrics(SCHEMA, files)
    by = {r['name']: r for r in recs}
    assert by['cases']['evidence'] == 'not_measured' and 'not provided' in by['cases']['note']
    assert any("'cases'" in p for p in problems)
    assert by['LUT']['status'] == 'ok'          # other sources unaffected


@pytest.mark.parametrize('bad,msg', [
    ({'sources': {}, 'metrics': []}, 'no metrics'),
    ({'sources': {'s': {'kind': 'csv', 'evidence': 'measured'}}, 'metrics': [{'name': 'x', 'source': 's', 'path': 'a'}]}, 'kind'),
    ({'sources': {'s': {'kind': 'json', 'evidence': 'not_measured'}}, 'metrics': [{'name': 'x', 'source': 's', 'path': 'a'}]}, 'evidence'),
    ({'sources': {}, 'metrics': [{'name': 'x', 'source': 'nope', 'path': 'a'}]}, 'unknown source'),
    ({'sources': {'s': {'kind': 'json', 'evidence': 'measured'}}, 'metrics': [{'name': 'x', 'source': 's', 'path': 'a.*'}]}, 'needs an "agg"'),
    ({'sources': {'s': {'kind': 'json', 'evidence': 'measured'}}, 'metrics': [{'name': 'x', 'source': 's', 'path': 'a.*', 'agg': 'median'}]}, 'agg'),
    ({'sources': {}, 'metrics': [{'name': 'x', 'value': 1, 'evidence': 'estimated'}]}, 'basis'),
    ({'sources': {}, 'metrics': [{'name': 'x', 'value': 1}]}, 'explicit evidence'),
    ({'sources': {}, 'metrics': [{'name': 'x', 'value': 1, 'evidence': 'measured'}, {'name': 'x', 'value': 2, 'evidence': 'measured'}]}, 'duplicate'),
])
def test_invalid_schemas(bad, msg):
    with pytest.raises(report.SchemaError, match=msg):
        report.load_schema(bad)


def test_report_renders_metrics_and_problems(tmp_path):
    files = _files(tmp_path)
    del files['run']
    recs, problems = report.collect_metrics(SCHEMA, files)
    data, md = report.build_report(title='t', metrics=recs, problems=problems)
    assert '## Metrics (7 configured, 5 not_measured)' in md
    assert '| peak | 400 | MB/s | estimated | constant | basis: 100 MHz x 4 B |' in md
    assert '## Problems' in md and data['problems'] == problems


def _cli(*args):
    return subprocess.run([sys.executable, str(SKILL / 'scripts' / 'pynq_skill_cli.py'), 'report', *args],
                          capture_output=True, text=True)


def test_cli_exit_codes(tmp_path):
    files = _files(tmp_path)
    (tmp_path / 's.json').write_text(json.dumps(SCHEMA), encoding='utf-8')
    ok = _cli('--schema', str(tmp_path / 's.json'), '--source', 'util=' + files['util'],
              '--source', 'run=' + files['run'], '-o', str(tmp_path / 'ok.md'))
    assert ok.returncode == 0, ok.stderr
    assert json.loads((tmp_path / 'ok.json').read_text(encoding='utf-8'))['metrics'][0]['value'] == 120
    bad = _cli('--schema', str(tmp_path / 's.json'), '--source', 'util=' + files['util'], '-o', str(tmp_path / 'bad.md'))
    assert bad.returncode == 1 and 'required metric' in bad.stderr
    typo = _cli('--schema', str(tmp_path / 's.json'), '--source', 'utl=' + files['util'], '-o', str(tmp_path / 't.md'))
    assert typo.returncode == 1 and 'not declared' in typo.stderr


def test_example_schema_is_valid():
    report.load_schema(str(EXAMPLES / 'report_schema.dma_loopback.json'))


@pytest.mark.skipif(not (REAL_LOOPBACK_REPORTS / 'utilization.rpt').exists() or not REAL_L3_DMA.exists(),
                    reason='non-Ascon DMA loopback reports / L3 board result not available')
def test_real_non_ascon_dma_loopback_report(tmp_path):
    out = _cli('--schema', str(EXAMPLES / 'report_schema.dma_loopback.json'),
               '--source', 'util=%s' % (REAL_LOOPBACK_REPORTS / 'utilization.rpt'),
               '--source', 'timing=%s' % (REAL_LOOPBACK_REPORTS / 'timing_summary.rpt'),
               '--source', 'board=%s' % REAL_L3_DMA, '-o', str(tmp_path / 'dma.md'))
    assert out.returncode == 0, out.stderr
    data = json.loads((tmp_path / 'dma.json').read_text(encoding='utf-8'))
    by = {m['name']: m for m in data['metrics']}
    assert by['LUT']['value'] == 2436 and by['FF']['value'] == 3333 and by['latches']['value'] == 0
    assert by['WNS']['value'] == pytest.approx(1.736) and by['timing met']['value'] is True
    assert by['LUT']['evidence'] == 'tool_report'
    assert by['board transfers']['value'] == 6 and by['all comparisons passed']['value'] is True
    assert by['board transfers']['evidence'] == 'measured'
    assert by['bytes received (total)']['value'] == 8 + 9 + 16 + 64 + 256 + 16
    assert by['loopback throughput']['evidence'] == 'not_measured'      # not collected on the board
    assert by['stream peak (theoretical)']['evidence'] == 'estimated'
