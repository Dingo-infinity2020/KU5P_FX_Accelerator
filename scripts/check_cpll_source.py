"""Accept the source-quad CPLL test bitstream without assuming lock or a PCIe link."""
import argparse,csv,hashlib,json,re
from datetime import datetime,timezone
from pathlib import Path
from vivado_mcp_server import parse_timing_summary,parse_utilization

sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--build-dir',type=Path,required=True)
    a=p.parse_args();root=Path(__file__).resolve().parents[1];out=a.build_dir.resolve()
    assert out!=root and root not in out.parents
    inputs=json.loads((out/'inputs.json').read_text());assert inputs['build_id']=='465805e3'
    for name,digest in inputs['sources'].items():
        assert sha(root/name)==sha(out/'source_snapshot'/name)==digest,'Changed source: '+name
    log=(out/'native_build.log').read_text(errors='replace')
    assert re.search(r'^CPLL_SOURCE_QUAD_BUILD_COMPLETE\s*$',log,re.M),'Incomplete native build'
    assert re.search(r'^PASS cpll_board_checks=12\s*$',log,re.M),'No actual dynamic simulation PASS'
    assert not re.search(r'^(ERROR:|CRITICAL WARNING:|Fatal:|FATAL_ERROR:)',log,re.M)
    marker=out/'cpll_board_pass.txt'
    assert marker.read_text().strip()=='PASS cpll_board_checks=12'
    assert marker.stat().st_mtime>=inputs['started_unix'],'Stale simulation marker'
    reports=out/'reports';timing=parse_timing_summary((reports/'timing.rpt').read_text())
    assert timing['met'] and all(timing['constraint_checks'][k]==0 for k in ('no_clock','unconstrained_internal_endpoints'))
    assert '(VIOLATED)' not in (reports/'bus_skew.rpt').read_text()
    cdc=(reports/'cdc.rpt').read_text()
    critical=sum(int(n) for n in re.findall(r'^CDC-\d+\s+Critical\s+(\d+)\s',cdc,re.M))
    assert critical==0,'Unwaived CDC Critical paths require review/fix'
    assert not re.search(r'^\|[^\n]*\|\s*Error\s*\|',(reports/'drc.rpt').read_text(),re.M)
    route=(reports/'route.rpt').read_text()
    counts={name:int(re.search(pattern,route).group(1)) for name,pattern in (
        ('routable',r'# of routable nets\.+\s*:\s*(\d+)'),('routed',r'# of fully routed nets\.+\s*:\s*(\d+)'),
        ('errors',r'# of nets with routing errors\.+\s*:\s*(\d+)'))}
    assert counts['routable']==counts['routed'] and counts['errors']==0
    assert (reports/'gt_inputs_before.tsv').read_bytes()==(reports/'gt_inputs_after.tsv').read_bytes(),'GT functional drivers changed'
    audit_names=('primitive_audit.tsv','pins.tsv','control_observers.tsv','reference_route.tsv')
    for name in audit_names:assert (reports/name).read_bytes()==(out/'reopened_audit'/name).read_bytes(),'DCP reopen audit mismatch: '+name
    with (reports/'primitive_audit.tsv').open(newline='') as h:audit=list(csv.DictReader(h,delimiter='\t'))
    properties={row['property']:row['value'] for row in audit if row['property'] not in ('constant','port')}
    assert properties['LOC']=='GTYE4_CHANNEL_X0Y0'
    assert [int(properties[k]) for k in ('CPLL_FBDIV','CPLL_FBDIV_45','CPLL_REFCLK_DIV','TXOUT_DIV','RXOUT_DIV')]==[5,5,1,1,1]
    assert len([r for r in audit if r['property']=='constant' and r['value']=='1'])==2
    assert len((reports/'pins.tsv').read_text().splitlines())==11
    assert len((reports/'control_observers.tsv').read_text().splitlines())==4
    ref=(reports/'reference_route.tsv').read_text();assert '\tROUTE_STATUS\tROUTED' in ref and 'NORTH' not in ref
    assert '\tLOC\tGTYE4_COMMON_X0Y0' in ref
    assert '\tBEL_PIN\tGTYE4_CHANNEL_X0Y0/GTYE4_CHANNEL/GTREFCLK0' in ref
    wrapper=out/'vivado_project/ip/lesson05g_cpll_gt/sim/lesson05g_cpll_gt.v'
    generated=wrapper.read_text()
    for name,value in (('C_TOTAL_NUM_CHANNELS',1),('C_TOTAL_NUM_COMMONS',0),('C_SIM_CPLL_CAL_BYPASS',1)):
        assert re.search(r'\.'+name+r'\('+str(value)+r'\)',generated)
    names=('lesson05h_cpll_source_top.bit','lesson05h_cpll_source_top.ltx','lesson05h_cpll_source_top_routed.dcp')
    assert (out/names[0]).stat().st_mtime>=inputs['started_unix']
    result=dict(verified_utc=datetime.now(timezone.utc).isoformat(),build_id='465805e3',
        sources=inputs['sources'],artifacts={n:sha(out/n) for n in names},
        simulation=dict(result='PASS cpll_board_checks=12',reset_recovery_cycles=3,sha256=sha(marker),
            simulation_calibration_bypass=True,hardware_cpll_calibration_simulated=False),
        timing={k:v for k,v in timing.items() if k!='raw'},route=counts,cdc_critical_no_waiver=critical,
        utilization={k:v for k,v in parse_utilization((reports/'utilization.rpt').read_text()).items() if k!='raw'},
        audit_sha256={n:sha(reports/n) for n in (*audit_names,'gt_inputs_before.tsv','gt_inputs_after.tsv',
            'gt_hier_inputs_before.tsv','gt_hier_inputs_after.tsv','hierarchical_alias_changes.tsv')},
        gt_functional_inputs_unchanged=True,dcp_reopened_audit_equal=True,
        native_log_sha256=sha(out/'native_build.log'),generated_sim_wrapper_sha256=sha(wrapper),
        acceptance_script_sha256=sha(Path(__file__)),
        scope='One source-quad224 CPLL5Gbps GTY test, TX inhibited, readonly internal control observers; hardware lock/RX data/BER/PCIe/DMA not established')
    (out/'verification.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(dict(build=result['build_id'],timing=result['timing'],route=counts,cdc_critical=critical)))

if __name__=='__main__':main()
