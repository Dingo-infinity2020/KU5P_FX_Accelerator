"""Vivado MCP Native 0.2.1 launcher with current report-table compatibility.

The upstream package stays in an external venv. This file contains no FPGA
sources and makes no network connection; it serves MCP over local stdio.
"""
import asyncio
import json
import re


def parse_utilization(output):
    rows = {}
    for line in output.splitlines():
        if not line.lstrip().startswith("|"):
            continue
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if len(cells) >= 5:
            rows[cells[0].rstrip("*").strip().lower()] = cells
    aliases = {"lut":("CLB LUTs","Slice LUTs"), "ff":("CLB Registers","Slice Registers"),
               "bram":("Block RAM Tile",), "dsp":("DSPs","DSP"),
               "io":("Bonded IOB","Bonded User I/O")}
    result = {"raw":output, "parser":"ku5p-vivado-table-v1"}
    for resource, labels in aliases.items():
        result[resource] = {"used":None, "available":None, "percent":None, "parsed":False}
        for label in labels:
            cells = rows.get(label.lower())
            if cells:
                try:
                    # Supports Used/Fixed/[Prohibited]/Available/Util% columns.
                    used, available, percent = (float(cells[index].replace(",","")) for index in (1,-2,-1))
                    result[resource] = {"used":used,"available":available,"percent":percent,"parsed":True}
                    break
                except ValueError:
                    pass
    return result


def parse_timing_summary(output):
    result = {key:None for key in ("wns","tns","whs","ths","wpws","tpws","failing_endpoints")}
    lines = output.splitlines()
    for index, line in enumerate(lines):
        if "WNS(ns)" not in line or "TNS(ns)" not in line:
            continue
        for candidate in lines[index+1:index+5]:
            cells = candidate.split()
            try:
                values = [float(value) for value in cells]
            except ValueError:
                continue
            if len(values) >= 12:
                for name, column in (("wns",0),("tns",1),("whs",4),("ths",5),("wpws",8),("tpws",9)):
                    result[name] = values[column]
                result["failing_endpoints"] = int(values[2]+values[6]+values[10])
                break
        if result["wns"] is not None:
            break
    # Retain support for old colon-based summaries, without inventing zeros.
    for name in ("wns","tns","whs","ths","wpws","tpws"):
        if result[name] is None:
            match = re.search(rf"{name.upper()}\(ns\)\s*:\s*([-+\d.]+)",output)
            if match:
                result[name] = float(match.group(1))
    result["met"] = (all(result[key] is not None and result[key] >= 0 for key in ("wns","whs","wpws"))
                     and all(result[key] == 0 for key in ("tns","ths","tpws")))
    result["scope"] = "Reported constrained paths only; inspect check_timing and design stage separately"
    result["constraint_checks"] = {}
    for name in ("no_clock","unconstrained_internal_endpoints","no_input_delay","no_output_delay"):
        match = re.search(rf"checking {name} \((\d+)\)",output)
        result["constraint_checks"][name] = int(match.group(1)) if match else None
    result["raw"] = output
    result["parser"] = "ku5p-vivado-table-v1"
    return result


def simulation_command(mode):
    modes = {"behavioral":"-mode behavioral", "post_synth_func":"-mode post-synthesis -type functional",
             "post_synth_timing":"-mode post-synthesis -type timing",
             "post_impl_func":"-mode post-implementation -type functional",
             "post_impl_timing":"-mode post-implementation -type timing"}
    if mode not in modes:
        raise ValueError(f"Unknown simulation mode: {mode}")
    return "launch_simulation " + modes[mode]


async def serve():
    from mcp.types import TextContent
    from vivado_mcp import server as upstream
    upstream.parse_timing_summary = parse_timing_summary
    upstream.parse_utilization = parse_utilization
    original_call = upstream.call_tool

    async def compatible_call(name, arguments):
        if name == "launch_simulation" or (name == "run_simulation" and arguments.get("time","").lower() == "all"):
            session = upstream.get_session()
            if not session.is_running:
                return [TextContent(type="text",text=json.dumps({"success":False,"error":"Call start_session first"}))]
            command = simulation_command(arguments.get("mode","behavioral")) if name == "launch_simulation" else "run all"
            result = session.run_tcl(command)
            return [TextContent(type="text",text=json.dumps({"success":result.success,"output":result.output,
                                                             "elapsed_ms":result.elapsed_ms}))]
        if name != "get_utilization":
            return await original_call(name, arguments)
        session = upstream.get_session()
        if not session.is_running:
            return [TextContent(type="text",text=json.dumps({"success":False,"error":"Call start_session first"}))]
        hierarchical = arguments.get("hierarchical",False)
        if arguments.get("module_filter"):
            return [TextContent(type="text",text=json.dumps({"success":False,
                "error":"Use run_tcl with this Vivado version's report_utilization options for module filtering"}))]
        command = "report_utilization -return_string" + (" -hierarchical" if hierarchical else "")
        report = session.run_tcl(command)
        parsed = parse_utilization(report.output)
        parsed.update(success=report.success, elapsed_ms=report.elapsed_ms)
        threshold = arguments.get("threshold_percent")
        for key in ("lut","ff","bram","dsp","io"):
            if threshold is not None and parsed[key]["percent"] is not None:
                parsed[key]["below_threshold"] = parsed[key]["percent"] < threshold
        detail = arguments.get("detail_level","summary")
        if detail == "summary" and not hierarchical:
            parsed.pop("raw")
        else:
            limit = 8000 if detail == "full" else 4000
            parsed["raw_total_chars"] = len(report.output)
            parsed["raw_truncated"] = len(report.output) > limit
            parsed["raw"] = report.output[:limit]
        if hierarchical:
            parsed["format"] = "hierarchical; summary counters may be unavailable"
        return [TextContent(type="text",text=json.dumps(parsed))]

    upstream.server.call_tool()(compatible_call)
    try:
        await upstream.main()
    finally:
        # A normal MCP disconnect also closes this server's own Vivado process.
        upstream.get_session().stop()


if __name__ == "__main__":
    asyncio.run(serve())
