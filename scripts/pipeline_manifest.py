"""Freeze pipeline build inputs; audit numerical, throughput and timing evidence."""
import argparse
from datetime import datetime,timezone
import hashlib
import json
from pathlib import Path
import re
import time
from vivado_mcp_server import parse_utilization,parse_timing_summary

SOURCES=["rtl/pfb_fir_pair_512_pipeline.sv","rtl/fft_pair_512_pipeline.sv",
    "rtl/channelized_x_pipeline.sv","rtl/two_channel_pfb_fx_pipeline.sv",
    "sim/tb_pfb_fx_pipeline.sv","scripts/generate_pipeline_vectors.py",
    "scripts/generate_lesson04_vectors.py","scripts/pfb512_reference.py","scripts/fft512_reference.py",
    "scripts/pipeline_manifest.py","scripts/run_pipeline.ps1","tcl/run_pipeline.tcl","constraints/pipeline_ooc.xdc",
    "sim/tb_fft_pair_elastic.sv","scripts/run_fft_elastic_test.ps1"]
DATA=["vectors.json","pfb_coeffs.mem","stimulus.txt","expected_pfb.txt","expected_fft.txt","expected_fx.txt"]


def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("action",choices=["begin","finish"])
    p.add_argument("--build-dir",type=Path,required=True)
    p.add_argument("--synthesized",action="store_true")
    p.add_argument("--routed",action="store_true")
    args=p.parse_args();root=Path(__file__).resolve().parents[1];build=args.build_dir.resolve()
    if build==root or root in build.parents:p.error("External build directory required")
    sources={n:digest(root/n) for n in SOURCES};data={n:digest(build/n) for n in DATA}
    inputs=build/"build_inputs.json";proof=build/"verification.json"
    if args.action=="begin":
        if proof.exists():proof.unlink()
        if (build/"simulation_pass.txt").exists():(build/"simulation_pass.txt").unlink()
        inputs.write_text(json.dumps({"started_unix":time.time(),"sources":sources,"data":data},indent=2)+"\n",encoding="utf-8")
        print("PIPELINE_INPUTS_FROZEN");return
    before=json.loads(inputs.read_text())
    assert sources==before["sources"] and data==before["data"],"Build inputs changed during validation"
    marker=build/"simulation_pass.txt";assert marker.stat().st_mtime>=before["started_unix"],"Stale PASS marker"
    text=marker.read_text().strip();assert text.startswith("PASS ")
    stats={k:int(v) for k,v in re.findall(r"(\w+)=(\d+)",text)}
    vectors=json.loads((build/"vectors.json").read_text())
    for k in ("windows","cases","input_pairs","pfb_pairs","fft_pairs","output_bins"):
        assert stats[k]==vectors[k],(k,stats[k],vectors[k])
    assert stats["protocol_faults"]==8
    assert all(stats[k]>0 for k in ("output_stalls","pfb_stalls","input_stalls"))
    assert stats["benchmark_pairs"]==65536 and stats["max_inflight_frames"]>=3
    assert stats["benchmark_input_cycles"]<=128*520
    assert stats["benchmark_total_cycles"]<=65536*125//100
    elastic=build/"elastic_test/elastic_pass.txt"
    assert elastic.stat().st_mtime>=before["started_unix"],"Stale elastic handshake test"
    elastic_text=elastic.read_text().strip()
    elastic_stats={k:int(v) for k,v in re.findall(r"(\w+)=(\d+)",elastic_text)}
    assert elastic_text.startswith("PASS ") and elastic_stats["pairs"]==4096
    assert all(elastic_stats[k]>0 for k in ("independent","replacements","output_stalls"))
    result={"verified_at":datetime.now(timezone.utc).isoformat(),"sources":sources,"data":data,
        "simulation":text,"stats":stats,"hardware_tested":False,"board_network_tested":False,
        "elastic_handshake_test":elastic_text,"elastic_marker_sha256":digest(elastic),
        "nominal_processing_clock_mhz":125,
        "benchmark_input_m_pairs_s_at_nominal_clock":stats["benchmark_pairs"]*125/stats["benchmark_input_cycles"],
        "benchmark_end_to_end_m_pairs_s_at_nominal_clock":stats["benchmark_pairs"]*125/stats["benchmark_total_cycles"],
        "scope":"two-channel arithmetic pipeline; finite 128-frame benchmark, backpressurable input, no RF/network test"}
    if args.synthesized or args.routed:
        dcp=build/"two_channel_pfb_fx_pipeline_synth.dcp"
        assert dcp.stat().st_mtime>=before["started_unix"],"Stale synthesis"
        util=parse_utilization((build/"reports/utilization_synth.rpt").read_text(errors="replace"))
        result["synth_checkpoint_sha256"]=digest(dcp)
        result["utilization"]={k:v for k,v in util.items() if k!="raw"}
    if args.routed:
        routed=build/"two_channel_pfb_fx_pipeline_routed.dcp"
        assert routed.stat().st_mtime>=before["started_unix"],"Stale route"
        timing=parse_timing_summary((build/"reports/timing_routed.rpt").read_text(errors="replace"))
        assert timing.get("wns") is not None and timing["wns"]>=0,timing
        assert timing.get("whs") is not None and timing["whs"]>=0,timing
        result["routed_checkpoint_sha256"]=digest(routed)
        result["ooc_routed_timing"]={k:v for k,v in timing.items() if k!="raw"}
        result["timing_scope"]="OOC internal 8 ns clock paths; not board I/O timing closure"
    proof.write_text(json.dumps(result,indent=2)+"\n",encoding="utf-8")
    print(json.dumps({k:v for k,v in result.items() if k not in ("sources","data","simulation")}))


if __name__=="__main__":main()
