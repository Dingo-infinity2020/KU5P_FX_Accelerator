"""Verify CPLL board observations without turning a negative lock result into PASS."""
import argparse,csv,hashlib,json,re
from datetime import datetime,timezone
from pathlib import Path
from pcie_evidence import verify_sources

BUILD='465805e2'
BUILD_PREFIXES={'465805e2':'lesson05g_cpll_top','465805e3':'lesson05h_cpll_source_top'}
U32=(1<<32)-1
EVENT_NAMES=('lock_rise','lock_fall','txdone_rise','txdone_fall')
BIT_NAMES=('gt_powergood','cpll_lock','tx_pma_done','rx_pma_done','tx_helper_done','rx_helper_done',
    'sys_mmcm_locked','sys_clock_stopped','cpllreset_raw','cpllpd_raw','manual_reset',
    'reset_all','reference_qualified','reference_recent','physical_perst_n','heartbeat_bit7','controls_valid')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()

def artifact_prefix(build_id):
    if build_id not in BUILD_PREFIXES:raise ValueError('Unsupported CPLL build identity')
    return BUILD_PREFIXES[build_id]

def flags(value):
    if not 0<=value<1<<32 or value&0x00fe0000:raise ValueError('Unknown/reserved status bits')
    result={name:bool(value&(1<<bit)) for bit,name in enumerate(BIT_NAMES)}
    result.update(initialization_releases=value>>24,
        cpllreset=result['cpllreset_raw'] if result['controls_valid'] else None,
        cpllpd=result['cpllpd_raw'] if result['controls_valid'] else None)
    return result

def events(value):
    return {name:(value>>(32*i))&U32 for i,name in enumerate(EVENT_NAMES)}

