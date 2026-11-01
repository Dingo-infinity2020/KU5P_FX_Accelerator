"""Decode startup evidence; valid evidence and a working PCIe link are separate."""
import argparse,csv,hashlib,json,re
from datetime import datetime,timezone
from pathlib import Path
from pcie_evidence import verify_sources
from check_pcie_training import STATES

sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
U32=(1<<32)-1
GROUPS=('powergood','cplllock','txresetdone','rxresetdone','txpmaresetdone',
        'rxpmaresetdone','rxelecidle','rxvalid','rxcommadet','rxcdrlock',
        'txelecidle','txinhibit','cpllreset','cpllpd')
CONTROL_NAMES=('physical_perst_n','manual_reset','endpoint_reset_n','reference_recent',
    'reference_window_good','axi_div8_recent','sys_mmcm_locked','sys_clock_stopped',
    'any_cpll_locked','qpll1_locked','all_txresetdone','all_rxresetdone',
    'phy_rst_idle','phy_rrst_n','phy_prst_n','link_up','axi_reset_n','raw_observers_valid')

def hexv(s,width):
    if not re.fullmatch('[0-9a-fA-F]{'+str(width//4)+'}',s):raise ValueError('Invalid hex vector')
    return int(s,16)

def raw(value):
    valid=bool(value>>63)
    return dict(valid=valid,groups={name:((value>>(4*i))&15) if valid else None for i,name in enumerate(GROUPS)},
        qpll1lock=bool(value&(1<<56)) if valid else None,
        qpll1reset=None,qpll1pd=None,
        qpll0lock=bool(value&(1<<59)) if valid else None,
        phy_rst_idle=bool(value&(1<<60)),phy_rrst_n=bool(value&(1<<61)),phy_prst_n=bool(value&(1<<62)))

def controls(value):
    if value&0x7c000000:raise ValueError('Reserved control bits are nonzero')
    return dict(**{n:bool(value&(1<<i)) for i,n in enumerate(CONTROL_NAMES)},
        ltssm_raw=(value>>18)&63,ltssm_name=STATES.get((value>>18)&63,'Reserved/unknown'),
        training_recent=bool(value&(1<<24)),all_gt_powergood=bool(value&(1<<25)))

def meta(value):
    return dict(timestamp_cycles=value&((1<<64)-1),epoch=(value>>64)&65535,
        entries=(value>>80)&1023,full=bool(value&(1<<90)),read_valid=bool(value&(1<<91)),
        training_snapshot_valid=bool(value&(1<<92)),training_recent=bool(value&(1<<93)),
        manual_reset=bool(value&(1<<94)),endpoint_reset_n=bool(value&(1<<95)),
        dropped_events=value>>96)

def verify(out):
    root=Path(__file__).resolve().parents[1]
    proof=json.loads((out/'verification.json').read_text())
    if proof['build_id']!='465805e4':raise ValueError('Wrong accepted image')
    locations=verify_sources(out,root,proof['sources'])
    for name,digest in proof['artifacts'].items():
        if sha(out/name)!=digest:raise ValueError('Changed accepted artifact')
    words=(out/'hardware/programmed.tcldict').read_text().split();program=dict(zip(words[::2],words[1::2]))
    if program['build']!='465805e4' or program['configuration']!='JTAG_SRAM' or program['done']!='1':raise ValueError('Invalid program provenance')
    return dict(verification_sha256=sha(out/'verification.json'),
        program_record_sha256=sha(out/'hardware/programmed.tcldict'),verified_source_locations=locations,
        decoder_sha256=sha(Path(__file__)),build_id='465805e4')

def snapshot(path):
    with path.open() as h:rows=list(csv.DictReader(h,delimiter='\t'))
    if len(rows)<2:raise ValueError('At least two observations required')
    samples=[]
    for i,r in enumerate(rows):
        if r['build_hex']!='465805e4' or int(r['index'])!=i:raise ValueError('Identity or index mismatch')
        m=meta(hexv(r['metadata_hex'],128));c=hexv(r['clocks_hex'],128);t=hexv(r['training_hex'],128)
        if m['entries']>512 or m['full']!=(m['entries']==512):raise ValueError('Invalid recorder metadata')
        samples.append(dict(unix_ms=int(r['unix_ms']),raw_hex=r['raw_hex'],raw=raw(hexv(r['raw_hex'],64)),
            metadata=m,ref_div8_count=c&U32,axi_div8_count=(c>>32)&U32,
            reference_window_delta=(c>>64)&U32,controls=controls(c>>96),
            training_sequence=t>>120,training_ltssm=(t>>96)&63,
            training_ltssm_name=STATES.get((t>>96)&63,'Reserved/unknown'),
            training_states_seen_hex=f'{t&((1<<64)-1):016x}'))
    if any(b['unix_ms']<=a['unix_ms'] or b['metadata']['timestamp_cycles']<=a['metadata']['timestamp_cycles'] for a,b in zip(samples,samples[1:])):
        raise ValueError('Independent observer did not advance')
    return dict(capture_sha256=sha(path),evidence_valid=True,samples=samples,
        monitor_advances=True,training_sequence_changes=len({s['training_sequence'] for s in samples})>1,
        ref_count_changes=len({s['ref_div8_count'] for s in samples})>1,
        axi_div8_count_changes=len({s['axi_div8_count'] for s in samples})>1,
        scope='Per-bit synchronized levels, sampled histories and coherent training snapshot; RXVALID/COMMA do not prove TS1/TS2 reception, enumeration or DMA')

def event_files(paths, *, capture_start_cycles=None, previous_observed_cycles=None,
                expected_epoch=None, expected_entries=None):
    """Decode e4 words, separating formatting from temporal provenance.

    Bounds must refer to the same retained configuration's monotonic SYS_CLK
    counter. Current read metadata cannot supply a per-word capture identity.
    No missing high timestamp bits or epoch values are inferred or repaired.
    """
    for value in (capture_start_cycles,previous_observed_cycles):
        if value is not None and (type(value) is not int or not 0<=value<1<<64):
            raise ValueError('Invalid same-configuration timestamp bound')
    if expected_epoch is not None and (type(expected_epoch) is not int or not 0<=expected_epoch<1<<16):
        raise ValueError('Invalid expected epoch')
    if expected_entries is not None and (type(expected_entries) is not int or not 1<=expected_entries<=512):
        raise ValueError('Invalid expected entry count')
    rows=[];hashes={}
    for path in paths:
        with path.open() as h:rows+=list(csv.DictReader(h,delimiter='\t'))
        hashes[path.name]=sha(path)
    rows.sort(key=lambda r:int(r['index']))
    if not rows or [int(r['index']) for r in rows]!=list(range(len(rows))):raise ValueError('Incomplete/overlapping event dump')
    epochs={int(r['epoch']) for r in rows}
    if len(epochs)!=1:raise ValueError('Events cross capture epochs')
    epoch=next(iter(epochs))
    if not 0<=epoch<1<<16 or expected_epoch is not None and epoch!=expected_epoch:
        raise ValueError('Unexpected capture epoch')
    if expected_entries is not None and len(rows)!=expected_entries:
        raise ValueError('Incomplete expected capture')
    events=[]
    for r in rows:
        word=hexv(r['event_hex'],256);m=meta(hexv(r['metadata_hex'],128))
        if m['epoch']!=int(r['epoch']) or not m['read_valid'] or not 1<=m['entries']<=512 or int(r['index'])>=m['entries']:
            raise ValueError('Invalid indexed evidence')
        if expected_entries is not None and m['entries']!=expected_entries:
            raise ValueError('Capture entry count changed during read')
        if (word&((1<<64)-1))>m['timestamp_cycles']:
            raise ValueError('Event timestamp is later than its read observation')
        events.append(dict(index=int(r['index']),timestamp_cycles=word&((1<<64)-1),
            controls=controls((word>>64)&U32),reference_window_delta=(word>>96)&U32,
            raw=raw((word>>128)&((1<<64)-1)),ref_div8_count=(word>>192)&U32,axi_div8_count=word>>224))
    if any(b['timestamp_cycles']<=a['timestamp_cycles'] for a,b in zip(events,events[1:])):raise ValueError('Events are not chronological')
    first=events[0]['timestamp_cycles'];reasons=[]
    if capture_start_cycles is not None and first!=capture_start_cycles:
        reasons.append('FIRST_EVENT_DOES_NOT_MATCH_CAPTURE_START')
    if previous_observed_cycles is not None and first<=previous_observed_cycles:
        reasons.append('EVENT_PREDATES_PREVIOUS_OBSERVATION')
    temporal_status=('FAIL' if reasons else 'BOUNDED_TIME_PASS' if capture_start_cycles is not None
                     else 'LOWER_BOUND_ONLY' if previous_observed_cycles is not None else 'UNKNOWN')
    return dict(input_sha256=hashes,evidence_valid=True,format_valid=True,epoch=epoch,events=events,
        event_count=len(events),temporal_provenance=dict(status=temporal_status,reasons=reasons,
            capture_start_cycles=capture_start_cycles,previous_observed_cycles=previous_observed_cycles,
            record_epoch_status='UNKNOWN_E4_WORD_HAS_NO_EPOCH'),
        scope='Indexed words read under one metadata epoch; formatting is not capture identity. E4 words have no stored epoch; RAM stops on full. No absolute-time or electrical-quality measurement')

def trace(path,layout):
    with path.open(newline='',encoding='utf-8-sig') as h:rows=list(csv.DictReader(h))
    if not rows or not rows[0]['Sample in Buffer'].startswith('Radix'):raise ValueError('Missing radix row')
    radix=rows.pop(0)
    if len(rows)!=4096 or [int(r['Sample in Buffer']) for r in rows]!=list(range(4096)):raise ValueError('Incomplete ILA capture')
    with layout.open() as h:probes=list(csv.DictReader(h,delimiter='\t'))
    widths=[32,64,64];values=[[0]*4096 for _ in widths];masks=[0]*3
    for p in probes:
        port,first,width=(int(p[k]) for k in ('port','first_bit','width'))
        if port not in range(3) or first<0 or width<1:raise ValueError('Invalid ILA metadata')
        names=[k for k in rows[0] if k==p['name'] or k.startswith(p['name']+'[')]
        if len(names)!=1 or radix[names[0]]!='HEX':raise ValueError('Ambiguous ILA column/radix')
        mask=((1<<width)-1)<<first
        if masks[port]&mask:raise ValueError('Overlapping fragments')
        masks[port]|=mask
        parts=[int(r[names[0]],16) for r in rows]
        if any(v<0 or v>=1<<width for v in parts):raise ValueError('Fragment overflow')
        values[port]=[a|(b<<first) for a,b in zip(values[port],parts)]
    if masks!=[(1<<w)-1 for w in widths]:raise ValueError('Incomplete ILA layout')
    rising=[i for i in range(1,4096) if values[0][i]&(1<<31) and not values[0][i-1]&(1<<31)]
    periods=[b-a for a,b in zip(rising,rising[1:])]
    calibration=len(periods)>=3 and set(periods)=={256}
    return dict(csv_sha256=sha(path),layout_sha256=sha(layout),samples=4096,
        heartbeat_period_samples=sorted(set(periods)),same_clock_calibration_passed=calibration,
        first_controls=controls(values[0][0]),last_controls=controls(values[0][-1]),
        first_raw=raw(values[1][0]),last_raw=raw(values[1][-1]),
        ref_div8_count_delta=((values[2][-1]&U32)-(values[2][0]&U32))&U32,
        axi_div8_count_delta=((values[2][-1]>>32)-(values[2][0]>>32))&U32,
        scope='4096 independent SYS_CLK samples; not a startup-duration, absolute-frequency, jitter, TS1/TS2, L0 or DMA acceptance')

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('action',choices=['snapshot','events','trace'])
    p.add_argument('--build-dir',required=True,type=Path);p.add_argument('--label',required=True)
    p.add_argument('--capture-start-cycles',type=lambda s:int(s,0))
    p.add_argument('--previous-observed-cycles',type=lambda s:int(s,0))
    p.add_argument('--expected-epoch',type=int);p.add_argument('--expected-entries',type=int)
    a=p.parse_args();out=a.build_dir.resolve();root=Path(__file__).resolve().parents[1]
    if out==root or root in out.parents or not re.fullmatch('[A-Za-z0-9_-]+',a.label):p.error('External build and valid label required')
    provenance=verify(out);hw=out/'hardware'
    if a.action=='snapshot':result=snapshot(hw/f'{a.label}.tsv')
    elif a.action=='events':result=event_files(list(hw.glob(f'{a.label}_events_*.tsv')),
        capture_start_cycles=a.capture_start_cycles,previous_observed_cycles=a.previous_observed_cycles,
        expected_epoch=a.expected_epoch,expected_entries=a.expected_entries)
    else:result=trace(hw/f'{a.label}.csv',hw/f'{a.label}_layout.tsv')
    result.update(provenance,verified_at_utc=datetime.now(timezone.utc).isoformat())
    with (hw/f'{a.label}_{a.action}.json').open('x') as h:json.dump(result,h,indent=2);h.write('\n')
    print(json.dumps({k:v for k,v in result.items() if k not in ('samples','events','verified_source_locations')}))

if __name__=='__main__':main()
