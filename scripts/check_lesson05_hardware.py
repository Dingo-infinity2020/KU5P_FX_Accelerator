"""Strictly compare every captured ILA row with the expected 650-bit payload."""
import argparse
import csv
from datetime import datetime,timezone
import hashlib
import json
from pathlib import Path
import re
from generate_lesson05_vectors import FIELDS,signature_step


def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def check_build(build):
    root=Path(__file__).resolve().parents[1]
    proof=json.loads((build/"verification.json").read_text(encoding="utf-8"))
    assert proof["implemented"] and proof["physical_timing_closed"]
    for directory,group in ((root,proof["sources"]),(build,proof["data"]),(build,proof["artifacts"])):
        for name,expected in group.items(): assert digest(directory/name)==expected,name
    return proof


def unpack(payload):
    values={}
    for name,width,signed in FIELDS[::-1]:
        value=payload&((1<<width)-1); payload>>=width
        if signed and value&(1<<(width-1)): value-=1<<width
        values[name]=value
    assert payload==0
    return values


def parse_capture(path):
    required=["debug_valid","debug_meta","debug_auto_a","debug_auto_b","debug_cross"]
    with path.open(encoding="utf-8-sig",newline="") as stream:
        reader=csv.reader(stream)
        header=next(reader)
        columns={}
        for name in required:
            matches=[i for i,s in enumerate(header) if name in s]
            assert len(matches)==1,("Missing or ambiguous ILA column",name,header)
            columns[name]=matches[0]
        radix=["HEX"]*len(header)
        for row in reader:
            if not row: continue
            if "Radix" in row[0]:
                radix=[cell.split()[-1].upper() for cell in row]; continue
            assert len(row)==len(header),("Malformed capture row",row)
            def number(name,width):
                i=columns[name]; base={"HEX":16,"BINARY":2,"BIN":2,"UNSIGNED":10,"SIGNED":10,"DEC":10}[radix[i]]
                text=row[i].strip()
                if text.lower().startswith("0x"): text=text[2:]
                assert text and not any(c in text.lower() for c in "xz"),("Unknown captured bits",name,text)
                value=int(text,base)
                if value<0: assert radix[i]=="SIGNED" and value>=-(1<<(width-1))
                else: assert value<(1<<width),("Captured value exceeds probe width",name,text)
                return value&((1<<width)-1)
            assert number("debug_valid",1)==1,"Unqualified idle sample in capture"
            p=number("debug_auto_a",64)
            p=(p<<64)|number("debug_auto_b",64)
            p=(p<<128)|number("debug_cross",128)
            p=(p<<394)|number("debug_meta",394)
            yield p


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-dir",type=Path,required=True)
    parser.add_argument("--label",action="append")
    parser.add_argument("--check-build-only",action="store_true")
    args=parser.parse_args(); build=args.build_dir.resolve(); proof=check_build(build)
    if args.check_build_only: print("PASS: frozen sources/data, timing-closed build, matching bit/LTX/DCP"); return
    assert args.label,"At least one capture label is required"
    expected=[int(s,16) for s in (build/"expected_replay.mem").read_text().splitlines()]
    assert len(expected)==2048
    programmed=build/"hardware/programmed.txt"
    identity=dict(line.split("=",1) for line in programmed.read_text().splitlines())
    assert identity["configuration"]=="JTAG_SRAM" and identity["device"]=="xcku5p"
    assert int(identity["bit_bytes"])==(build/"lesson05_board_top.bit").stat().st_size
    assert int(identity["ltx_bytes"])==(build/"lesson05_board_top.ltx").stat().st_size
    assert int(identity["bit_mtime"])==int((build/"lesson05_board_top.bit").stat().st_mtime)
    expected_cycles=int(re.search(r"cycles=(\d+)",proof["simulation"]).group(1))
    captures=[]
    for label in args.label:
        assert label.replace("_","").replace("-","").isalnum()
        path=build/"hardware"/(label+".csv")
        assert path.stat().st_mtime>=programmed.stat().st_mtime,"Capture predates programming"
        actual=list(parse_capture(path)); assert len(actual)==len(expected),(label,len(actual))
        signature=0
        for i,(got,want) in enumerate(zip(actual,expected)):
            assert got==want,(label,i,unpack(got),unpack(want))
            signature=signature_step(signature,got)
        assert signature==0x930aa3d5
        vio=dict(line.split() for line in (build/"hardware"/(label+"_vio.txt")).read_text().splitlines())
        # Vivado VIO INPUT_VALUE is a hexadecimal property value.
        vio={k:int(v,16) for k,v in vio.items()}
        assert vio["before_input_count"]==0 and vio["before_result_count"]==0
        assert vio["*debug_status*"]==0x22 and vio["*input_count*"]==8192 and vio["*result_count*"]==2048,vio
        assert vio["*signature*"]==signature and vio["*run_cycles*"]==expected_cycles,vio
        decoded=build/"hardware"/(label+"_decoded.csv")
        with decoded.open("w",newline="",encoding="utf-8") as stream:
            writer=csv.DictWriter(stream,fieldnames=[f[0] for f in FIELDS]); writer.writeheader()
            writer.writerows(unpack(p) for p in actual)
        captures.append({"label":label,"rows":len(actual),"csv_sha256":digest(path),
                         "vio_sha256":digest(build/"hardware"/(label+"_vio.txt")),
                         "signature_hex":f"{signature:08x}","run_cycles":expected_cycles})
    result={"verified_at":datetime.now(timezone.utc).isoformat(),"hardware_tested":True,"device":"xcku5p",
            "configuration":"JTAG SRAM","input_pairs_per_run":8192,"output_rows_per_run":2048,
            "captures":captures,"build_verification_sha256":digest(build/"verification.json"),
            "bitstream_sha256":proof["artifacts"]["lesson05_board_top.bit"],
            "ltx_sha256":proof["artifacts"]["lesson05_board_top.ltx"],
            "checker_sha256":digest(Path(__file__)),
            "hardware_tcl_sha256":digest(Path(__file__).resolve().parents[1]/"tcl/lesson05_hardware.tcl")}
    (build/"hardware_verification.json").write_text(json.dumps(result,indent=2)+"\n",encoding="utf-8")
    print(json.dumps({"hardware_tested":True,"captures":captures}))


if __name__=="__main__": main()
