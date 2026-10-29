"""Plot integer references only after their RTL verification has succeeded."""

import argparse
import hashlib
import json
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-dir", type=Path, required=True)
    args = parser.parse_args()
    build = args.build_dir.resolve()
    repo = Path(__file__).resolve().parents[1]
    if build == repo or repo in build.parents:
        parser.error("Plot output must stay outside the repository")
    proof = json.loads((build/"verification.json").read_text(encoding="utf-8-sig"))
    if not proof["simulation"].startswith("PASS "):
        raise ValueError("Missing successful RTL verification")
    for name, expected in proof["sources"].items():
        if hashlib.sha256((repo/name).read_bytes()).hexdigest() != expected:
            raise ValueError(f"Source changed since verification: {name}")
    data = np.loadtxt(build/"expected_fx.txt", dtype=np.int64)
    k = np.arange(512)
    fig, axes = plt.subplots(2,2,figsize=(11,6.7),layout="constrained")
    for ax, window, label, color in (
        (axes[0,0],3,"Positive-frequency tone: k = 128","#2366ad"),
        (axes[0,1],4,"Negative-frequency tone: k = 384","#24805d")):
        rows = data[data[:,0]==window]
        power = rows[:,3].astype(float) / rows[:,2]
        ax.plot(k,power/np.max(power),color=color,lw=1.4)
        ax.set(xlim=(0,511),ylim=(-0.04,1.12),xlabel="Natural output bin k",
               ylabel="Auto A / peak",title=label)
        ax.grid(alpha=.2)
    rows = data[data[:,0]==7]
    signed_k = np.fft.fftshift(np.fft.fftfreq(512)*512)
    power = rows[:,3].astype(float)
    level = 10*np.log10(np.maximum(np.fft.fftshift(power)/power.max(),1e-10))
    axes[1,0].plot(signed_k,level,color="#2366ad",lw=1.3)
    axes[1,0].set(xlim=(-80,60),ylim=(-100,5),xlabel="Signed frequency bin",ylabel="Auto A (dB / peak)",
                  title="Two tones, integrated across four varying frames")
    phase = np.angle(rows[:,5]+1j*rows[:,6],deg=True)
    significant = power > power.max()*1e-4
    signed_unshifted = np.fft.fftfreq(512)*512
    axes[1,1].axhline(-90,color="#999999",lw=1,ls="--")
    axes[1,1].scatter(signed_unshifted[significant],phase[significant],color="#ba4c42",s=50,zorder=3)
    axes[1,1].set(xlim=(-80,60),ylim=(-180,0),yticks=[-180,-135,-90,-45,0],
                  xlabel="Signed frequency bin",ylabel="Cross phase (degrees)",
                  title="B = j A: phase of A conj(B) is -90 degrees")
    for ax in axes[1,:]: ax.grid(alpha=.2)
    fig.suptitle("512-point FFT-FX: integer reference matched exactly by RTL",fontsize=14)
    target=build/"lesson03_spectra.png"
    fig.savefig(target,dpi=160)
    plt.close(fig)
    print(target)


if __name__ == "__main__":
    main()
