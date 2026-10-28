"""Exact two-input correlation reference; write vectors outside the repository."""

import argparse
import json
import random
from pathlib import Path


def correlate(samples):
    """Return Paa, Pbb, Re(Vab), Im(Vab), count using unbounded integers."""
    power_a = power_b = real = imag = count = 0
    for ai, aq, bi, bq in samples:
        if not all(-32768 <= value <= 32767 for value in (ai, aq, bi, bq)):
            raise ValueError("I/Q component outside signed 16-bit range")
        power_a += ai**2 + aq**2
        power_b += bi**2 + bq**2
        real += ai * bi + aq * bq
        imag += aq * bi - ai * bq
        count += 1
    return power_a, power_b, real, imag, count


def make_windows(seed):
    rng = random.Random(seed)
    cases = []

    def add(label, samples, mutation=0):
        cases.append((label, samples, mutation))

    add("zero", [(0, 0, 0, 0)])
    add("hand_worked", [(3, 4, 1, 2)] * 4)
    # B leads A by +90 degrees. A*conj(B) therefore has NEGATIVE imaginary part.
    tone = [(12000, 0), (0, 12000), (-12000, 0), (0, -12000)] * 128
    add("B_leads_90_deg", [(ai, aq, -aq, ai) for ai, aq in tone], 1)
    add("A_leads_90_deg", [(-aq, ai, ai, aq) for ai, aq in tone], 7)
    add("identical_inputs", [(ai, aq, ai, aq) for ai, aq in tone], 0xFFFFFFFF)
    add("opposite_inputs", [(ai, aq, -ai, -aq) for ai, aq in tone])
    add("cancellation", [(1, 0, 1, 0), (1, 0, -1, 0)])
    add("one_input_zero", [(32767, -32768, 0, 0)] * 17)
    add("maximum_positive_real", [(-32768, -32768, -32768, -32768)] * 4096)
    add("large_negative_real", [(-32768, -32768, 32767, 32767)] * 257, 1)
    add("large_positive_imag", [(-32768, 32767, 32767, 32767)] * 257)
    add("large_negative_imag", [(32767, 32767, -32768, 32767)] * 257)
    extremes = [-32768, -32767, -1, 0, 1, 32766, 32767]
    add("all_extreme_combinations", [(ai, aq, bi, bq) for ai in extremes
                                    for aq in extremes for bi in extremes for bq in extremes])
    for index in range(120):
        samples = [tuple(rng.randint(-32768, 32767) for _ in range(4))
                   for _ in range(rng.randint(1, 65))]
        mutation = [0, 1, 0xFFFFFFFF, rng.randint(2, 100)][index % 4]
        add(f"random_{index}", samples, mutation)
        # An explicitly swapped second window checks the Hermitian convention
        # against the same underlying data, including both autos.
        add(f"random_{index}_swapped", [(bi, bq, ai, aq) for ai, aq, bi, bq in samples], mutation)
    return cases


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--seed", type=lambda value: int(value, 0), default=0x46585F32)
    args = parser.parse_args()
    repo_dir = Path(__file__).resolve().parents[1]
    output_dir = args.output_dir.resolve()
    if output_dir == repo_dir or repo_dir in output_dir.parents:
        parser.error("Generated vectors must be outside the source repository")
    output_dir.mkdir(parents=True, exist_ok=True)

    assert correlate([(3, 4, 1, 2)] * 4) == (100, 20, 44, -8, 4)
    assert correlate([(1, 0, 0, 1)]) == (1, 1, 0, -1, 1)
    assert correlate([(-32768,) * 4]) == (2**31, 2**31, 2**31, 0, 1)
    maximum_m = 2**32 - 1
    conservative_sum_bound = maximum_m * 2**31
    assert conservative_sum_bound < 2**63

    cases = make_windows(args.seed)
    entries = []
    with (output_dir / "windows.txt").open("w", encoding="ascii", newline="\n") as stream:
        for label, samples, mutation in cases:
            pa, pb, real, imag, size = correlate(samples)
            swapped = correlate([(bi, bq, ai, aq) for ai, aq, bi, bq in samples])
            assert swapped == (pb, pa, real, -imag, size)
            # Exact Cauchy-Schwarz check on the unnormalized visibility matrix.
            assert real**2 + imag**2 <= pa * pb
            stream.write(f"{size} {pa} {pb} {real} {imag} {mutation}\n")
            stream.writelines(f"{ai} {aq} {bi} {bq}\n" for ai, aq, bi, bq in samples)
            entries.append({"label": label, "count": size, "auto_a": pa, "auto_b": pb,
                            "cross_real": real, "cross_imag": imag, "mid_window_config": mutation})
    manifest = {
        "seed": args.seed,
        "windows": len(cases),
        "sample_pairs": sum(entry["count"] for entry in entries),
        "reference": "Python arbitrary-precision integer correlation; Vab=sum(A*conj(B))",
        "maximum_legal_window": maximum_m,
        "conservative_absolute_sum_bound": conservative_sum_bound,
        "scope": "one aligned antenna pair and one frequency; synthetic voltages, no FFT or RFSoC capture",
        "cases": entries,
    }
    (output_dir / "vectors.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps({key: value for key, value in manifest.items() if key != "cases"}))


if __name__ == "__main__":
    main()
