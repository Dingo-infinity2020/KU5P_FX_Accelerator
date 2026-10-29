"""Freeze authored CPLL bring-up inputs before simulation/implementation."""
import argparse,hashlib,json,shutil,time
from datetime import datetime,timezone
from pathlib import Path

SOURCES=('tcl/build.tcl','tcl/lesson05g_cpll_project.tcl','constr/lesson05g_cpll.xdc',
    'rtl/lesson05g_cpll_top.sv','rtl/lesson05g_cpll_body.sv','rtl/cpll_diagnostics.sv',
    'rtl/gt_isolation_clocking.sv','rtl/pcie_phy_monitor.sv','sim/tb_cpll_board.sv',
    'scripts/cpll_board_manifest.py','scripts/check_cpll_board.py','scripts/run_cpll_board.ps1')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--build-dir',required=True,type=Path)
    a=p.parse_args();root=Path(__file__).resolve().parents[1];out=a.build_dir.resolve()
    assert out!=root and root not in out.parents,'External directory required'
    sources={name:sha(root/name) for name in SOURCES}
    manifest=out/'inputs.json'
    if manifest.exists():
        old=json.loads(manifest.read_text());assert old['sources']==sources,'Preserve the old attempt before freezing changed sources'
        assert all(sha(out/'source_snapshot'/n)==d for n,d in sources.items())
        print('CPLL frozen inputs match');return
    out.mkdir(parents=True,exist_ok=True)
    for name in SOURCES:
        target=out/'source_snapshot'/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(root/name,target)
    manifest.write_text(json.dumps(dict(build_id='465805e2',started_unix=time.time(),
        started_utc=datetime.now(timezone.utc).isoformat(),sources=sources,
        scope='One GTY X0Y4, CPLL5Gbps, original PCIe reference, inhibited transmitter; no PCIe protocol'),indent=2)+'\n')
    print('CPLL inputs frozen')

if __name__=='__main__':main()
