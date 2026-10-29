"""Freeze the exact sources and successful RTL simulation for a read-only build."""
import argparse,hashlib,json,shutil,time
from pathlib import Path

SOURCES=('tcl/build.tcl','tcl/lesson05f_si5338_project.tcl','constr/lesson05f_si5338.xdc',
    'rtl/i2c_register_readonly.sv','rtl/lesson05f_si5338_top.sv',
    'sim/tb_i2c_register_readonly.sv','scripts/run_i2c_readonly_test.ps1')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--build-dir',type=Path,required=True)
    a=p.parse_args();root=Path(__file__).resolve().parents[1];out=a.build_dir.resolve()
    assert out!=root and root not in out.parents,'External build directory required'
    marker=out/'i2c_sim/simulation_pass.txt'
    assert marker.read_text().strip()=='PASS i2c_readonly_checks=10'
    sources={n:sha(root/n) for n in SOURCES};path=out/'inputs.json'
    if path.exists():
        old=json.loads(path.read_text())
        assert old['sources']==sources and old['simulation_sha256']==sha(marker),'Use a new output directory for changed inputs'
        assert all(sha(out/'source_snapshot'/n)==digest for n,digest in sources.items())
        print('Existing frozen inputs match');return
    for name in SOURCES:
        target=out/'source_snapshot'/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(root/name,target)
    path.write_text(json.dumps(dict(build_id='465805f1',started_unix=time.time(),
        sources=sources,simulation_sha256=sha(marker)),indent=2)+'\n')
    print('Read-only I2C inputs frozen')

if __name__=='__main__':main()
