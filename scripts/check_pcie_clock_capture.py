"""Measure divided clock activity in an ILA CSV relative to nominal SYS_CLK.

This measures gross frequency, not jitter, ppm accuracy, PLL lock or PCIe health.
"""
import argparse
import csv
import hashlib
import json
from pathlib import Path
import statistics


def measure(values, bit, monitor_mhz=100.0, divisor=256):
    edges = [i for i in range(1, len(values))
             if not values[i-1] & (1 << bit) and values[i] & (1 << bit)]
    periods = [b-a for a, b in zip(edges, edges[1:])]
    result = dict(rising_edges=len(edges), full_periods=len(periods),
                  stable_periods_observed=False,
                  frequency_mhz_relative_to_nominal_sysclk=None)
    if len(periods) >= 3:
        mean = statistics.mean(periods)
        # A gross stability screen, not a jitter specification. Synchronization
        # quantizes edges; wildly varying periods do not define one clock rate.
        stable = max(periods)-min(periods) <= max(4, 0.02*mean)
        result.update(stable_periods_observed=stable,
                      stability_screen='period range <= max(4 monitor samples, 2% mean)',
                      period_monitor_samples_min=min(periods),
                      period_monitor_samples_max=max(periods),
                      period_monitor_samples_mean=mean,
                      mean_edge_rate_mhz_equivalent=divisor*monitor_mhz/mean,
                      frequency_mhz_relative_to_nominal_sysclk=divisor*monitor_mhz/mean if stable else None)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('csv', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--probe-column', required=True)
    parser.add_argument('--same-clock-calibration', action='store_true',
                        help='bit1 is monitor heartbeat bit7, not divided AXI')
    args = parser.parse_args()
    with args.csv.open(newline='', encoding='utf-8-sig') as handle:
        rows = list(csv.DictReader(handle))
    assert rows and rows[0]['Sample in Buffer'].startswith('Radix'), 'Missing radix row'
    radix = rows.pop(0)[args.probe_column].upper()
    base = {'HEX': 16, 'BIN': 2, 'UNSIGNED': 10}[radix]
    assert len(rows) == 4096, 'Incomplete ILA capture'
    assert [int(r['Sample in Buffer']) for r in rows] == list(range(4096))
    values = [int(r[args.probe_column], base) for r in rows]
    assert all(0 <= v < 4 for v in values), 'Expected exactly two clock bits'
    result = dict(csv_sha256=hashlib.sha256(args.csv.read_bytes()).hexdigest(),
                  samples=len(values), nominal_sysclk_mhz=100.0, source_divisor=256,
                  ref=measure(values, 0), axi=measure(values, 1),
                  scope='Two-stage synchronized counter bit 7; relative to nominal board SYS_CLK; not calibrated frequency, jitter, PLL lock or PCIe acceptance')
    if args.same_clock_calibration:
        calibration = result.pop('axi')
        calibration['scope'] = 'Same-clock heartbeat bit7, one diagnostic FF delay; checks capture sample spacing, not absolute SYS_CLK frequency'
        result['monitor_calibration'] = calibration
        result['calibration_pass'] = (calibration.get('full_periods',0)>=3
            and calibration.get('period_monitor_samples_min')==256
            and calibration.get('period_monitor_samples_max')==256)
    args.output.write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps(result))


if __name__ == '__main__':
    main()
