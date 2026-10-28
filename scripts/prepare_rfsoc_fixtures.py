"""Generate OFFLINE candidate-format captures; sends no network traffic."""
import argparse
import hashlib
import json
from pathlib import Path
from rfsoc_packet_candidate import PROFILE,SAMPLES,encode_frame,write_pcap


def samples(source,channel,counter):
    data=[]
    for n in range(SAMPLES):
        value=(counter*SAMPLES+n+source*13+channel*7)&0xffff
        i=value if value<32768 else value-65536
        q=65535-value; q=q if q<32768 else q-65536
        data.append((i,q))
    data[:8]=[(0,0),(1,-1),(32767,-32768),(-32768,32767),(-1,1),(0x1234,-0x1234),(-0x1234,0x1234),(42,-42)]
    return data


def main():
    p=argparse.ArgumentParser(description=__doc__); p.add_argument("--output-dir",type=Path,required=True)
    args=p.parse_args(); out=args.output_dir.resolve(); root=Path(__file__).resolve().parents[1]
    if out==root or root in out.parents: p.error("Use a directory outside the source repository")
    out.mkdir(parents=True,exist_ok=True)
    normal=[encode_frame(samples(s,ch,c),ch,c,s) for c in range(2) for s in range(2) for ch in range(8)]
    sequence=[encode_frame(samples(0,0,c),0,c) for c in (0,2,1,2,3)]
    bad=bytearray(normal[0]); bad[42]^=1
    write_pcap(out/"normal_16_flows.pcap",normal)
    write_pcap(out/"sequence_faults.pcap",sequence)
    write_pcap(out/"metadata_fault.pcap",[bytes(bad)])
    manifest={"profile":PROFILE,"capture_kind":"synthetic_fixture","rf_hardware_validated":False,
              "iq_order":"signed16 little-endian I,Q candidate; verify against a known RFSoC capture",
              "payload_bytes":8224,"samples_per_packet":2048,"ethernet_bytes_without_fcs":8320,
              "ignored_synthetic_padding":54,"ip_addresses":"RFC documentation range 192.0.2.0/24",
              "normal":{"packets":32,"flows":16,"complex_samples":65536},
              "sequence_faults":{"packet_counters":[0,2,1,2,3],"statuses":["first","gap","late","duplicate","in_order"],
                                 "accepted_packets":3,"missing_at_delivery_slots":1},
              "metadata_fault":{"rejected_packets":1},
              "files":{f.name:hashlib.sha256(f.read_bytes()).hexdigest() for f in out.glob("*.pcap")},
              "sources":{n:hashlib.sha256((root/"scripts"/n).read_bytes()).hexdigest()
                         for n in ("rfsoc_packet_candidate.py","prepare_rfsoc_fixtures.py","inspect_rfsoc_pcap.py")}}
    (out/"fixture_manifest.json").write_text(json.dumps(manifest,indent=2)+"\n",encoding="utf-8")
    print(json.dumps({k:v for k,v in manifest.items() if k in ("profile","capture_kind","normal","sequence_faults","rf_hardware_validated")}))


if __name__=="__main__": main()
