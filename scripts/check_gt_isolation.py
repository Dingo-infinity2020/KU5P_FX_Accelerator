"""Accept and decode the standalone GT experiment, without claiming a PCIe link."""
import argparse,csv,hashlib,json,re
from datetime import datetime,timezone
from pathlib import Path
from pcie_evidence import verify_sources
from vivado_mcp_server import parse_timing_summary,parse_utilization

sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()

def decode(value):
    result={name:(value>>shift)&15 for name,shift in
            [('powergood',0),('txpmaresetdone',5),('rxpmaresetdone',9)]}
    result.update({name:bool(value&(1<<bit)) for name,bit in
        [('qpll1lock',4),('helper_txdone',21),('helper_rxdone',22),
         ('monitor_mmcm_locked',25),('monitor_clkin_stopped',26),
         ('reset_all',27),('manual_reset',28),('pcie_reset_n',29),('heartbeat_bit7',30)]})
    result['raw_gt_powergood']={f'GTYE4_CHANNEL_X0Y{y}':bool(value&(1<<(y-4))) for y in range(4,8)}
    result.update(txresetdone=None,rxresetdone=None,tx_userclk_active=None,rx_userclk_active=None)
    return result

def heartbeat_bounds(rows):
    first,last=rows[0],rows[-1]
    dt_min=int(last['refresh_start_us'])-int(first['refresh_end_us'])
    dt_max=int(last['refresh_end_us'])-int(first['refresh_start_us'])
    assert 0<dt_min<=dt_max<5_000_000,'Invalid/too long host timestamp interval'
    cycles=(int(last['heartbeat_hex'],16)-int(first['heartbeat_hex'],16))&0xffffffff
    assert cycles>0,'Heartbeat did not advance'
    return dict(min_mhz=cycles/dt_max,max_mhz=cycles/dt_min,cycles=cycles,
        host_elapsed_us_min=dt_min,host_elapsed_us_max=dt_max,
        scope='Gross host-time comparison; assumes each refreshed VIO sample was acquired during its command interval and fewer than one counter wrap; not calibrated ppm accuracy')

