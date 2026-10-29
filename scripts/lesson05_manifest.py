"""Freeze board build inputs; accept only new matching simulation/route outputs."""
import argparse
from datetime import datetime,timezone
import hashlib
import json
from pathlib import Path
import time
from vivado_mcp_server import parse_utilization,parse_timing_summary

SOURCES=["rtl/two_channel_correlator.sv","rtl/fft_pair_512.sv","rtl/channelized_x_engine.sv",
         "rtl/pfb_fir_pair_512.sv","rtl/two_channel_pfb_fx.sv","rtl/lesson05_replay.sv",
         "rtl/lesson05_board_top.sv","sim/tb_lesson05_replay.sv","constr/lesson05_fnic_ku5p.xdc",
         "tcl/build.tcl","tcl/lesson05_project.tcl","scripts/fft512_reference.py",
         "scripts/pfb512_reference.py","scripts/generate_lesson04_vectors.py",
         "scripts/generate_lesson05_vectors.py","scripts/lesson05_manifest.py","scripts/run_lesson05.ps1",
         "scripts/vivado_mcp_server.py"]
DATA=["vectors.json","replay_samples.mem","replay_good.mem","pfb_coeffs.mem","expected_replay.mem","expected_results.json"]


def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action",choices=["begin","finish"])
    parser.add_argument("--build-dir",type=Path,required=True)
    parser.add_argument("--implemented",action="store_true")
    args=parser.parse_args(); root=Path(__file__).resolve().parents[1]; build=args.build_dir.resolve()
    if build==root or root in build.parents: parser.error("Use an external build directory")
    sources={n:sha(root/n) for n in SOURCES}; data={n:sha(build/n) for n in DATA}
    inputs=build/"build_inputs.json"; proof=build/"verification.json"
    if args.action=="begin":
        if proof.exists(): proof.unlink()
        if (build/"simulation_pass.txt").exists(): (build/"simulation_pass.txt").unlink()
        inputs.write_text(json.dumps({"started_unix":time.time(),"sources":sources,"data":data},indent=2)+"\n",encoding="utf-8")
        print("LESSON05_INPUTS_FROZEN"); return
    before=json.loads(inputs.read_text(encoding="utf-8"))
    assert sources==before["sources"] and data==before["data"],"Inputs changed during build"
    marker=build/"simulation_pass.txt"
    assert marker.stat().st_mtime>=before["started_unix"],"Stale simulation marker"
    simulation=marker.read_text(encoding="utf-8").strip()
    assert simulation.startswith("PASS replay_samples=8192 result_rows=2048 signature=930aa3d5 ")
    result={"verified_at":datetime.now(timezone.utc).isoformat(),"simulation":simulation,
            "sources":sources,"data":data,"implemented":args.implemented,"hardware_tested":False}
    if args.implemented:
        artifacts=["lesson05_board_top.bit","lesson05_board_top.ltx","lesson05_board_top_routed.dcp"]
        for name in artifacts:
            assert (build/name).stat().st_mtime>=before["started_unix"],f"Stale {name}"
        result["artifacts"]={n:sha(build/n) for n in artifacts}
        result["implementation_scope"]=(build/"implementation_scope.txt").read_text(encoding="utf-8").splitlines()
        assert "blackboxes=0" in result["implementation_scope"] and "drc_errors=0" in result["implementation_scope"]
        util=parse_utilization((build/"reports/utilization_route.rpt").read_text(encoding="utf-8",errors="replace"))
        timing=parse_timing_summary((build/"reports/timing_route.rpt").read_text(encoding="utf-8",errors="replace"))
        assert timing["met"],timing
        assert timing["constraint_checks"]["no_clock"]==0
        assert timing["constraint_checks"]["unconstrained_internal_endpoints"]==0
        result["utilization"]={k:v for k,v in util.items() if k!="raw"}
        result["timing"]={k:v for k,v in timing.items() if k!="raw"}
        result["physical_timing_closed"]=True
        result["reports"]={n:sha(build/"reports"/n) for n in ["utilization_route.rpt","timing_route.rpt","drc_route.rpt","route_status.rpt","check_timing_route.rpt","cdc_route.rpt"]}
    proof.write_text(json.dumps(result,indent=2)+"\n",encoding="utf-8")
    print(simulation)


if __name__=="__main__": main()
