"""Audit authored application simulation and a fresh, pin-constrained board build."""
import argparse
from datetime import datetime,timezone
import hashlib
import json
from pathlib import Path
import re
import time
from pcie_pattern import verify,signature
from vivado_mcp_server import parse_utilization,parse_timing_summary

SOURCES=['rtl/dma_pattern_source.sv','rtl/pcie_test_endpoint.sv','rtl/lesson05d_pcie_top.sv',
    'sim/tb_pcie_test_endpoint.sv','constr/lesson05d_fnic_ku5p.xdc','tcl/build.tcl','tcl/lesson05d_project.tcl',
    'scripts/pcie_pattern.py','scripts/generate_pcie_vectors.py','scripts/run_pcie_application_test.ps1',
    'scripts/lesson05d_manifest.py','rtl/pcie_clock_monitor.sv','sim/tb_pcie_clock_monitor.sv',
    'scripts/run_pcie_clock_monitor_test.ps1','tcl/lesson05d_synth_settings.tcl',
    'rtl/lesson05d_pcie_x4_top.sv','constr/lesson05d_fnic_ku5p_x4.xdc',
    'rtl/pcie_training_monitor.sv','rtl/lesson05d_pcie_training_top.sv',
    'sim/tb_pcie_training_monitor.sv','scripts/run_pcie_training_monitor_test.ps1',
    'rtl/pcie_phy_monitor.sv','rtl/lesson05d_pcie_phy_top.sv','constr/lesson05d_phy_monitor.xdc',
    'sim/tb_pcie_phy_monitor.sv','scripts/run_pcie_phy_monitor_test.ps1']


