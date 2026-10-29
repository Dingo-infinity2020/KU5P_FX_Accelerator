"""Freeze source bytes for a standalone GT experiment before native Vivado."""
import argparse
from datetime import datetime,timezone
import hashlib,json
from pathlib import Path
import shutil,time

SOURCES=('tcl/build.tcl','tcl/lesson05e_gt_project.tcl','rtl/gt_isolation_reset.sv',
    'rtl/gt_isolation_clocking.sv','rtl/gt_isolation_body.sv','rtl/lesson05e_gt_top.sv','rtl/pcie_phy_monitor.sv',
    'constr/lesson05e_gt_isolation.xdc','sim/tb_gt_isolation_reset.sv','sim/tb_gt_isolation_clocking.sv','sim/tb_gt_isolation_body.sv')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--build-dir',type=Path,required=True)
    a=p.parse_args();root=Path(__file__).resolve().parents[1];out=a.build_dir.resolve()
    assert out!=root and root not in out.parents,'Use an external output directory'
    sources={n:sha(root/n) for n in SOURCES}
    path=out/'inputs.json'
    if path.exists():
        old=json.loads(path.read_text());assert old['sources']==sources,'Archive the old attempt before changing frozen inputs'
        print('Existing frozen inputs match');return
    out.mkdir(parents=True,exist_ok=True)
    for name in SOURCES:
        target=out/'source_snapshot'/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(root/name,target)
    path.write_text(json.dumps(dict(build_id='465805e1',started_unix=time.time(),
        started_utc=datetime.now(timezone.utc).isoformat(),sources=sources,
        purpose='Independent GT Wizard, fixed8Gbps QPLL1, nominal100MHz reference and SYS_CLK; all transmitters inhibited'),indent=2)+'\n')
    print('GT inputs frozen')

if __name__=='__main__':main()
