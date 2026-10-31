"""Freeze and accept a fresh startup-observer build, independently of link success."""
import argparse,csv,hashlib,json,re,shutil,time,subprocess
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
    p.add_argument('--build-dir',type=Path,required=True)
    p.add_argument('--profile',choices=['e4','e5','e6'],default='e4')
    p.add_argument('--ip-cache-dir',type=Path);a=p.parse_args()
    top=dict(e4='lesson05i_pcie_boot_top',e5='lesson05j_pcie_reference_top',e6='lesson05k_pcie_perst_top')[a.profile]
    build_id='465805'+a.profile
    source_names=SOURCES
    if a.profile!='e4':
        source_names+=('rtl/lesson05j_pcie_reference_top.sv','rtl/pcie_reference_reset.sv',
            'sim/tb_pcie_reference_reset.sv','sim/tb_pcie_boot_provenance.sv',
            'scripts/run_pcie_reference_reset.ps1','scripts/run_pcie_boot_provenance.ps1',
            'scripts/run_pcie_reference.ps1','tcl/audit_pcie_lane_mapping.tcl')
    if a.profile=='e6':source_names+=('rtl/lesson05k_pcie_perst_top.sv','rtl/pcie_perst_reference_reset.sv','sim/tb_pcie_perst_reference_reset.sv')
    root=Path(__file__).resolve().parents[1];out=a.build_dir.resolve()
    assert root!=out and root not in out.parents,'External directory required'
    if a.action=='begin':
        assert not out.exists(),'Use a new directory; preserve failed attempts'
        out.mkdir(parents=True)
        sources={n:sha(root/n) for n in source_names}
        for name in source_names:
            target=out/'source_snapshot'/name;target.parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(root/name,target)
        source_commit=subprocess.check_output(['git','-C',str(root),'rev-parse','HEAD']).decode().strip()
        cache_inputs={}
        if a.ip_cache_dir:
            assert a.ip_cache_dir.is_dir(),'Explicit IP cache missing'
            cache_inputs={str(p.resolve()):sha(p) for p in a.ip_cache_dir.rglob('*.dcp')}
            assert cache_inputs,'No synthesized IP cache inputs'
        (out/'inputs.json').write_text(json.dumps(dict(build_id=build_id,profile=a.profile,source_commit=source_commit,started_unix=time.time(),sources=sources,ip_cache_dcp_sha256=cache_inputs),indent=2)+'\n')
        print('Boot build inputs frozen');return
    inputs=json.loads((out/'inputs.json').read_text())
    assert inputs['build_id']==build_id,'Profile differs from frozen inputs'
    for name,digest in inputs.get('ip_cache_dcp_sha256',{}).items():assert sha(Path(name))==digest,'IP cache DCP changed'
    for name,digest in inputs['sources'].items():
        assert sha(root/name)==sha(out/'source_snapshot'/name)==digest,'Changed source: '+name
    log=(out/'native_build.log').read_text(errors='replace')
    assert 'BOOT_DIAGNOSTIC_BUILD_COMPLETE' in log
    assert not re.search(r'^(ERROR:|CRITICAL WARNING:|Fatal:)',log,re.M)
    simulations={}
    cases=[('boot_sim','PASS boot_diagnostics_checks=14'),
            ('training_sim','PASS training_monitor_checks=9'),('application_test','PASS packets=29 beats=3712 ')]
    if a.profile!='e4':cases += [('reference_reset_sim','PASS reference_reset_checks=10' if a.profile=='e5' else 'PASS perst_reference_reset_checks=7'),('boot_provenance_sim','PASS boot_provenance_checks=15 events=8')]
    for folder,expected in cases:
        marker=out/folder/'simulation_pass.txt';result=marker.read_text().strip()
        assert result.startswith(expected) and marker.stat().st_mtime>=inputs['started_unix']
        simulations[folder]=dict(result=result,sha256=sha(marker))
        for runtime in (out/folder).glob('*.log'):
            assert not re.search(r'(^|\s)(Fatal:|Error:|ERROR:)',runtime.read_text(errors='replace'),re.M),'Simulator error: '+str(runtime)
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
    names=[top+'.bit',top+'.ltx',top+'_routed.dcp']
    assert all((out/n).stat().st_mtime>=inputs['started_unix'] for n in names)
    result=dict(verified_at_utc=datetime.now(timezone.utc).isoformat(),build_id=build_id,profile=a.profile,source_commit=inputs.get('source_commit'),
        sources=inputs['sources'],ip_cache_dcp_sha256=inputs.get('ip_cache_dcp_sha256',{}),artifacts={n:sha(out/n) for n in names},simulation=simulations,
        timing={k:v for k,v in timing.items() if k!='raw'},route=counts,cdc_critical_no_waiver=critical,
        utilization={k:v for k,v in parse_utilization((reports/'utilization.rpt').read_text()).items() if k!='raw'},
        observer_count=59,gt_pcie_functional_inputs_unchanged=True,dcp_reopened_audit_equal=True,
        audit_sha256={n:sha(reports/n) for n in audit_names+['functional_inputs_before.tsv','functional_inputs_after.tsv']},
        scope='Authored diagnostic/reset/application simulation plus implementation and observation-only GT hookups. No full PCIe/GT dynamic model, host enumeration, BAR or DMA acceptance.',
        hardware_tested=False,expected_device_id='9034',pcie_lanes=4,axi_counter_divisor=8,
        ref_counter_divisor=8,event_depth=512,event_bits=256,window_cycles=1000000,
        clock_port_layout_high_to_low=['controls32','window_delta32','axi_div8_count32','ref_div8_count32'])
    if a.profile!='e4':
        with (reports/'lane_data_contract.tsv').open() as h:lane_rows=list(csv.DictReader(h,delimiter='\t'))
        assert len(lane_rows)==272 and all(r['verified']=='1' for r in lane_rows)
        result.update(lane_contract_sha256=sha(reports/'lane_data_contract.tsv'),
            reset_scope='core reset is raw PERSTn AND NOT manual; metadata bit95/control bit2 are independent two-stage observed release, not the raw core input',
            hardware_tested=False,board_authorized=False)
        if a.profile=='e6':result.update(reset_scope='raw physical PERST only; VIO output0 reserved init0 and cannot reset PHY; metadata bit95/control bit2 are two-stage observation, manual-reset metadata is constant0',vio_phy_reset_supported=False)
    with (out/'verification.json').open('x') as h:json.dump(result,h,indent=2);h.write('\n')
    print(json.dumps(dict(build_id=result['build_id'],timing=result['timing'],route=counts,cdc_critical=critical)))

if __name__=='__main__':main()
