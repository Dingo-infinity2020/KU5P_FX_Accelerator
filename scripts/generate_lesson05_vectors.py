"""Make authored on-chip ROM replay plus full bit-exact hardware expectations."""
import argparse
import json
from pathlib import Path
import numpy as np
from fft512_reference import FFT512Reference,N
from pfb512_reference import PFB512Reference,coefficients
from generate_lesson04_vectors import tone_frames

# Field order exactly matches lesson04/05 result_payload (most significant first).
FIELDS=[("auto_a",64,False),("auto_b",64,False),("cross_real",64,True),("cross_imag",64,True),
        ("bin",9,False),("last",1,False),("window_id",32,False),("weight_a",32,False),
        ("weight_b",32,False),("weight_ab",32,False),("window_frames",32,False),
        ("first_frame",64,False),("last_frame",64,False),("epoch_id",32,False),
        ("config_id",32,False),("source_a",16,False),("source_b",16,False)]


def pack_result(values):
    packed=0
    for name,width,_ in FIELDS: packed=(packed<<width)|(int(values[name])&((1<<width)-1))
    return packed


def signature_step(previous,payload):
    folded=0
    for shift in range(0,650,32): folded^=(payload>>shift)&0xffffffff
    return (((previous<<5)|(previous>>27))&0xffffffff)^folded


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir",type=Path,required=True)
    parser.add_argument("--vivado-root",type=Path,required=True)
    args=parser.parse_args(); out=args.output_dir.resolve(); root=Path(__file__).resolve().parents[1]
    if out==root or root in out.parents: parser.error("Use an external build directory")
    out.mkdir(parents=True,exist_ok=True)
    frames=tone_frames(16,25.25,20000)
    flags=[(True,True) for _ in frames]; flags[4]=(False,True); flags[6]=(True,False)
    rom=[]
    for frame in frames:
        for ai,aq,bi,bq in frame:
            rom.append(f"{((bq&0xffff)<<48)|((bi&0xffff)<<32)|((aq&0xffff)<<16)|(ai&0xffff):016x}\n")
    (out/"replay_samples.mem").write_text("".join(rom),encoding="ascii")
    (out/"replay_good.mem").write_text("".join(f"{int(a)+2*int(b):x}\n" for a,b in flags),encoding="ascii")
    _,_,coeffs,_=coefficients()
    (out/"pfb_coeffs.mem").write_text("".join(f"{int(v)&0x3ffff:05x}\n" for v in coeffs.flat),encoding="ascii")
    pfb=PFB512Reference(); fft=FFT512Reference(args.vivado_root,out)
    sums=np.zeros((N,4),dtype=np.int64); W=np.zeros(3,dtype=np.int64)
    results=[]; windows=[]; signature=0
    try:
        for j,frame in enumerate(frames):
            filtered,mask=pfb.transform(frame,*flags[j])
            _,a=fft.transform([(ai,aq) for ai,aq,_,_ in filtered])
            _,b=fft.transform([(bi,bq) for _,_,bi,bq in filtered])
            W+=np.array([mask[0],mask[1],mask[0] and mask[1]],dtype=np.int64)
            for k,((ai,aq),(bi,bq)) in enumerate(zip(a,b)):
                sums[k]+=np.array([ai*ai+aq*aq,bi*bi+bq*bq,ai*bi+aq*bq,aq*bi-ai*bq],dtype=np.int64)
            if j%4==3:
                wid=j//4
                windows.append({"window_id":wid,"weights":W.tolist(),"first_frame":1000+j-3,"last_frame":1000+j})
                for k,(pa,pb,vr,vi) in enumerate(sums.tolist()):
                    row=dict(auto_a=pa,auto_b=pb,cross_real=vr,cross_imag=vi,bin=k,last=int(k==511),
                             window_id=wid,weight_a=int(W[0]),weight_b=int(W[1]),weight_ab=int(W[2]),
                             window_frames=4,first_frame=1000+j-3,last_frame=1000+j,epoch_id=5005,
                             config_id=0x00050001,source_a=0,source_b=8)
                    payload=pack_result(row); signature=signature_step(signature,payload); results.append((payload,row))
                sums[:]=0; W[:]=0
        assert [w["weights"] for w in windows]==[[1,1,1],[0,2,0],[4,2,2],[4,4,4]]
        assert len(results)==2048 and len(rom)==8192
        (out/"expected_replay.mem").write_text("".join(f"{p:0163x}\n" for p,_ in results),encoding="ascii")
        (out/"expected_results.json").write_text(json.dumps([r for _,r in results])+"\n",encoding="utf-8")
        manifest={"frames":16,"input_pairs":8192,"windows":windows,"output_rows":2048,
                  "tone_bin":25.25,"amplitude":20000,"relation":"B=jA","missing_hops":{"a":[4],"b":[6]},
                  "expected_signature":signature,"expected_signature_hex":f"{signature:08x}",
                  "design_id_hex":"46580501","payload_width":650,"fields_msb_first":FIELDS,
                  "cmodel":fft.provenance,"max_fir_float_error":pfb.max_float_error,
                  "numpy_max_raw_component_error":fft.max_raw_error}
        (out/"vectors.json").write_text(json.dumps(manifest,indent=2)+"\n",encoding="utf-8")
        print(json.dumps({k:manifest[k] for k in ("frames","input_pairs","output_rows","expected_signature_hex","windows")}))
    finally: fft.close()


if __name__=="__main__": main()
