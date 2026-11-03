#!/usr/bin/env python3
"""Summarize results.csv: per task x arm scores, per-scenario pass rates, exact permutation test
(with vs without, placebo vs without, with vs placebo) and Cliff's delta. Standard library only."""
import argparse
import csv
import itertools
import random
import statistics
from collections import defaultdict


def perm_test(x, y, max_exact=200000, n_mc=20000, seed=1):
    """Two-sided permutation test on difference of means. Returns p-value."""
    obs = abs(statistics.mean(x) - statistics.mean(y))
    pool, n = x + y, len(x)
    total = 1
    for i in range(n):
        total = total * (len(pool) - i) // (i + 1)
    count = hits = 0
    if total <= max_exact:
        for idx in itertools.combinations(range(len(pool)), n):
            s = set(idx)
            a = [pool[i] for i in s]
            b = [pool[i] for i in range(len(pool)) if i not in s]
            count += 1
            hits += abs(statistics.mean(a) - statistics.mean(b)) >= obs - 1e-12
    else:
        rnd = random.Random(seed)
        for _ in range(n_mc):
            rnd.shuffle(pool)
            count += 1
            hits += abs(statistics.mean(pool[:n]) - statistics.mean(pool[n:])) >= obs - 1e-12
    return hits / count


def cliffs_delta(x, y):
    gt = sum(1 for a in x for b in y if a > b)
    lt = sum(1 for a in x for b in y if a < b)
    return (gt - lt) / (len(x) * len(y))


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('results')
    a = p.parse_args(argv)
    trials = defaultdict(list)
    meta = {}
    scen = defaultdict(lambda: [0, 0])
    with open(a.results, encoding='utf-8') as f:
        for r in csv.DictReader(f):
            key = (r['task'], r['arm'], r['rep'])
            trials[key].append(r['outcome'] == 'pass')
            meta[key] = r
            s = scen[(r['task'], r['scenario'], r['arm'])]
            s[0] += r['outcome'] == 'pass'
            s[1] += 1
    score = defaultdict(dict)
    for (task, arm, rep), oks in trials.items():
        score[task].setdefault(arm, []).append(sum(oks) / len(oks))
    for task in sorted(score):
        print('\n== %s' % task)
        for arm, xs in sorted(score[task].items()):
            loads = sum(1 for (t, ar, rp), m in meta.items() if t == task and ar == arm and m['canary'])
            full = sum(1 for x in xs if x == 1.0)
            print('  %-8s n=%d  mean=%.3f  median=%.3f  full_pass=%d/%d  skill_canary=%d/%d' % (
                arm, len(xs), statistics.mean(xs), statistics.median(xs), full, len(xs), loads, len(xs)))
        for x_arm, y_arm in (('with', 'without'), ('placebo', 'without'), ('with', 'placebo')):
            if x_arm in score[task] and y_arm in score[task]:
                x, y = score[task][x_arm], score[task][y_arm]
                print('  %s vs %s: diff=%+.3f  permutation p=%.4f  cliffs_delta=%+.2f' % (
                    x_arm, y_arm, statistics.mean(x) - statistics.mean(y), perm_test(x, y), cliffs_delta(x, y)))
        print('  per-scenario pass rate:')
        names = sorted({sc for (t, sc, _) in scen if t == task})
        arms = sorted(score[task])
        print('    %-28s ' % 'scenario' + ' '.join('%9s' % ar for ar in arms))
        for sc in names:
            print('    %-28s ' % sc + ' '.join('%4d/%-4d' % tuple(scen[(task, sc, ar)]) for ar in arms))


if __name__ == '__main__':
    main()