def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('action',choices=['begin','finish'])
    p.add_argument('--build-dir',type=Path,required=True);p.add_argument('--implemented',action='store_true')
    p.add_argument('--lanes',type=int,choices=[4,8],default=8)
    p.add_argument('--training-debug',action='store_true')
    p.add_argument('--phy-debug',action='store_true')
    a=p.parse_args();root=Path(__file__).resolve().parents[1];out=a.build_dir.resolve();test=out/'application_test'
    if out==root or root in out.parents:p.error('External output required')
    if a.training_debug and a.lanes!=4:p.error('Training diagnostic requires x4')
    if a.phy_debug and not a.training_debug:p.error('PHY diagnostic requires training monitor')
    sources={n:sha(root/n) for n in SOURCES}
    data={n:sha(test/n) for n in ('vectors.json','cases.txt','expected.mem')}
    inputs=out/'build_inputs.json'
    if a.action=='begin':
        inputs.write_text(json.dumps({'started_unix':time.time(),'sources':sources,'data':data,'lanes':a.lanes,
            'training_debug':a.training_debug,'phy_debug':a.phy_debug},indent=2)+'\n')
        for n in ('verification.json','simulation_pass.txt'):
            if (out/n).exists():(out/n).unlink()
        print('LESSON05D_INPUTS_FROZEN');return
    before=json.loads(inputs.read_text())
    assert before['lanes']==a.lanes,'PCIe width changed'
    assert before.get('training_debug',False)==a.training_debug,'Diagnostic profile changed'
    assert before.get('phy_debug',False)==a.phy_debug,'PHY profile changed'
    assert before['sources']==sources and before['data']==data,'Inputs changed'
    marker=test/'simulation_pass.txt';assert marker.stat().st_mtime>=before['started_unix'],'Stale simulation'
    text=marker.read_text().strip();assert text.startswith('PASS ')
    stats={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',text)}
    assert stats['packets']==29 and stats['beats']==3712 and stats['stalls']>0 and stats['max_burst']>=256
    assert stats['write_errors']==12 and stats['read_errors']==2 and stats['aw_first']>0 and stats['w_first']>0
    clock_marker=out/'clock_monitor_test/simulation_pass.txt'
    assert clock_marker.stat().st_mtime>=before['started_unix'],'Stale clock monitor simulation'
    assert clock_marker.read_text().strip()=='PASS clock_monitor_checks=7'
    if a.training_debug:
        training_marker=out/'training_monitor_test/simulation_pass.txt'
        assert training_marker.stat().st_mtime>=before['started_unix'],'Stale training monitor simulation'
        assert training_marker.read_text().strip()=='PASS training_monitor_checks=9'
    if a.phy_debug:
        phy_marker=out/'phy_monitor_test/simulation_pass.txt'
        assert phy_marker.stat().st_mtime>=before['started_unix'],'Stale PHY monitor simulation'
        assert phy_marker.read_text().strip()=='PASS phy_monitor_checks=5'
    captured=b''.join(int(line.strip(),16).to_bytes(32,'little') for line in (test/'captured.mem').read_text().splitlines())
    vectors=json.loads((test/'vectors.json').read_text());offset=0;cases=[]
    for case in vectors['cases']:
        size=case['packets']*4096
        result=verify(captured[offset:offset+size],case['packets'],case['run_id'],case['seed'])
        assert result['signature']==case['signature'];cases.append(result);offset+=size
    assert len(captured)==offset==118784
    result={'verified_at':datetime.now(timezone.utc).isoformat(),'sources':sources,'data':data,'simulation':text,
        'stats':stats,'cases':cases,'captured_sha256':sha(test/'captured.mem'),
        'physical_pcie_tested':False,'host_dma_tested':False,'hardware_tested':False,
        'clock_monitor_simulation':clock_marker.read_text().strip(),
        'monitor_build_id':'465805d5' if a.phy_debug else ('465805d4' if a.training_debug else ('465805d3' if a.lanes==4 else '465805d2')),
        'pcie_lanes':a.lanes,'training_debug':a.training_debug,'phy_debug':a.phy_debug,
        'expected_device_id':'9034' if a.lanes==4 else '9038',
        'scope':'authored AXI-Lite and application stream unit test; not PCIe root-port simulation'}
    if a.training_debug:result['training_monitor_simulation']=training_marker.read_text().strip()
    if a.phy_debug:result['phy_monitor_simulation']=phy_marker.read_text().strip()
    if a.implemented:
        reports=out/'reports'
        bit=out/'lesson05d_pcie_top.bit';assert bit.stat().st_mtime>=before['started_unix'],'Stale bitstream'
        timing=parse_timing_summary((reports/'timing_routed.rpt').read_text(errors='replace'))
        assert timing['met'],timing
        for k in ('no_clock','unconstrained_internal_endpoints'):assert timing['constraint_checks'][k]==0,timing
        util=parse_utilization((reports/'utilization_routed.rpt').read_text(errors='replace'))
        drc=(reports/'drc_routed.rpt').read_text()
        assert not re.search(r'^\|[^\n]*\|\s*Error\s*\|',drc,re.M),'DRC error'
        run_log=(out/'vivado_project/lesson05d_pcie.runs/impl_1/runme.log').read_text(errors='replace')
        assert 'CRITICAL WARNING:' not in run_log,'Review critical implementation warnings before acceptance'
        pins=(reports/'verified_pins.tsv').read_text().splitlines()
        assert len(pins)==7+4*a.lanes,'Incomplete pin audit'
        skew=(reports/'bus_skew_routed.rpt').read_text()
        assert '(VIOLATED)' not in skew,'Bus skew violation'
        result.update(bitstream_sha256=sha(bit),ltx_sha256=sha(out/'lesson05d_pcie_top.ltx'),
            checkpoint_sha256=sha(out/'lesson05d_pcie_top_routed.dcp'),
            timing={k:v for k,v in timing.items() if k!='raw'},utilization={k:v for k,v in util.items() if k!='raw'},
            report_sha256={f.name:sha(f) for f in reports.glob('*.rpt')})
    (out/'verification.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k not in ('sources','data','report_sha256')}))


if __name__=='__main__':main()
