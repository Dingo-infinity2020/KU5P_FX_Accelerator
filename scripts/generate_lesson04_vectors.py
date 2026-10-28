"""Tagged hop records, bit-exact PFB/FFT/FX references and planned weights."""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from fft512_reference import FFT512Reference, N
from pfb512_reference import PFB512Reference, coefficients, response_metrics


def tone_frames(count, frequency, amplitude=20000):
    t = np.arange(count*N)
    a = np.rint(amplitude*np.exp(2j*np.pi*frequency*t/N))
    # np.rint(complex) is supported, but spell out the integer channels below.
    return [[(int(z.real),int(z.imag),-int(z.imag),int(z.real)) for z in a[j*N:(j+1)*N]]
            for j in range(count)]


def scenarios(seed):
    rng = np.random.default_rng(seed)
    random_frames = rng.integers(-32768,32768,size=(6,N,4)).tolist()
    impulses = np.zeros((8,N,4),dtype=np.int64)
    impulses[3,19] = (32767,-32768,-32768,32767)
    extreme = [[(-32768,32767,-32768 if n%2 else 32767,32767 if n%2 else -32768)
                for n in range(N)] for _ in range(6)]
    return [
        ("fractional_tone",4,tone_frames(8,25.25),{}),
        ("independent_antenna_gaps",4,tone_frames(12,128,16384),{4:(False,True),6:(True,False)}),
        ("zero_and_M1_warmup",1,[[(0,0,0,0)]*N for _ in range(4)],{}),
        ("full_range_random",3,random_frames,{}),
        ("extreme_DC_Nyquist",2,extreme,{}),
        ("random_swapped",3,[[(bi,bq,ai,aq) for ai,aq,bi,bq in f] for f in random_frames],{}),
        ("impulse_history",4,impulses.tolist(),{}),
    ]


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir",type=Path,required=True)
    parser.add_argument("--vivado-root",type=Path,required=True)
    parser.add_argument("--seed",type=lambda x:int(x,0),default=0x50464234)
    args=parser.parse_args()
    output=args.output_dir.resolve()
    repo=Path(__file__).resolve().parents[1]
    if output==repo or repo in output.parents: parser.error("Use an external build directory")
    output.mkdir(parents=True,exist_ok=True)
    h,q,rom,bound=coefficients()
    coeff_text="".join(f"{int(v)&0x3ffff:05x}\n" for v in rom.flat)
    (output/"pfb_coeffs.mem").write_text(coeff_text,encoding="ascii")
    metrics,response=response_metrics()
    fft=FFT512Reference(args.vivado_root,output)
    cases=[]; output_windows=[]; total_frames=0; max_fir_error=0
    try:
        with (output/"stimulus.txt").open("w",encoding="ascii") as stim, \
             (output/"expected_pfb.txt").open("w",encoding="ascii") as pfb_out, \
             (output/"expected_fft.txt").open("w",encoding="ascii") as fft_out, \
             (output/"expected_fx.txt").open("w",encoding="ascii") as fx_out:
            for case,(name,M,frames,gaps) in enumerate(scenarios(args.seed)):
                first=(1<<40)+case*1000; epoch=700+case; config=100+case; sa=10+2*case; sb=sa+1
                stim.write(f"{case} {M} {first} {epoch} {config} {sa} {sb} {len(frames)}\n")
                pfb=PFB512Reference(); weights=np.zeros(3,dtype=np.int64)
                sums=np.zeros((N,4),dtype=np.int64); windows=[]; masks=[]
                for j,frame in enumerate(frames):
                    va,vb=gaps.get(j,(True,True))
                    stim.write(f"{first+j} {int(va)} {int(vb)}\n")
                    stim.writelines(" ".join(map(str,row))+"\n" for row in frame)
                    filtered,mask=pfb.transform(frame,va,vb)
                    masks.append([int(x) for x in mask])
                    weights+=np.array([mask[0],mask[1],mask[0] and mask[1]],dtype=np.int64)
                    for phase,row in enumerate(filtered):
                        pfb_out.write(f"{case} {phase} {int(mask[0])} {int(mask[1])} "+" ".join(map(str,row))+"\n")
                    ar,aq=fft.transform([(ai,aq) for ai,aq,_,_ in filtered])
                    br,bq=fft.transform([(bi,bq) for _,_,bi,bq in filtered])
                    for k,((ari,arq),(bri,brq),(ai,aqi),(bi,bqi)) in enumerate(zip(ar,br,aq,bq)):
                        fft_out.write(f"{case} {k} {ari} {arq} {bri} {brq} {ai} {aqi} {bi} {bqi}\n")
                        sums[k]+=np.array([ai*ai+aqi*aqi,bi*bi+bqi*bqi,ai*bi+aqi*bqi,aqi*bi-ai*bqi],dtype=np.int64)
                    total_frames+=1
                    if j%M==M-1:
                        wid=j//M; wf=first+j-M+1; wl=first+j
                        for k,(pa,pb,vr,vi) in enumerate(sums.tolist()):
                            assert vr*vr+vi*vi <= pa*pb
                            fx_out.write(f"{case} {wid} {k} {wf} {wl} {M} "+" ".join(map(str,weights))+f" {pa} {pb} {vr} {vi} {epoch} {config} {sa} {sb}\n")
                        windows.append({"window":wid,"first":wf,"last":wl,"weights":weights.tolist()})
                        output_windows.append((case,sums.copy()))
                        sums[:]=0; weights[:]=0
                assert len(frames)%M==0
                max_fir_error=max(max_fir_error,pfb.max_float_error)
                cases.append({"case":case,"name":name,"M":M,"frames":len(frames),"first_frame":first,
                              "epoch":epoch,"config":config,"source_a":sa,"source_b":sb,
                              "effective_masks":masks,"windows":windows})
        assert [w["weights"] for w in cases[1]["windows"]] == [[1,1,1],[0,2,0],[4,2,2]]
        assert [w["weights"] for w in cases[2]["windows"]] == [[0,0,0]]*3+[[1,1,1]]
        random=[s for c,s in output_windows if c==3]; swapped=[s for c,s in output_windows if c==5]
        for a,b in zip(random,swapped):
            assert np.array_equal(b,a[:,[1,0,2,3]]*np.array([1,1,1,-1]))
        counts={"cases":len(cases),"frames":total_frames,"input_pairs":total_frames*N,
                "pfb_pairs":total_frames*N,"fft_pairs":total_frames*N,
                "windows":len(output_windows),"output_bins":len(output_windows)*N}
        manifest={**counts,"seed":args.seed,"fft_length":N,"taps_per_phase":4,"hop":N,
                  "coeff_fraction_bits":17,"fir_output_shift":18,"fft_output_shift":10,
                  "coeff_sha256":hashlib.sha256(coeff_text.encode("ascii")).hexdigest(),
                  "filter_definition":"h=sinc((r-1023.5)/512)*Hann(2048); normalize sum(h)=512; Q17 ties-even",
                  "validity":"all four contributing hops valid, separately per antenna",
                  "window_definition":"fixed M sequential frame IDs, invalid contributions do not extend window",
                  "max_fir_vs_float_component_error":max_fir_error,"fir_float_error_bound":1.0,
                  "numpy_max_raw_component_error":fft.max_raw_error,
                  "numpy_max_quantized_component_error":fft.max_quantized_error,
                  "response_metrics":metrics,"cmodel":fft.provenance,"scenarios":cases}
        (output/"vectors.json").write_text(json.dumps(manifest,indent=2)+"\n",encoding="utf-8")
        np.savez(output/"response.npz",offset=response[0],pfb=response[1],rect=response[2],prototype_q17=q)
        print(json.dumps({**counts,"response_metrics":metrics,"max_fir_error":max_fir_error}))
    finally: fft.close()


if __name__=="__main__": main()
