"""Generate independent integer reference windows; write only to a build directory."""

import argparse
import json
import random
from pathlib import Path


def integrated_power(samples):
    """Exact unnormalized sum for signed 16-bit I/Q pairs, using Python integers."""
    total = 0
    count = 0
    for i_value, q_value in samples:
        if not (-32768 <= i_value <= 32767 and -32768 <= q_value <= 32767):
            raise ValueError("I/Q component outside signed 16-bit range")
        total += i_value**2 + q_value**2
        count += 1
    return total, count


def make_windows(seed):
    rng = random.Random(seed)
    cases = [
        ([(0, 0)], 0),
        ([(3, 4)], 0),
        ([(-3, -4), (3, -4), (-3, 4)], 0),
        ([(-32768, -32768)], 0),
        ([(32767, 32767), (-32768, 32767)], 1),
        ([(0, 0)] * 17, 0),
        ([(-32768, -32768)] * 4096, 0),
        ([(32767, -32768)] * 257, 7),
    ]
    # A quarter-cycle tone has exactly constant integer power. Different
    # phases/signs must produce the same power, without a floating FFT model.
    tone = [(30000, 0), (0, 30000), (-30000, 0), (0, -30000)]
    cases.append((tone * 128, 1))
    for index in range(160):
        size = rng.randint(1, 65)
        samples = [(rng.randint(-32768, 32767), rng.randint(-32768, 32767))
                   for _ in range(size)]
        # Mid-window config edits include zero, one, and a very large target.
        mutation = [0, 1, 0xFFFFFFFF, rng.randint(2, 100)][index % 4]
        cases.append((samples, mutation))
    return cases


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--seed", type=lambda value: int(value, 0), default=0x4B553550)
    args = parser.parse_args()
    repo_dir = Path(__file__).resolve().parents[1]
    output_dir = args.output_dir.resolve()
    if output_dir == repo_dir or repo_dir in output_dir.parents:
        parser.error("Generated vectors must be outside the source repository")
    output_dir.mkdir(parents=True, exist_ok=True)

    assert integrated_power([(3, 4)]) == (25, 1)
    assert integrated_power([(-32768, -32768)]) == (1 << 31, 1)
    # The legal maximum window also fits, without attempting a 2^32-cycle sim.
    maximum_sum = (2**32 - 1) * (2 * 32768**2)
    assert maximum_sum < 2**63

    cases = make_windows(args.seed)
    sample_count = 0
    with (output_dir / "windows.txt").open("w", encoding="ascii", newline="\n") as stream:
        for samples, mutation in cases:
            expected, size = integrated_power(samples)
            stream.write(f"{size} {expected} {mutation}\n")
            stream.writelines(f"{i_value} {q_value}\n" for i_value, q_value in samples)
            sample_count += size
    manifest = {
        "seed": args.seed,
        "windows": len(cases),
        "samples": sample_count,
        "reference": "Python arbitrary-precision sum of squared signed I/Q components",
        "maximum_legal_window": 2**32 - 1,
        "maximum_legal_sum": maximum_sum,
        "scope": "one logical stream; no antenna/bin interleaving or real RFSoC capture",
    }
    (output_dir / "vectors.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps(manifest))


if __name__ == "__main__":
    main()
