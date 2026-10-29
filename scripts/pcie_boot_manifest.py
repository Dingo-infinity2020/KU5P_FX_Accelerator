"""Freeze and accept a fresh startup-observer build, independently of link success."""
import argparse,csv,hashlib,json,re,shutil,time
from datetime import datetime,timezone
from pathlib import Path
from vivado_mcp_server import parse_timing_summary,parse_utilization

SOURCES=('tcl/build.tcl','tcl/lesson05i_boot_project.tcl','tcl/lesson05d_project.tcl',
    'tcl/lesson05d_synth_settings.tcl','constr/lesson05i_pcie_boot.xdc',
    'rtl/lesson05i_pcie_boot_top.sv','rtl/pcie_boot_diagnostics.sv',
    'rtl/pcie_training_monitor.sv','rtl/dma_pattern_source.sv','rtl/pcie_test_endpoint.sv',
    'sim/tb_pcie_boot_diagnostics.sv','sim/tb_pcie_training_monitor.sv','sim/tb_pcie_test_endpoint.sv',
    'scripts/pcie_boot_manifest.py','scripts/run_pcie_boot.ps1','scripts/run_pcie_boot_test.ps1',
    'scripts/run_pcie_training_monitor_test.ps1','scripts/run_pcie_application_test.ps1',
    'scripts/generate_pcie_vectors.py','scripts/pcie_pattern.py')
sha=lambda path:hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('action',choices=['begin','finish'])
    p.add_argument('--build-dir',type=Path,required=True);a=p.parse_args()
    root=Path(__file__).resolve().parents[1];out=a.build_dir.resolve()
    assert root!=out and root not in out.parents,'External directory required'
    if a.action=='begin':
        assert not out.exists(),'Use a new directory; preserve failed attempts'
        out.mkdir(parents=True)
        sources={n:sha(root/n) for n in SOURCES}
        for name in SOURCES:
            target=out/'source_snapshot'/name;target.parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(root/name,target)
        (out/'inputs.json').write_text(json.dumps(dict(build_id='465805e4',started_unix=time.time(),sources=sources),indent=2)+'\n')
        print('Boot build inputs frozen');return
    inputs=json.loads((out/'inputs.json').read_text())
    for name,digest in inputs['sources'].items():
        assert sha(root/name)==sha(out/'source_snapshot'/name)==digest,'Changed source: '+name
    log=(out/'native_build.log').read_text(errors='replace')
    assert 'BOOT_DIAGNOSTIC_BUILD_COMPLETE' in log
    assert not re.search(r'^(ERROR:|CRITICAL WARNING:|Fatal:)',log,re.M)
    simulations={}
    for folder,expected in [('boot_sim','PASS boot_diagnostics_checks=14'),
            ('training_sim','PASS training_monitor_checks=9'),('application_test','PASS packets=29 beats=3712 ')]:
        marker=out/folder/'simulation_pass.txt';result=marker.read_text().strip()
        assert result.startswith(expected) and marker.stat().st_mtime>=inputs['started_unix']
        simulations[folder]=dict(result=result,sha256=sha(marker))
    assert not re.search(r'(^|\s)(Fatal:|Error:|ERROR:)',(out/'boot_sim/boot_runtime.log').read_text(),re.M)
    assert (out/'application_test/captured.mem').read_bytes()==(out/'application_test/expected.mem').read_bytes()
    reports=out/'reports';timing=parse_timing_summary((reports/'timing.rpt').read_text())
    assert timing['met'] and all(timing['constraint_checks'][k]==0 for k in ('no_clock','unconstrained_internal_endpoints'))
    assert '(VIOLATED)' not in (reports/'bus_skew.rpt').read_text()
    critical=sum(int(n) for n in re.findall(r'^CDC-\d+\s+Critical\s+(\d+)\s',(reports/'cdc.rpt').read_text(),re.M))
    assert critical==0
    route=(reports/'route.rpt').read_text()
    counts={name:int(re.search(pattern,route).group(1)) for name,pattern in (
        ('routable',r'# of routable nets\.+\s*:\s*(\d+)'),('routed',r'# of fully routed nets\.+\s*:\s*(\d+)'),
        ('errors',r'# of nets with routing errors\.+\s*:\s*(\d+)'))}
    assert counts['routable']==counts['routed'] and counts['errors']==0
    assert (reports/'functional_inputs_before.tsv').read_bytes()==(reports/'functional_inputs_after.tsv').read_bytes()
    audit_names=['observers.tsv','destinations.tsv','pins.tsv','clock_reset.tsv']
    for name in audit_names:assert (reports/name).read_bytes()==(out/'reopened_audit'/name).read_bytes(),name
    with (reports/'observers.tsv').open() as h:observers=list(csv.DictReader(h,delimiter='\t'))
    assert {int(r['bit']) for r in observers}==set(range(57))|{59,63}
    with (reports/'pins.tsv').open() as h:pins={r['port']:r['package_pin'] for r in csv.DictReader(h,delimiter='\t')}
    expected=dict(SYS_CLK='AB21',LED1='AF14',LED2='AF15',pcie_refclk_p='AB7',pcie_refclk_n='AB6',pcie_reset_n='T19')
    for signal,values in [('pcie_rx_p',['P2','T2','V2','Y2']),('pcie_rx_n',['P1','T1','V1','Y1']),
                          ('pcie_tx_p',['R5','U5','W5','AA5']),('pcie_tx_n',['R4','U4','W4','AA4'])]:
        expected.update({f'{signal}[{i}]':pin for i,pin in enumerate(values)})
    assert pins==expected
    names=['lesson05i_pcie_boot_top.bit','lesson05i_pcie_boot_top.ltx','lesson05i_pcie_boot_top_routed.dcp']
    assert all((out/n).stat().st_mtime>=inputs['started_unix'] for n in names)
    result=dict(verified_at_utc=datetime.now(timezone.utc).isoformat(),build_id='465805e4',
        sources=inputs['sources'],artifacts={n:sha(out/n) for n in names},simulation=simulations,
        timing={k:v for k,v in timing.items() if k!='raw'},route=counts,cdc_critical_no_waiver=critical,
        utilization={k:v for k,v in parse_utilization((reports/'utilization.rpt').read_text()).items() if k!='raw'},
        observer_count=59,gt_pcie_functional_inputs_unchanged=True,dcp_reopened_audit_equal=True,
        audit_sha256={n:sha(reports/n) for n in audit_names+['functional_inputs_before.tsv','functional_inputs_after.tsv']},
        scope='Authored diagnostic/reset/application simulation plus implementation and observation-only GT hookups. No full PCIe/GT dynamic model, host enumeration, BAR or DMA acceptance.',
        hardware_tested=False,expected_device_id='9034',pcie_lanes=4,axi_counter_divisor=8,
        ref_counter_divisor=8,event_depth=512,event_bits=256,window_cycles=1000000,
        clock_port_layout_high_to_low=['controls32','window_delta32','axi_div8_count32','ref_div8_count32'])
    with (out/'verification.json').open('x') as h:json.dump(result,h,indent=2);h.write('\n')
    print(json.dumps(dict(build_id=result['build_id'],timing=result['timing'],route=counts,cdc_critical=critical)))

if __name__=='__main__':main()
