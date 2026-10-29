"""Generate deterministic time-domain records, FFT references and FX spectra."""

import argparse
import json
import random
from pathlib import Path

import numpy as np

from fft512_reference import FFT512Reference, N, requantize


def tone(bin_index, amplitude=16000, phase=0):
    return [(round(amplitude * np.cos(2*np.pi*bin_index*n/N + phase)),
             round(amplitude * np.sin(2*np.pi*bin_index*n/N + phase))) for n in range(N)]


def paired(a, b):
    return [(ai, aq, bi, bq) for (ai, aq), (bi, bq) in zip(a, b)]


def make_windows(seed):
    rng = random.Random(seed)
    windows = []
    def add(name, frames, mutation=0):
        windows.append((name, frames, mutation))
    add("zero", [[(0, 0, 0, 0)] * N])
    impulse_a, impulse_b = [(0, 0)]*N, [(0, 0)]*N
    impulse_a[0], impulse_b[0] = (16384, 0), (8192, 8192)
    add("impulse_all_bins", [paired(impulse_a, impulse_b)])
    add("DC_B_leads_90", [[(8192, 0, 0, 4096)]*N]*2, 0)
    positive = [(16384, 0), (0, 16384), (-16384, 0), (0, -16384)]*128
    add("positive_bin128", [paired(positive, [(-q, i) for i, q in positive])]*3, 1)
    negative = [(i, -q) for i, q in positive]
    add("negative_bin384", [paired(negative, negative)]*2, 0xFFFFFFFF)
    add("all_minimum_DC", [[(-32768, -32768, -32768, -32768)]*N])
    alternating = [(32767 if n % 2 else -32768, -32768, 32767, -32768 if n % 2 else 32767)
                   for n in range(N)]
    add("extremes_DC_Nyquist", [alternating]*2, 0)
    multi = []
    for frame in range(4):
        a1, a2 = tone(17, 9000 + frame*1000), tone(-41, 4500)
        a = [(i1+i2, q1+q2) for (i1, q1), (i2, q2) in zip(a1, a2)]
        multi.append(paired(a, [(-q, i) for i, q in a]))
    add("multitone_varying_frames", multi, 2)
    random_frames = [[tuple(rng.randint(-32768, 32767) for _ in range(4)) for _ in range(N)] for _ in range(5)]
    add("random_five_frames", random_frames, 0)
    add("random_swapped", [[(bi, bq, ai, aq) for ai, aq, bi, bq in frame] for frame in random_frames], 1)
    add("half_bin_leakage", [paired(tone(25.5, 20000, 0.37), tone(25.5, 12000, -0.46))]*2, 7)
    add("one_antenna_zero", [paired(tone(7, 18000), [(0, 0)]*N)]*3, 0)
    return windows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--vivado-root", type=Path, required=True)
    parser.add_argument("--seed", type=lambda value: int(value, 0), default=0x46585F33)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    output = args.output_dir.resolve()
    if output == repo or repo in output.parents:
        parser.error("Vectors must be generated outside the repository")
    output.mkdir(parents=True, exist_ok=True)
    assert [requantize(v)[0] for v in [512, 1536, -512, -1536, 513, -513]] == [0, 2, 0, -2, 1, -1]
    reference = FFT512Reference(args.vivado_root, output)
    windows = make_windows(args.seed)
    manifest_cases = []
    results = []
    frame_total = 0
    try:
        with (output/"stimulus.txt").open("w", encoding="ascii", newline="\n") as stimulus, \
             (output/"expected_fft.txt").open("w", encoding="ascii", newline="\n") as fft_file, \
             (output/"expected_fx.txt").open("w", encoding="ascii", newline="\n") as fx_file:
            for window_id, (name, frames, mutation) in enumerate(windows):
                stimulus.write(f"{len(frames)} {mutation}\n")
                sums = [[0, 0, 0, 0] for _ in range(N)]
                for frame in frames:
                    stimulus.writelines(" ".join(map(str, sample))+"\n" for sample in frame)
                    a_raw, a = reference.transform([(ai, aq) for ai, aq, _, _ in frame])
                    b_raw, b = reference.transform([(bi, bq) for _, _, bi, bq in frame])
                    for k, ((ari, arq), (bri, brq), (ai, aq), (bi, bq)) in enumerate(zip(a_raw, b_raw, a, b)):
                        fft_file.write(f"{k} {ari} {arq} {bri} {brq} {ai} {aq} {bi} {bq}\n")
                        values = (ai*ai+aq*aq, bi*bi+bq*bq, ai*bi+aq*bq, aq*bi-ai*bq)
                        sums[k] = [old+value for old, value in zip(sums[k], values)]
                    frame_total += 1
                for k, (pa, pb, vr, vi) in enumerate(sums):
                    assert vr*vr + vi*vi <= pa*pb
                    fx_file.write(f"{window_id} {k} {len(frames)} {pa} {pb} {vr} {vi}\n")
                results.append(sums)
                peak = max(range(N), key=lambda k: sums[k][0])
                manifest_cases.append({"name": name, "window_id": window_id, "frames": len(frames),
                                       "peak_bin_a": peak, "peak_result": sums[peak], "mid_window_config": mutation})
        assert all(row == [256, 128, 128, -128] for row in results[1])
        assert results[2][0] == [33554432, 8388608, 0, -16777216]
        assert results[3][128] == [201326592, 201326592, 0, -201326592]
        assert results[4][384] == [134217728, 134217728, 134217728, 0]
        assert all(row == [0,0,0,0] for k,row in enumerate(results[3]) if k != 128)
        assert all(row == [0,0,0,0] for k,row in enumerate(results[4]) if k != 384)
        assert all(swapped == [pb,pa,vr,-vi] for (pa,pb,vr,vi),swapped in zip(results[8],results[9]))
        manifest = {"seed":args.seed, "fft_length":N, "windows":len(windows), "frames":frame_total,
                    "input_pairs":frame_total*N, "fft_pairs":frame_total*N, "output_bins":len(windows)*N,
                    "fft_direction":"forward, exp(-j*2*pi*k*n/512)", "ordering":"natural 0..511",
                    "voltage_divisor":1024, "visibility_divisor":1024**2,
                    "numpy_max_raw_component_error":reference.max_raw_error,
                    "numpy_max_quantized_component_error":reference.max_quantized_error,
                    "numpy_raw_error_bound":128, "numpy_quantized_error_bound":1,
                    "exact_check":"AMD C model raw FFT + Python integer ties-even requantization and per-bin FX",
                    "cmodel":reference.provenance, "cases":manifest_cases}
        (output/"vectors.json").write_text(json.dumps(manifest,indent=2)+"\n",encoding="utf-8")
        print(json.dumps({k:v for k,v in manifest.items() if k not in ("cmodel","cases")}))
    finally:
        reference.close()


if __name__ == "__main__":
    main()
