"""Record frozen build inputs, then verify fresh lesson04 artifacts against them."""
import argparse
from datetime import datetime,timezone
import hashlib
import json
from pathlib import Path
import re
import time
from vivado_mcp_server import parse_utilization,parse_timing_summary

SOURCES=["rtl/two_channel_correlator.sv","rtl/fft_pair_512.sv","rtl/channelized_x_engine.sv",
         "rtl/pfb_fir_pair_512.sv","rtl/two_channel_pfb_fx.sv","sim/tb_two_channel_pfb_fx.sv",
         "scripts/fft512_reference.py","scripts/pfb512_reference.py","scripts/generate_lesson04_vectors.py",
         "scripts/run_lesson04.ps1","scripts/lesson04_manifest.py","tcl/run_lesson04.tcl",
         "constraints/lesson04_ooc.xdc","scripts/vivado_mcp_server.py"]
DATA=["vectors.json","pfb_coeffs.mem","stimulus.txt","expected_pfb.txt","expected_fft.txt","expected_fx.txt","response.npz"]


def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action",choices=["begin","finish"])
    parser.add_argument("--build-dir",type=Path,required=True)
    parser.add_argument("--synthesized",action="store_true")
    args=parser.parse_args(); root=Path(__file__).resolve().parents[1]; build=args.build_dir.resolve()
    if build==root or root in build.parents: parser.error("External build directory required")
    src={name:digest(root/name) for name in SOURCES}; data={name:digest(build/name) for name in DATA}
    inputs=build/"build_inputs.json"; proof=build/"verification.json"
    if args.action=="begin":
        if proof.exists(): proof.unlink()
        for name in ("simulation_pass.txt",):
            if (build/name).exists(): (build/name).unlink()
        inputs.write_text(json.dumps({"started_unix":time.time(),"sources":src,"data":data},indent=2)+"\n",encoding="utf-8")
        print("LESSON04_INPUTS_FROZEN"); return
    before=json.loads(inputs.read_text(encoding="utf-8"))
    assert src==before["sources"] and data==before["data"],"Build inputs changed during validation"
    marker=build/"simulation_pass.txt"
    assert marker.stat().st_mtime>=before["started_unix"],"Stale PASS marker"
    text=marker.read_text(encoding="utf-8").strip(); assert text.startswith("PASS ")
    stats={k:int(v) for k,v in re.findall(r"(\w+)=(\d+)",text)}
    vectors=json.loads((build/"vectors.json").read_text(encoding="utf-8"))
    for k in ("windows","cases","input_pairs","pfb_pairs","fft_pairs","output_bins"):
        assert stats[k]==vectors[k],(k,stats[k],vectors[k])
    assert stats["protocol_faults"]==8
    assert all(stats[k]>0 for k in ("output_stalls","pfb_stalls","input_stalls"))
    result={"verified_at":datetime.now(timezone.utc).isoformat(),"simulation":text,"sources":src,
            "data":data,"synthesis_run_this_invocation":args.synthesized,"hardware_tested":False,
            "physical_timing_closed":False,"response_metrics":vectors["response_metrics"]}
    if args.synthesized:
        dcp=build/"two_channel_pfb_fx_synth.dcp"
        assert dcp.stat().st_mtime>=before["started_unix"],"Stale synthesis checkpoint"
        scope=(build/"synthesis_scope.txt").read_text(encoding="utf-8")
        assert "blackboxes=0" in scope
        util=parse_utilization((build/"reports/utilization_synth.rpt").read_text(encoding="utf-8",errors="replace"))
        timing=parse_timing_summary((build/"reports/timing_synth.rpt").read_text(encoding="utf-8",errors="replace"))
        result.update(checkpoint_sha256=digest(dcp),synthesis_scope=scope.splitlines(),
                      utilization={k:v for k,v in util.items() if k!="raw"},
                      timing={k:v for k,v in timing.items() if k!="raw"})
    proof.write_text(json.dumps(result,indent=2)+"\n",encoding="utf-8")
    print(text)


if __name__=="__main__": main()
