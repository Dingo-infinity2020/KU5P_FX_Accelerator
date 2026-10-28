"""Generate known byte streams for the AXI-Lite/application unit test."""
import argparse
import json
from pathlib import Path
from pcie_pattern import packet,signature

CASES=[(3,0x90000001,0x10ad30ef),(1,0xffffffff,0xfffffff0),(17,2,0x80000000),(8,0x12345678,0)]


def main():
    p=argparse.ArgumentParser();p.add_argument('--output-dir',type=Path,required=True);args=p.parse_args()
    out=args.output_dir.resolve();root=Path(__file__).resolve().parents[1]
    if out==root or root in out.parents:p.error('Use external build directory')
    out.mkdir(parents=True,exist_ok=True);cases=[];all_bytes=b''
    with (out/'cases.txt').open('w') as desc:
        for case,(count,rid,seed) in enumerate(CASES):
            data=b''.join(packet(i,count,rid,seed) for i in range(count));all_bytes+=data
            desc.write(f'{case} {count} {rid:08x} {seed:08x} {signature(data):08x}\n')
            cases.append({'case':case,'packets':count,'run_id':rid,'seed':seed,'signature':f'{signature(data):08x}'})
    (out/'expected.mem').write_text(''.join(f'{int.from_bytes(all_bytes[i:i+32],"little"):064x}\n' for i in range(0,len(all_bytes),32)))
    (out/'vectors.json').write_text(json.dumps({'cases':cases,'packets':29,'beats':3712,'bytes':len(all_bytes),
        'kind':'synthetic application stream','physical_pcie_tested':False},indent=2)+'\n')
    print('PCIE_VECTORS packets=29 beats=3712')


if __name__=='__main__':main()
