"""Accept the read-only I2C bitstream before touching clock-chip pins."""
import argparse,hashlib,json,re
from datetime import datetime,timezone
from pathlib import Path
from vivado_mcp_server import parse_timing_summary,parse_utilization

sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--build-dir',type=Path,required=True)
    a=p.parse_args();root=Path(__file__).resolve().parents[1];out=a.build_dir.resolve()
    assert out!=root and root not in out.parents
    inputs=json.loads((out/'inputs.json').read_text())
    assert inputs['build_id']=='465805f1'
    for name,digest in inputs['sources'].items():
        assert sha(root/name)==sha(out/'source_snapshot'/name)==digest,'Changed input: '+name
    marker=out/'i2c_sim/simulation_pass.txt'
    assert marker.read_text().strip()=='PASS i2c_readonly_checks=10' and sha(marker)==inputs['simulation_sha256']
    log=(out/'native_build.log').read_text(errors='replace')
    assert re.search(r'^SI5338_READONLY_BUILD_COMPLETE\s*$',log,re.M)
    assert not re.search(r'^(ERROR:|CRITICAL WARNING:)',log,re.M)
    reports=out/'reports';timing=parse_timing_summary((reports/'timing.rpt').read_text())
    assert timing['met'] and all(timing['constraint_checks'][k]==0 for k in ('no_clock','unconstrained_internal_endpoints'))
    cdc=(reports/'cdc.rpt').read_text()
    critical=sum(int(n) for n in re.findall(r'^CDC-\d+\s+Critical\s+(\d+)\s',cdc,re.M))
    assert critical==0,'Unwaived CDC Critical paths require review/fix'
    assert not re.search(r'^\|[^\n]*\|\s*Error\s*\|',(reports/'drc.rpt').read_text(),re.M)
    route=(reports/'route.rpt').read_text()
    counts={name:int(re.search(pattern,route).group(1)) for name,pattern in (
        ('routable',r'# of routable nets\.+\s*:\s*(\d+)'),('routed',r'# of fully routed nets\.+\s*:\s*(\d+)'),
        ('errors',r'# of nets with routing errors\.+\s*:\s*(\d+)'))}
    assert counts['routable']==counts['routed'] and counts['errors']==0
    assert len((reports/'pins.tsv').read_text().splitlines())==9
    assert all('\tGND\t' in line for line in (reports/'open_drain.tsv').read_text().splitlines()[1:])
    names=('lesson05f_si5338_top.bit','lesson05f_si5338_top.ltx','lesson05f_si5338_top_routed.dcp')
    assert (out/names[0]).stat().st_mtime>=inputs['started_unix']
    proof=dict(verified_utc=datetime.now(timezone.utc).isoformat(),build_id='465805f1',sources=inputs['sources'],
        artifacts={n:sha(out/n) for n in names},timing={k:v for k,v in timing.items() if k!='raw'},route=counts,
        cdc_critical_no_waiver=critical,simulation='PASS i2c_readonly_checks=10',simulation_sha256=sha(marker),
        utilization={k:v for k,v in parse_utilization((reports/'utilization.rpt').read_text()).items() if k!='raw'},
        native_log_sha256=sha(out/'native_build.log'),acceptance_script_sha256=sha(Path(__file__)),
        audit_sha256={n:sha(reports/n) for n in ('pins.tsv','open_drain.tsv')},
        scope='Fixed0x70 pointer-only writes followed by byte reads; no configuration-data, page selector or clock output writes')
    (out/'verification.json').write_text(json.dumps(proof,indent=2)+'\n')
    print(json.dumps(dict(build=proof['build_id'],timing=proof['timing'],route=counts,cdc_critical=critical)))

if __name__=='__main__':main()
