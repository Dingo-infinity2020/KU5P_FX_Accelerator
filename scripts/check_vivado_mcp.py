"""Exercise the configured local MCP over stdio using disposable build data."""
import argparse
import asyncio
from datetime import datetime, timedelta
import hashlib
import json
from pathlib import Path
import shutil
import time
import tomllib

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client


async def verify(args):
    repo = Path(__file__).resolve().parents[1]
    build = args.build_dir.resolve()
    if build == repo or repo in build.parents:
        raise ValueError("Validation outputs must stay outside the source repository")
    build.mkdir(parents=True,exist_ok=True)
    checkpoint = args.checkpoint.resolve()
    original_hash = hashlib.sha256(checkpoint.read_bytes()).hexdigest()
    copy = build/"fft_fx_probe.dcp"
    shutil.copy2(checkpoint,copy)
    source_vectors = args.lesson02_build.resolve()/"windows.txt"
    shutil.copy2(source_vectors,build/"windows.txt")
    config = tomllib.loads(args.config.read_text(encoding="utf-8-sig"))["mcp_servers"][args.server]
    params = StdioServerParameters(command=config["command"],args=config.get("args",[]),
                                   env=config.get("env",{}),cwd=config.get("cwd"))
    proof = {"verified_at":datetime.now().astimezone().isoformat(),"success":False,
             "transport":"MCP stdio ClientSession", "server":args.server,
             "checkpoint_sha256":original_hash,"calls":[]}
    try:
        async with stdio_client(params) as (read,write):
            async with ClientSession(read,write,read_timeout_seconds=timedelta(seconds=7200)) as client:
                initialized = await client.initialize()
                proof["server_info"] = initialized.serverInfo.model_dump(mode="json")
                catalog = await client.list_tools()
                proof["tool_count"] = len(catalog.tools)
                (build/"tools.json").write_text(json.dumps([tool.model_dump(mode="json") for tool in catalog.tools],indent=2),encoding="utf-8")

                async def call(name,arguments=None):
                    start=time.monotonic()
                    response=await client.call_tool(name,arguments or {})
                    body=json.loads("\n".join(item.text for item in response.content if item.type=="text"))
                    proof["calls"].append({"tool":name,"arguments":arguments or {},"response":body,
                                           "elapsed_seconds":round(time.monotonic()-start,3)})
                    (build/"mcp_trace.json").write_text(json.dumps(proof,indent=2,ensure_ascii=False),encoding="utf-8")
                    if response.isError or body.get("success") is False:
                        raise RuntimeError(f"{name} failed: {body}")
                    print(f"OK {name}",flush=True)
                    return body

                async def tcl(command):
                    return await call("run_tcl",{"command":command})

                started=False
                try:
                    await call("start_session")
                    started=True
                    pid=(await tcl("pid"))["output"].strip()
                    version=(await tcl("version -short"))["output"].strip()
                    proof["vivado_version"]=version
                    await call("check_session_health",{"auto_recover":False})
                    await tcl(f"open_checkpoint {{{copy.as_posix()}}}")
                    utilization=await call("get_utilization",{"detail_level":"summary"})
                    for key,expected in (("lut",6345),("ff",11632),("dsp",52),("bram",10)):
                        if utilization[key]["used"]!=expected:
                            raise AssertionError((key,utilization[key],expected))
                    timing=await call("get_timing_summary",{"detail_level":"summary"})
                    assert abs(timing["wns"]-5.732)<0.001
                    assert timing["constraint_checks"]["no_input_delay"]==99
                    assert timing["constraint_checks"]["no_output_delay"]==334
                    await call("get_clocks")
                    await tcl("close_project")

                    project_dir=build/"probe_project"
                    xpr=project_dir/"mcp_probe.xpr"
                    if not xpr.exists():
                        await tcl(f"create_project mcp_probe {{{project_dir.as_posix()}}} -part xcku5p-ffvb676-1-i")
                    else:
                        await call("open_project",{"project_path":xpr.as_posix()})
                    files=[("sources_1",repo/"rtl/two_channel_correlator.sv"),
                           ("sim_1",repo/"sim/tb_two_channel_correlator.sv"),
                           ("sim_1",build/"windows.txt")]
                    for fileset,path in files:
                        name=path.as_posix()
                        await tcl(f"if {{[llength [get_files -quiet {{{name}}}]] == 0}} {{add_files -fileset {fileset} -norecurse {{{name}}}}}")
                    await tcl(f"set_property file_type {{Data Files}} [get_files {{{(build/'windows.txt').as_posix()}}}]; "
                              "set_property top two_channel_correlator [get_filesets sources_1]; "
                              "set_property xsim.simulate.runtime 0ns [get_filesets sim_1]")
                    await call("set_simulation_top",{"top_module":"tb_two_channel_correlator"})
                    await call("close_project")
                    await call("open_project",{"project_path":xpr.as_posix()})
                    info=await call("get_project_info")
                    assert info["get_property PART [current_project]"].strip()=="xcku5p-ffvb676-1-i"
                    pass_file=project_dir/"mcp_probe.sim/sim_1/behav/xsim/simulation_pass.txt"
                    if pass_file.exists(): pass_file.unlink()
                    await call("launch_simulation",{"mode":"behavioral"})
                    await call("get_signal_value",{"signal":"/tb_two_channel_correlator/rst_n","radix":"hex"})
                    await call("run_simulation",{"time":"100ns"})
                    await call("get_simulation_time")
                    await call("run_simulation",{"time":"all"})
                    simulation=pass_file.read_text().strip()
                    assert simulation.startswith("PASS windows=289 ")
                    proof["simulation"]=simulation
                    await call("close_simulation")
                    await call("close_project")
                    assert (await tcl("pid"))["output"].strip()==pid
                    proof["persistent_vivado_pid"]=pid
                    proof["session_status"]=await call("session_status")
                    proof["success"]=True
                finally:
                    if started: await call("stop_session")
    finally:
        proof["original_checkpoint_unchanged"]=(hashlib.sha256(checkpoint.read_bytes()).hexdigest()==original_hash)
        proof["source_hashes"]={name:hashlib.sha256((repo/name).read_bytes()).hexdigest() for name in
                                ("scripts/vivado_mcp_server.py","scripts/check_vivado_mcp.py")}
        (build/"verification.json").write_text(json.dumps(proof,indent=2,ensure_ascii=False),encoding="utf-8")
    print(json.dumps({key:value for key,value in proof.items() if key not in ("calls","session_status","source_hashes")},ensure_ascii=False))


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config",type=Path,default=Path.home()/".codex/config.toml")
    parser.add_argument("--server",default="vivado")
    parser.add_argument("--build-dir",type=Path,required=True)
    parser.add_argument("--checkpoint",type=Path,required=True)
    parser.add_argument("--lesson02-build",type=Path,required=True)
    asyncio.run(verify(parser.parse_args()))


if __name__=="__main__":
    main()
