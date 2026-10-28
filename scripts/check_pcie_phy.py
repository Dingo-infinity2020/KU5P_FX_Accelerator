"""Decode independent synchronized GT/PHY flags; not a coherent multibit bus."""
import argparse
import csv
from datetime import datetime,timezone
import hashlib
import json
from pathlib import Path
import re

FIELDS=('txresetdone','rxresetdone','rxpmaresetdone','txpmaresetdone','ip_power_on',
        'cplllock','qpll_locks','phy_reset_flags','txprogdivresetdone','txsyncdone','rxsyncdone','rxcdrlock')


def decode(value):
    fields={name:(value>>(4*i))&15 for i,name in enumerate(FIELDS)}
    fields.update(qpll1lock=bool(value&(1<<24)),qpll0lock=bool(value&(1<<25)),
        phy_rst_idle=bool(value&(1<<28)),phy_rrst_n=bool(value&(1<<29)),phy_prst_n=bool(value&(1<<30)))
    return fields


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--build-dir',type=Path,required=True);p.add_argument('--label',required=True)
    a=p.parse_args();out=a.build_dir.resolve();root=Path(__file__).resolve().parents[1]
    if out==root or root in out.parents:p.error('External output required')
    if not re.fullmatch('[a-zA-Z0-9_-]+',a.label):p.error('Invalid label')
    proof=json.loads((out/'verification.json').read_text())
    assert proof['monitor_build_id']=='465805d5' and proof['phy_debug']
    for name,expected in proof['sources'].items():
        assert hashlib.sha256((root/name).read_bytes()).hexdigest()==expected, f'Changed source: {name}'
    path=out/'hardware'/f'{a.label}_phy.tsv'
    with path.open(newline='') as h:rows=list(csv.DictReader(h,delimiter='\t'))
    assert len(rows)==12
    samples=[]
    for index,row in enumerate(rows):
        assert int(row['index'])==index and row['build_hex']=='465805d5'
        assert re.fullmatch('[0-9a-f]{36}',row['observation_hex'])
        v=int(row['observation_hex'],16);mask=(1<<48)-1
        current=v&mask;high=(v>>48)&mask;low=(v>>96)&mask
        samples.append(dict(status_hex=row['status_hex'],observation_hex=row['observation_hex'],
            current_hex=f'{current:012x}',ever_high_hex=f'{high:012x}',ever_low_hex=f'{low:012x}',
            current=decode(current),ever_high=decode(high),ever_low=decode(low)))
    result=dict(observed_at_utc=datetime.now(timezone.utc).isoformat(),build_id='465805d5',
        capture_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),samples=samples,
        current_levels_stable=len(set(s['current_hex'] for s in samples))==1,
        scope='Independent per-bit synchronized flags; narrow pulses may be missed; history starts after synchronizer warmup; no coherent encoded FSM or link/DMA proof')
    (out/f'{a.label}_phy.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result))


if __name__=='__main__':main()
