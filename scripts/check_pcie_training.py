"""Decode coherent d4 training captures; invalid/stale snapshots are not live link proof."""
import argparse
import csv
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re

STATE_SOURCE = 'https://docs.amd.com/r/en-US/pg213-pcie4-ultrascale-plus/Configuration-Status-Interface'
STATES = {0x00:'Detect.Quiet',0x01:'Detect.Active',0x02:'Polling.Active',0x03:'Polling.Compliance',
    0x04:'Polling.Configuration',0x05:'Configuration.Linkwidth.Start',0x06:'Configuration.Linkwidth.Accept',
    0x07:'Configuration.Lanenum.Accept',0x08:'Configuration.Lanenum.Wait',0x09:'Configuration.Complete',
    0x0a:'Configuration.Idle',0x0b:'Recovery.RcvrLock',0x0c:'Recovery.Speed',0x0d:'Recovery.RcvrCfg',
    0x0e:'Recovery.Idle',0x10:'L0',0x17:'L1.Entry',0x18:'L1.Idle',0x20:'Disabled',
    0x21:'Loopback.Entry.Master',0x22:'Loopback.Active.Master',0x23:'Loopback.Exit.Master',
    0x24:'Loopback.Entry.Slave',0x25:'Loopback.Active.Slave',0x26:'Loopback.Exit.Slave',
    0x27:'Hot.Reset',0x28:'Recovery.Equalization.Phase0',0x29:'Recovery.Equalization.Phase1',
    0x2a:'Recovery.Equalization.Phase2',0x2b:'Recovery.Equalization.Phase3'}


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--build-dir',type=Path,required=True)
    p.add_argument('--label',required=True)
    a=p.parse_args()
    if not re.fullmatch(r'[a-zA-Z0-9_-]+',a.label):p.error('Invalid capture label')
    root=Path(__file__).resolve().parents[1];out=a.build_dir.resolve()
    if out==root or root in out.parents:p.error('External output required')
    proof=json.loads((out/'verification.json').read_text())
    assert proof['monitor_build_id'] in ('465805d4','465805d5') and proof['training_debug']
    expected_build=proof['monitor_build_id']
    for name,expected in proof['sources'].items():
        assert hashlib.sha256((root/name).read_bytes()).hexdigest()==expected, f'Changed source: {name}'
    path=out/'hardware'/f'{a.label}_training.tsv'
    with path.open(newline='') as h:rows=list(csv.DictReader(h,delimiter='\t'))
    assert len(rows)==12
    samples=[]
    for index,row in enumerate(rows):
        assert int(row['index'])==index and row['build_hex']==expected_build
        assert re.fullmatch('[0-9a-f]{32}',row['snapshot_hex'])
        value=int(row['snapshot_hex'],16);status=int(row['status_hex'],16)
        assert 0<=status<=255 and row['valid'] in ('0','1')
        valid=row['valid']=='1';state=(value>>96)&63
        seen=value&((1<<64)-1)
        if valid:assert seen&(1<<state),'Current state absent from coherent history'
        samples.append(dict(status_hex=row['status_hex'],valid=valid,
            axi_clock_recent=bool(status&128),snapshot_hex=row['snapshot_hex'],
            state_hex=f'{state:02x}',state_name=STATES.get(state,'Reserved/unknown'),
            states_seen_hex=f'{seen:016x}',states_seen=[dict(hex=f'{i:02x}',name=STATES.get(i,'Reserved/unknown')) for i in range(64) if seen&(1<<i)],
            transitions=(value>>64)&0xffffffff,speed_raw=(value>>102)&7,width_raw=(value>>105)&15,
            sticky_errors_hex=f'{(value>>109)&255:02x}',snapshot_link_up=bool(value&(1<<118)),
            snapshot_axi_reset_n=bool(value&(1<<119)),sequence=(value>>120)&255))
    result=dict(observed_at_utc=datetime.now(timezone.utc).isoformat(),build_id=expected_build,
        state_encoding_source=STATE_SOURCE,capture_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
        samples=samples,valid_snapshots=sum(s['valid'] for s in samples),
        l0_ever_seen=any(s['valid'] and int(s['states_seen_hex'],16)&(1<<16) for s in samples),
        scope='Lifetime history since configuration; snapshot may be stale when AXI clock stops; speed/width kept raw; not host enumeration or DMA proof')
    (out/f'{a.label}_training.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result))


if __name__=='__main__':main()
