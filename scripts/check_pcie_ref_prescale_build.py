"""Accept clock diagnostic builds only after native routing and source audits."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import shutil
from vivado_mcp_server import parse_timing_summary, parse_utilization


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build-dir',type=Path,required=True)
    parser.add_argument('--parent-dir',type=Path,required=True)
    parser.add_argument('--profile',choices=('prescale','ungated','monitor-pll'),default='prescale')
    args=parser.parse_args()
    root=Path(__file__).resolve().parents[1];out=args.build_dir.resolve();parent=args.parent_dir.resolve()
    assert out!=root and root not in out.parents,'External output required'
    before=json.loads((out/'eco_inputs.json').read_text())
    previous=json.loads((parent/'verification.json').read_text())
    build_id={'prescale':'465805de','ungated':'465805df','monitor-pll':'465805e0'}[args.profile]
    assert before['build_id']==build_id,'Wrong diagnostic profile'
    assert sha(parent/'lesson05d_pcie_top_routed.dcp')==before['parent_checkpoint_sha256'],'Parent changed'
    for name,digest in before['sources'].items():assert sha(root/name)==digest,f'Source changed: {name}'
    if args.profile=='monitor-pll':
        marker=out/'monitor_pll_sim/simulation_pass.txt'
        expected_marker='PASS monitor_pll_checks=4'
    else:
        marker=(out if args.profile=='prescale' else parent)/'prescale_sim/simulation_pass.txt'
        expected_marker='PASS ref_prescale_checks=4'
    assert marker.read_text().strip()==expected_marker
    sim_inputs=before if args.profile!='ungated' else json.loads((parent/'eco_inputs.json').read_text())
    assert sha(marker)==sim_inputs['simulation_sha256'],'Simulation result changed'
    log=(out/'implementation_incremental.log').read_text(errors='replace')
    completed={'prescale':'REF_PRESCALE_EXPERIMENT_COMPLETE','ungated':'REF_UNGATED_EXPERIMENT_COMPLETE',
               'monitor-pll':'MONITOR_PLL_EXPERIMENT_COMPLETE'}[args.profile]
    assert re.search(r'^'+completed+r'\s*$',log,re.M),'Incomplete native build'
    assert not re.search(r'^(?:ERROR:|CRITICAL WARNING:)',log,re.M),'Review/fix native critical messages before accepting'
    reports=out/'reports'
    a=(reports/'functional_inputs_before.tsv').read_bytes()
    assert a==(reports/'functional_inputs_after.tsv').read_bytes(),'Functional inputs changed'
    assert len(a.splitlines())>1000,'Incomplete functional input inventory'
    timing=parse_timing_summary((reports/'timing_routed.rpt').read_text())
    assert timing['met'],'Timing not met'
    for key in ('no_clock','unconstrained_internal_endpoints'):assert timing['constraint_checks'][key]==0,key
    assert '(VIOLATED)' not in (reports/'bus_skew_routed.rpt').read_text(),'Bus skew violation'
    assert not re.search(r'^\|[^\n]*\|\s*Error\s*\|',(reports/'drc_routed.rpt').read_text(),re.M),'DRC error'
    route=(reports/'route_status.rpt').read_text()
    counts={name:int(re.search(pattern,route).group(1)) for name,pattern in (
        ('routable',r'# of routable nets\.+\s*:\s*(\d+)'),
        ('routed',r'# of fully routed nets\.+\s*:\s*(\d+)'),
        ('errors',r'# of nets with routing errors\.+\s*:\s*(\d+)'))}
    assert counts['routable']==counts['routed'] and counts['errors']==0,'Incomplete routing'
    pins=lambda path:dict(line.split('\t') for line in path.read_text().splitlines()[1:])
    assert pins(reports/'verified_pins.tsv')==pins(parent/'reports/verified_pins.tsv'),'Pin mismatch'
    bit=out/'lesson05d_pcie_top.bit'
    assert bit.stat().st_mtime>=before['started_unix'],'Stale bitstream'
    result=dict(previous)
    result.update(verified_at=datetime.now(timezone.utc).isoformat(),
        monitor_build_id=build_id,
        sources=before['sources'],parent_checkpoint_sha256=before['parent_checkpoint_sha256'],
        parent_verification_sha256=sha(parent/'verification.json'),
        measurement='BUFG_GT /8 then counter bit4 /32, total /256; bit1 same-clock heartbeat; raw GT power-good layout unchanged',
        prescale_simulation=previous['prescale_simulation'] if args.profile=='monitor-pll' else marker.read_text().strip(),simulation_scope='Parent application/monitor simulation reused; new UNISIM prescale 100/125/500MHz and stopped-clock tests passed',
        persisted_connections_verified=True,functional_gt_pcie_inputs_unchanged=True,
        functional_input_count=len(a.splitlines())-1,functional_inputs_sha256=hashlib.sha256(a).hexdigest(),
        timing={k:v for k,v in timing.items() if k!='raw'},route=counts,
        utilization={k:v for k,v in parse_utilization((reports/'utilization_routed.rpt').read_text()).items() if k!='raw'},
        implementation_log_sha256=sha(out/'implementation_incremental.log'),
        acceptance_script_sha256=sha(Path(__file__)),
        bitstream_sha256=sha(bit),ltx_sha256=sha(out/'lesson05d_pcie_top.ltx'),
        checkpoint_sha256=sha(out/'lesson05d_pcie_top_routed.dcp'))
    if args.profile=='ungated':
        result.update(diagnostic_ce_bypassed=True,
            measurement='Same /8 and bit4 /32 chain, diagnostic CEMASK=1; total /256; core reference buffer unchanged',
            reference_activity_node='Ungated diagnostic branch, not proof of core reference clock activity',
            simulation_scope='Accepted parent DE UNISIM prescaler simulation reused; only diagnostic CEMASK and identity changed')
    if args.profile=='monitor-pll':
        result.update(monitor_pll_debug=True,
            monitor_pll_bits={'locked':27,'clkin_stopped':31},
            measurement='DF reference observer retained; added diagnostic SYS_CLK MMCME4_ADV, no functional logic driven from its output',
            simulation_scope='Parent application and prescaler simulation reused; new UNISIM MMCM stable100/stopped/recovery/stable125MHz tests passed',
            monitor_pll_simulation=marker.read_text().strip(),
            monitor_pll_scope='LOCKED is a clock qualification flag, not an absolute 100MHz or ppm measurement')
    for name,digest in before['sources'].items():
        target=out/'source_snapshot'/name;target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(root/name,target);assert sha(target)==digest
    (out/'verification.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(dict(build=result['monitor_build_id'],timing=result['timing'],route=counts,
                          unchanged_functional_inputs=result['functional_input_count'])))


if __name__=='__main__':main()
