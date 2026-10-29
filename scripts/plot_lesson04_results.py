"""Plot verified integer spectra/weights and explicitly separate model curves."""
import argparse
import hashlib
import json
from pathlib import Path
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from generate_lesson04_vectors import tone_frames


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-dir",type=Path,required=True)
    args=parser.parse_args(); build=args.build_dir.resolve(); repo=Path(__file__).resolve().parents[1]
    proof=json.loads((build/"verification.json").read_text(encoding="utf-8"))
    assert proof["simulation"].startswith("PASS ")
    for directory,hashes in ((repo,proof["sources"]),(build,proof["data"])):
        for name,expected in hashes.items():
            assert hashlib.sha256((directory/name).read_bytes()).hexdigest()==expected,name
    vectors=json.loads((build/"vectors.json").read_text(encoding="utf-8"))
    response=np.load(build/"response.npz")
    rows=[list(map(int,line.split())) for line in (build/"expected_fx.txt").read_text().splitlines()]
    spectrum=np.array([r[9]/r[6] for r in rows if r[0]==0 and r[1]==1])
    frame_data=np.asarray(tone_frames(8,25.25))[-4:]
    rect=np.mean(abs(np.fft.fft(frame_data[:,:,0]+1j*frame_data[:,:,1],axis=1))**2,axis=0)
    gaps=vectors["scenarios"][1]
    masks=np.array(gaps["effective_masks"])
    weights=np.array([w["weights"] for w in gaps["windows"]])
    fig,axes=plt.subplots(2,2,figsize=(13,8),layout="constrained")
    ax=axes[0,0]
    for key,label in (("rect","Rectangular FFT"),("pfb","4-tap Hann-sinc PFB")):
        ax.plot(response["offset"],20*np.log10(np.maximum(abs(response[key]),1e-6)),label=label)
    ax.set(xlabel="Frequency offset / channel spacing",ylabel="Power response (dB)",ylim=(-110,3),
           title="Channel response (coefficient model)")
    ax.legend(); ax.grid(alpha=.25)
    ax=axes[0,1]; k=np.arange(512); sel=(k>=8)&(k<=43)
    ax.plot(k[sel],10*np.log10(np.maximum(rect[sel]/rect.max(),1e-12)),"o-",ms=3,label="Rectangular (floating reference)")
    ax.plot(k[sel],10*np.log10(np.maximum(spectrum[sel]/spectrum.max(),1e-12)),"o-",ms=3,label="PFB-FX (RTL-matched integers)")
    ax.set(xlabel="FFT bin (tone at 25.25)",ylabel="Power / own peak (dB)",ylim=(-100,3),
           title="Steady fractional tone: four valid spectra")
    ax.legend(fontsize=8); ax.grid(alpha=.25)
    ax=axes[1,0]; t=np.arange(len(masks))
    ax.step(t,masks[:,0]+2,where="mid",label="A valid (offset +2)")
    ax.step(t,masks[:,1]+1,where="mid",label="B valid (offset +1)")
    ax.step(t,masks[:,0]*masks[:,1],where="mid",label="Pair valid")
    for boundary in (3.5,7.5): ax.axvline(boundary,color="gray",ls="--",lw=.8)
    ax.set(xlabel="Hop / spectral-frame offset",ylabel="Validity (0 or 1 + offset)",
           title="A missing at hop 4; B missing at hop 6",xticks=t,ylim=(-.15,3.3))
    ax.legend(fontsize=8); ax.grid(alpha=.25)
    ax=axes[1,1]; x=np.arange(len(weights))
    for i,label in enumerate(("W_A","W_B","W_AB")):
        bars=ax.bar(x+(i-1)*.24,weights[:,i],width=.23,label=label)
        ax.bar_label(bars,padding=3)
    ax.axhline(4,color="gray",ls="--",label="Planned M = 4")
    ax.set(xticks=x,xticklabels=["0..3","4..7","8..11"],xlabel="Planned frame offsets per window",
           ylabel="Valid contributions",ylim=(0,4.8),title="Every window closes after four hops")
    ax.legend(fontsize=8); ax.grid(axis="y",alpha=.25)
    fig.suptitle("Lesson04: PFB-FX spectra and planned-window weights",fontsize=15)
    fig.supxlabel("Spectral points and weights: integer reference matched bit-for-bit by RTL. Curves: model only.",fontsize=9)
    path=build/"lesson04_pfb_weights.png"; fig.savefig(path,dpi=150); plt.close(fig); print(path)


if __name__=="__main__": main()
