"""Plot actual, hash-verified ILA data after full 650-bit row comparison."""
import argparse
import json
from pathlib import Path
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from check_lesson05_hardware import check_build,digest,parse_capture,unpack


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-dir",type=Path,required=True)
    args=parser.parse_args(); build=args.build_dir.resolve(); check_build(build)
    proof=json.loads((build/"hardware_verification.json").read_text())
    assert proof["hardware_tested"] and digest(build/"verification.json")==proof["build_verification_sha256"]
    traces=[]
    for capture in proof["captures"]:
        path=build/"hardware"/(capture["label"]+".csv")
        assert digest(path)==capture["csv_sha256"]
        traces.append(list(parse_capture(path)))
    expected=[int(s,16) for s in (build/"expected_replay.mem").read_text().splitlines()]
    assert all(trace==expected for trace in traces)
    rows=[unpack(p) for p in traces[0]]
    clean=rows[1536:2048]; k=np.arange(512)
    pa=np.array([r["auto_a"]/r["weight_a"] for r in clean])
    vr=np.array([r["cross_real"]/r["weight_ab"] for r in clean])
    vi=np.array([r["cross_imag"]/r["weight_ab"] for r in clean])
    weights=np.array([[rows[w*512][f"weight_{name}"] for name in ("a","b","ab")] for w in range(4)])
    fig,axes=plt.subplots(2,2,figsize=(12.5,7.5),layout="constrained")
    ax=axes[0,0]; selected=(k>=15)&(k<=35)
    ax.plot(k[selected],pa[selected],"o-",ms=4)
    ax.set(xlabel="FFT bin",ylabel="P_AA / W_A (integer units)",title="FPGA capture: fractional tone at bin 25.25")
    ax.grid(alpha=.25)
    ax=axes[0,1]; selected=(k>=23)&(k<=28)
    ax.plot(k[selected],vr[selected],"o-",label="Real")
    ax.plot(k[selected],vi[selected],"o-",label="Imaginary")
    ax.set(xlabel="FFT bin",ylabel="V_AB / W_AB (integer units)",title="B = jA: A conj(B) has negative imaginary part")
    ax.legend(); ax.grid(alpha=.25)
    ax=axes[1,0]; x=np.arange(4)
    for i,name in enumerate(("W_A","W_B","W_AB")):
        bars=ax.bar(x+(i-1)*.24,weights[:,i],width=.23,label=name); ax.bar_label(bars,padding=3)
    ax.axhline(4,color="gray",ls="--",label="Planned M = 4")
    ax.set(xticks=x,xticklabels=["1000..1003","1004..1007","1008..1011","1012..1015"],
           xlabel="Planned frame range",ylabel="Valid contributions",ylim=(0,4.8),title="FPGA weights: startup and independent gaps")
    ax.tick_params(axis="x",labelsize=8); ax.legend(fontsize=8); ax.grid(axis="y",alpha=.25)
    ax=axes[1,1]
    for trace,capture in zip(traces,proof["captures"]):
        ax.plot(np.arange(2048),[int(a!=b) for a,b in zip(trace,expected)],label=capture["label"])
    ax.set(xlabel="Captured result row",ylabel="650-bit payload mismatch (0/1)",ylim=(-.1,1.1),
           title=f"All 2048 rows match in each of {len(traces)} captures")
    ax.legend(); ax.grid(alpha=.25)
    fig.suptitle("KU5P hardware: ROM replay through PFB / FFT / FX",fontsize=15)
    fig.supxlabel("Actual ILA CSV data; synthetic input; complete payloads compared bit-for-bit with integer reference.",fontsize=9)
    target=build/"lesson05_hardware_results.png"; fig.savefig(target,dpi=150); plt.close(fig); print(target)


if __name__=="__main__": main()