def accept(out,root):
    inputs=json.loads((out/'inputs.json').read_text())
    assert inputs['build_id']=='465805e1'
    assert all(sha(root/name)==digest for name,digest in inputs['sources'].items()),'Changed build source'
    verify_sources(out,root,inputs['sources'])
    log=(out/'native_build.log').read_text(errors='replace')
    assert re.search(r'^GT_ISOLATION_IMPLEMENTATION_COMPLETE\s*$',log,re.M),'Build incomplete'
    assert not re.search(r'^(ERROR:|CRITICAL WARNING:|Fatal:)',log,re.M),'Native critical/error or simulation failure'
    simulations={}
    for marker,text in [('reset_simulation_pass.txt','PASS gt_reset_checks=4'),('clocking_simulation_pass.txt','PASS gt_clocking_checks=4')]:
        path=out/marker;assert path.read_text().strip()==text
        assert path.stat().st_mtime>=inputs['started_unix'],'Stale simulation result'
        simulations[marker]=dict(result=text,sha256=sha(path))
    elaboration=out/'reports/gt_single_elaboration.log'
    elaboration_text=elaboration.read_text()
    assert 'Completed static elaboration' in elaboration_text
    assert ('Built simulation snapshot tb_gt_isolation_body_behav' in elaboration_text or
            'No Change in HDL. Linking previously generated obj files to create kernel' in elaboration_text)
    assert (out/'gt_elaboration_only.txt').read_text().strip()=='GT_SINGLE_ELABORATION_ONLY runtime_not_run=BASIC_50000_limit'
    reports=out/'reports'
    timing=parse_timing_summary((reports/'timing_routed.rpt').read_text())
    assert timing['met']
    assert all(timing['constraint_checks'][key]==0 for key in ('no_clock','unconstrained_internal_endpoints'))
    assert '(VIOLATED)' not in (reports/'bus_skew_routed.rpt').read_text()
    assert not re.search(r'^\|[^\n]*\|\s*Error\s*\|',(reports/'drc_routed.rpt').read_text(),re.M)
    route=(reports/'route_status.rpt').read_text()
    counts={name:int(re.search(pattern,route).group(1)) for name,pattern in (
        ('routable',r'# of routable nets\.+\s*:\s*(\d+)'),('routed',r'# of fully routed nets\.+\s*:\s*(\d+)'),
        ('errors',r'# of nets with routing errors\.+\s*:\s*(\d+)'))}
    assert counts['routable']==counts['routed'] and counts['errors']==0
    cdc=(reports/'cdc_no_waiver.rpt').read_text()
    critical=sum(int(n) for n in re.findall(r'^CDC-\d+\s+Critical\s+(\d+)\s',cdc,re.M))
    assert critical==0,'Review/fix unwaived CDC critical paths before accepting'
    pins=lambda p:dict(line.split('\t') for line in p.read_text().splitlines()[1:])
    baseline=out.parent/'lesson05d_pcie_monitor_pll'
    assert pins(reports/'verified_pins.tsv')==pins(baseline/'reports/verified_pins.tsv'),'Board pin mismatch'
    with (reports/'primitive_audit.tsv').open(newline='') as h:audit=list(csv.DictReader(h,delimiter='\t'))
    assert len([a for a in audit if a['property']=='constant' and a['value']=='1'])==8,'TX inhibit/idle audit missing'
    attrs={a['property']:a['value'] for a in audit if 'GTYE4_COMMON' in a['value'] or a['property'].startswith('QPLL1')}
    assert float(attrs['QPLL1_FBDIV'])==80 and float(attrs['QPLL1_REFCLK_DIV'])==1
    artifacts={name:sha(out/name) for name in ('lesson05e_gt_top.bit','lesson05e_gt_top.ltx','lesson05e_gt_top_routed.dcp')}
    assert (out/'lesson05e_gt_top.bit').stat().st_mtime>=inputs['started_unix']
    result=dict(verified_utc=datetime.now(timezone.utc).isoformat(),build_id='465805e1',
        sources=inputs['sources'],simulations=simulations,artifacts=artifacts,
        timing={k:v for k,v in timing.items() if k!='raw'},route=counts,cdc_critical_count_no_waiver=critical,
        utilization={k:v for k,v in parse_utilization((reports/'utilization_routed.rpt').read_text()).items() if k!='raw'},
        native_log_sha256=sha(out/'native_build.log'),acceptance_script_sha256=sha(Path(__file__)),
        audit_sha256=sha(reports/'primitive_audit.tsv'),
        gt_dynamic_simulation_passed=False,
        gt_dynamic_simulation_limitation='Single-channel model 63337 instances; BASIC runtime limit 50000; compilation/elaboration only',
        gt_elaboration_sha256=sha(elaboration),
        simulation_scope='Reset controller faults/recovery and real MMCM wrapper:8 checks. GT model compiled/elaborated but not dynamically simulated; hardware audit/testing required',
        scope='Independent fixed8Gbps QPLL1 GT Wizard, all four transmitters inhibited; not PCIe protocol or DMA')
    (out/'verification.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(dict(build=result['build_id'],timing=result['timing'],route=counts,cdc_critical=critical)))

def capture(out,root,label):
    assert re.fullmatch('[A-Za-z0-9_-]+',label)
    proof=json.loads((out/'verification.json').read_text())
    verify_sources(out,root,proof['sources'])
    assert all(sha(out/name)==digest for name,digest in proof['artifacts'].items()),'Artifact changed'
    path=out/'hardware'/(label+'.tsv')
    with path.open(newline='') as h:rows=list(csv.DictReader(h,delimiter='\t'))
    assert len(rows)==12
    samples=[]
    for index,row in enumerate(rows):
        assert int(row['index'])==index and row['build_hex']=='465805e1'
        assert re.fullmatch('[0-9a-f]{24}',row['observation_hex'])
        assert int(row['refresh_end_us'])>=int(row['refresh_start_us'])
        value=int(row['observation_hex'],16)
        samples.append(dict(current_hex=f'{value&0xffffffff:08x}',current=decode(value&0xffffffff),
            ever_high=decode((value>>32)&0xffffffff),ever_low=decode((value>>64)&0xffffffff)))
    result=dict(observed_utc=datetime.now(timezone.utc).isoformat(),build_id='465805e1',samples=samples,
        capture_sha256=sha(path),decoder_sha256=sha(Path(__file__)),
        heartbeat_host_time=heartbeat_bounds(rows),
        scope='Independent synchronized flags, history since configuration; no PCIe controller present, no link/DMA conclusion')
    (out/(label+'.json')).write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(dict(label=label,current=samples[-1]['current'],heartbeat=result['heartbeat_host_time'])))

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('action',choices=('accept','capture'))
    p.add_argument('--build-dir',type=Path,required=True);p.add_argument('--label')
    a=p.parse_args();root=Path(__file__).resolve().parents[1];out=a.build_dir.resolve()
    assert root!=out and root not in out.parents,'External directory required'
    if a.action=='accept':accept(out,root)
    else:
        assert a.label,'Capture label required';capture(out,root,a.label)

if __name__=='__main__':main()