def hex_value(value,width):
    if not re.fullmatch('[0-9a-fA-F]{'+str(width//4)+'}',value):raise ValueError('Invalid hex vector width/value')
    return int(value,16)

def capture(path,expected_sequence=None,expected_build=BUILD):
    artifact_prefix(expected_build)
    with path.open(newline='') as h:rows=list(csv.DictReader(h,delimiter='\t'))
    if len(rows)<2:raise ValueError('At least two observations required')
    samples=[]
    for i,row in enumerate(rows):
        if int(row['index'])!=i or row['build_hex']!=expected_build:raise ValueError('Capture identity/index mismatch')
        obs=hex_value(row['observation_hex'],96);current=obs&U32
        manual=int(row['manual_reset']);start=int(row['refresh_start_us']);end=int(row['refresh_end_us'])
        if manual not in (0,1) or end<start:raise ValueError('Invalid reset or timestamps')
        if samples and start<samples[-1]['refresh_end_us']:raise ValueError('Overlapping/nonmonotonic refresh intervals')
        state=flags(current)
        if state['manual_reset']!=bool(manual):raise ValueError('VIO reset readback disagrees with stable diagnostic capture')
        samples.append(dict(index=i,observation_hex=row['observation_hex'],current_hex=f'{current:08x}',
            ever_high_hex=f'{(obs>>32)&U32:08x}',ever_low_hex=f'{(obs>>64)&U32:08x}',current=state,
            heartbeat=hex_value(row['heartbeat_hex'],32),reference_counter=hex_value(row['refcounter_hex'],32),
            events=events(hex_value(row['events_hex'],128)),manual_reset=manual,refresh_start_us=start,refresh_end_us=end))
    intervals=[]
    for a,b in zip(samples,samples[1:]):
        dh=(b['heartbeat']-a['heartbeat'])&U32;dr=(b['reference_counter']-a['reference_counter'])&U32
        monotonic=all(b['events'][k]>=a['events'][k] for k in EVENT_NAMES)
        if not monotonic:raise ValueError('Saturating event counter decreased: capture crossed a configuration/reset boundary')
        intervals.append(dict(heartbeat_delta=dh,reference_delta=dr,
            host_gap_upper_us=b['refresh_end_us']-a['refresh_start_us'],
            reference_mhz_relative_to_nominal_sysclk=(dr/dh)*800 if dh else None))
    required=('gt_powergood','cpll_lock','tx_pma_done','tx_helper_done','sys_mmcm_locked','controls_valid','reference_qualified','reference_recent')
    forbidden=('sys_clock_stopped','manual_reset','reset_all')
    checks=dict(released_levels_good=all(all(s['current'][k] for k in required) and not any(s['current'][k] for k in forbidden)
        and s['current']['cpllreset'] is False and s['current']['cpllpd'] is False for s in samples),
        held_levels_good=all(s['manual_reset']==1 and s['current']['reset_all'] for s in samples),
        observation_at_least_one_second=samples[-1]['refresh_start_us']-samples[0]['refresh_end_us']>=1_000_000,
        heartbeat_advances=all(i['heartbeat_delta']>0 for i in intervals),
        counter_unwrap_interval_bounded=all(i['host_gap_upper_us']<20_000_000 for i in intervals),
        reference_counter_advances=all(i['reference_delta']>0 for i in intervals),
        reference_ratio_matches_nominal=all(i['reference_mhz_relative_to_nominal_sysclk'] is not None and
            95<=i['reference_mhz_relative_to_nominal_sysclk']<=105 for i in intervals),
        events_not_saturated=all(v<U32 for s in samples for v in s['events'].values()),
        no_lock_or_txdone_events_during_observation=samples[0]['events']==samples[-1]['events'])
    if expected_sequence is not None:
        checks['initialization_sequence_matches']=all(s['current']['initialization_releases']==expected_sequence for s in samples)
    released_checks={k:v for k,v in checks.items() if k!='held_levels_good'}
    return dict(build_id=expected_build,capture_sha256=sha(path),decoder_sha256=sha(Path(__file__)),sample_count=len(samples),samples=samples,intervals=intervals,checks=checks,
        released_window_passed=all(released_checks.values()),
        observation_lower_us=samples[-1]['refresh_start_us']-samples[0]['refresh_end_us'],
        observation_upper_us=samples[-1]['refresh_end_us']-samples[0]['refresh_start_us'],
        scope='Synchronized digital observations and bounded host intervals; no RX data/BER, independent absolute frequency, jitter, PCIe or DMA proof',
        counter_assumption='At most one 32-bit heartbeat/reference wrap between adjacent observations; nominal SYS_CLK=100MHz for ratios')

def verify_build(out,root):
    proof=json.loads((out/'verification.json').read_text())
    expected_build=proof['build_id'];prefix=artifact_prefix(expected_build)
    expected_artifacts={prefix+'.bit',prefix+'.ltx',prefix+'_routed.dcp'}
    if set(proof['artifacts'])!=expected_artifacts:raise ValueError('Artifact prefix does not match accepted build identity')
    locations=verify_sources(out,root,proof['sources'])
    inputs=json.loads((out/'inputs.json').read_text())
    if inputs['build_id']!=expected_build or inputs['sources']!=proof['sources']:raise ValueError('Accepted/frozen input mismatch')
    for name,digest in proof['sources'].items():
        if sha(out/'source_snapshot'/name)!=digest:raise ValueError('Frozen snapshot changed: '+name)
    for name,digest in proof['artifacts'].items():
        if sha(out/name)!=digest:raise ValueError('Changed artifact: '+name)
    if not proof['timing']['met'] or proof['cdc_critical_no_waiver']!=0 or proof['route']['errors']!=0 or proof['route']['routable']!=proof['route']['routed']:
        raise ValueError('Implementation acceptance requirements not met')
    return proof,locations

def suite(out,root=None):
    root=root or Path(__file__).resolve().parents[1]
    proof,locations=verify_build(out,root);hw=out/'hardware'
    expected_build=proof['build_id'];prefix=artifact_prefix(expected_build)
    metadata=dict(line.split('=',1) for line in (hw/'programmed.txt').read_text().splitlines())
    if metadata['configuration']!='JTAG_SRAM' or metadata['build']!=expected_build or int(metadata['jtag_hz'])!=6_000_000:
        raise ValueError('Incorrect programming metadata')
    if int(metadata['programmed_unix'])<(out/(prefix+'.bit')).stat().st_mtime:
        raise ValueError('Program record predates accepted bitstream')
    numbers=sorted(int(re.fullmatch(r'cycle([1-9][0-9]*)_released.tsv',p.name).group(1))
        for p in hw.glob('cycle*_released.tsv') if re.fullmatch(r'cycle([1-9][0-9]*)_released.tsv',p.name))
    if len(numbers)<3 or numbers!=list(range(1,len(numbers)+1)) or len(numbers)>254:
        raise ValueError('Need at least three consecutive captured initialization cycles beginning at1')
    with (hw/'reset_actions.tsv').open(newline='') as h:actions=list(csv.DictReader(h,delimiter='\t'))
    if not actions or int(actions[0]['readback'])!=1 or int(actions[-1]['readback'])!=0:
        raise ValueError('Reset log does not bracket experiments')
    if any(int(a['requested']) not in (0,1) or a['requested']!=a['readback'] for a in actions):raise ValueError('Reset readback mismatch')
    if sum(int(a['requested'])==0 for a in actions)!=len(numbers):raise ValueError('Reset releases do not match initialization cycles')
    cycles=[];previous=None
    for n in numbers:
        held_path=hw/f'cycle{n}_held.tsv';released_path=hw/f'cycle{n}_released.tsv'
        if min(held_path.stat().st_mtime,released_path.stat().st_mtime)<int(metadata['programmed_unix']):
            raise ValueError('Capture file predates this programming record')
        held=capture(held_path,n-1,expected_build);released=capture(released_path,n,expected_build)
        a=held['samples'][-1];b=released['samples'][0]
        if b['refresh_start_us']<a['refresh_end_us']:raise ValueError('Released capture predates held capture')
        if previous and held['samples'][0]['refresh_start_us']<previous['refresh_end_us']:raise ValueError('Cycle chronology invalid')
        changed_events={k:b['events'][k]-a['events'][k] for k in EVENT_NAMES}
        if any(v<0 for v in changed_events.values()):raise ValueError('Events went backwards across reset')
        checks=dict(held_request_and_sequence=held['checks']['held_levels_good'] and held['checks']['initialization_sequence_matches'],
            held_heartbeat_advances=held['checks']['heartbeat_advances'],released_window_passed=released['released_window_passed'],
            heartbeat_advances_across_release=((b['heartbeat']-a['heartbeat'])&U32)>0,
            real_lock_and_txdone_recovery=changed_events['lock_rise']>=1 and changed_events['txdone_rise']>=1 and
                (n==1 or (changed_events['lock_fall']>=1 and changed_events['txdone_fall']>=1)))
        if previous:
            if any(held['samples'][0]['events'][k]<previous['events'][k] for k in EVENT_NAMES):raise ValueError('Events reset between cycles')
        previous=released['samples'][-1]
        cycles.append(dict(cycle=n,checks=checks,passed=all(checks.values()),events_across_release=changed_events,
            held=held,released=released))
    return dict(verified_utc=datetime.now(timezone.utc).isoformat(),build_id=expected_build,artifact_prefix=prefix,
        decoder_sha256=sha(Path(__file__)),
        evidence_valid=True,hardware_passed=all(c['passed'] for c in cycles),cycle_count=len(cycles),cycles=cycles,
        verified_source_locations=locations,bitstream_sha256=proof['artifacts'][prefix+'.bit'],
        verification_sha256=sha(out/'verification.json'),programmed_sha256=sha(hw/'programmed.txt'),reset_actions_sha256=sha(hw/'reset_actions.tsv'),
        simulation_pass_does_not_imply_hardware_pass=True,
        scope='Repeated local reset, CPLL and TX initialization/steady digital observations only; RX data/BER/PCIe/DMA not tested')

def trace(path,layout,expected_build=BUILD):
    artifact_prefix(expected_build)
    with path.open(newline='',encoding='utf-8-sig') as h:rows=list(csv.DictReader(h))
    if not rows or not rows[0]['Sample in Buffer'].startswith('Radix'):raise ValueError('Missing ILA radix header')
    radix=rows.pop(0)
    if len(rows)!=8192 or [int(r['Sample in Buffer']) for r in rows]!=list(range(8192)):raise ValueError('Incomplete ILA capture')
    with layout.open(newline='') as h:probes=list(csv.DictReader(h,delimiter='\t'))
    values=[[0]*8192 for _ in range(2)];masks=[0,0]
    for p in probes:
        port,first,width=(int(p[k]) for k in ('port','first_bit','width'))
        if port not in (0,1) or first<0 or width<1:raise ValueError('Invalid ILA metadata')
        names=[k for k in rows[0] if k==p['name'] or k.startswith(p['name']+'[')]
        if len(names)!=1 or radix[names[0]]!='HEX':raise ValueError('Ambiguous column/radix')
        part_mask=((1<<width)-1)<<first
        if masks[port]&part_mask:raise ValueError('Overlapping ILA fragments')
        masks[port]|=part_mask
        raw=[int(r[names[0]],16) for r in rows]
        if any(v<0 or v>=1<<width for v in raw):raise ValueError('ILA fragment value overflow')
        values[port]=[a|(b<<first) for a,b in zip(values[port],raw)]
    if masks!=[(1<<32)-1,(1<<128)-1]:raise ValueError('Incomplete ILA port layout')
    statuses=[flags(v) for v in values[0]];event_values=[events(v) for v in values[1]]
    edges=[i for i in range(1,8192) if statuses[i]['heartbeat_bit7'] and not statuses[i-1]['heartbeat_bit7']]
    periods=[b-a for a,b in zip(edges,edges[1:])]
    calibration_ok=len(periods)>=2 and all(p==256 for p in periods)
    if any(any(b[k]<a[k] for k in EVENT_NAMES) for a,b in zip(event_values,event_values[1:])):raise ValueError('ILA event counter went backwards')
    return dict(build_id=expected_build,identity_scope='Provided by accepted build/provenance; ILA ports do not embed build ID',
        csv_sha256=sha(path),layout_sha256=sha(layout),decoder_sha256=sha(Path(__file__)),samples=8192,heartbeat_period_samples=sorted(set(periods)),
        same_domain_heartbeat_passed=calibration_ok,
        first_status=statuses[0],last_status=statuses[-1],first_events=event_values[0],last_events=event_values[-1],
        observed_transitions={k:sum(a[k]!=b[k] for a,b in zip(statuses,statuses[1:])) for k in ('reset_all','cpll_lock','tx_helper_done')},
        scope='Short selected transition or immediate window; no PLL transition required, not a one-second steady-state or full-suite proof')

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('action',choices=('capture','suite','trace'))
    p.add_argument('--build-dir',type=Path,required=True);p.add_argument('--label')
    a=p.parse_args();out=a.build_dir.resolve();root=Path(__file__).resolve().parents[1]
    if out==root or root in out.parents:p.error('External build directory required')
    if a.action=='suite':result=suite(out);target=out/'hardware/cpll_suite.json'
    else:
        if not a.label or not re.fullmatch('[A-Za-z0-9_-]+',a.label):p.error('Valid capture label required')
        proof,_=verify_build(out,root);expected_build=proof['build_id']
        if a.action=='capture':
            match=re.fullmatch(r'cycle([1-9][0-9]*)_(held|released)',a.label)
            expected=int(match[1])-(match[2]=='held') if match else None
            result=capture(out/'hardware'/f'{a.label}.tsv',expected,expected_build);suffix='capture'
        else:result=trace(out/'hardware'/f'{a.label}.csv',out/'hardware'/f'{a.label}_layout.tsv',expected_build);suffix='trace'
        target=out/'hardware'/f'{a.label}_{suffix}.json'
    with target.open('x',encoding='utf-8') as h:json.dump(result,h,indent=2);h.write('\n')
    print(json.dumps({k:v for k,v in result.items() if k not in ('samples','intervals','cycles','verified_source_locations')}))

if __name__=='__main__':main()
