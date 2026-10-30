"""Stage E: golden comparison with diagnostic hints, mutation self-check and timing stats."""
import statistics
import time

from . import PynqSkillError


class GoldenMismatch(PynqSkillError):
    def __init__(self, result):
        self.result = result
        super().__init__('golden mismatch (%s): %s' % (result['name'], result['summary']))


def _b(x):
    return bytes(x) if not isinstance(x, bytes) else x


def compare(actual, expected, *, name='case', previous=None, sentinel=None):
    """Byte-wise comparison returning a result dict with a diagnostic `hint`."""
    a, e = _b(actual), _b(expected)
    n = min(len(a), len(e))
    diffs = [i for i in range(n) if a[i] != e[i]]
    ok = not diffs and len(a) == len(e)
    res = {'name': name, 'ok': ok, 'actual_len': len(a), 'expected_len': len(e),
           'mismatches': len(diffs) + abs(len(a) - len(e)), 'first_mismatch': diffs[0] if diffs else None,
           'hint': None}
    if ok:
        res['summary'] = 'match (%d bytes)' % len(e)
        return res
    res['hint'] = _hint(a, e, diffs, previous, sentinel)
    first = diffs[0] if diffs else n
    res['summary'] = '%d differing bytes, first at %d (actual %s expected %s), hint=%s' % (
        res['mismatches'], first, a[first:first + 8].hex(), e[first:first + 8].hex(), res['hint'])
    return res


def _hint(a, e, diffs, previous, sentinel):
    if len(a) != len(e) and a == e[:len(a)]:
        return 'length_mismatch'
    if sentinel is not None and a and all(x == sentinel for x in a):
        return 'all_sentinel'
    if a and not any(a):
        return 'all_zero'
    if previous is not None and a == _b(previous):
        return 'equals_previous'
    if len(a) == len(e) and len(a) % 4 == 0 and len(a) >= 4:
        if all(a[i:i + 4] == e[i:i + 4][::-1] for i in range(0, len(a), 4)):
            return 'byte_swapped_words'
    for k in range(1, min(16, len(e))):
        if len(a) - k >= 8 and (a[k:] == e[:len(a) - k] or a[:len(a) - k] == e[k:]):
            return 'shifted_by_%d' % k
    if diffs and diffs[0] >= len(e) * 3 // 4:
        return 'tail_only'
    if len(a) != len(e):
        return 'length_mismatch'
    return 'scattered'


def check(actual, expected, **kw):
    res = compare(actual, expected, **kw)
    if not res['ok']:
        raise GoldenMismatch(res)
    return res


def mutation_must_fail(checker, *args):
    """Prove the checker is sensitive: checker(*args) on deliberately wrong data must fail."""
    try:
        checker(*args)
    except (GoldenMismatch, AssertionError):
        return True
    raise PynqSkillError('mutation was NOT detected: the comparison is too weak to trust')


def boundary_lengths(max_len, align=4):
    vals = {0, 1, align - 1, align, align + 1, max_len - 1, max_len}
    return sorted(v for v in vals if 0 <= v <= max_len)


def measure(fn, *, warmup=3, repeat=20, clock=time.perf_counter_ns, label='', evidence='measured'):
    """Return cold (first call) and warm statistics in microseconds."""
    t0 = clock()
    fn()
    cold = (clock() - t0) / 1000.0
    for _ in range(max(0, warmup - 1)):
        fn()
    samples = []
    for _ in range(repeat):
        t0 = clock()
        fn()
        samples.append((clock() - t0) / 1000.0)
    samples.sort()
    p95 = samples[min(len(samples) - 1, int(round(0.95 * (len(samples) - 1))))]
    return {'label': label, 'evidence': evidence, 'unit': 'us', 'cold': cold, 'n': repeat,
            'min': samples[0], 'median': statistics.median(samples), 'p95': p95, 'max': samples[-1],
            'warmup': warmup}
