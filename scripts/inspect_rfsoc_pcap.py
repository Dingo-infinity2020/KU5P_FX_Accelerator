"""Inspect candidate-format PCAP. Sequence gaps do not establish ADC timing."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
from rfsoc_packet_candidate import PROFILE,PacketError,SequenceTracker,decode_frame,read_pcap


def inspect(path):
    tracker=SequenceTracker(); statuses=Counter(); errors=Counter(); events=[]; accepted=0; gap_slots=0; packets=0
    for index,frame in enumerate(read_pcap(path)):
        packets+=1
        try: packet=decode_frame(frame)
        except PacketError as e: errors[str(e)]+=1; continue
        event=tracker.observe(packet); statuses[event["status"]]+=1; gap_slots+=event["gap_before"]
        if event["accepted"]: accepted+=len(packet.samples)
        events.append({"index":index,"source":list(packet.flow_key),"counter":packet.counter,
                       "first_iq":packet.samples[0],"ignored_trailer_bytes":packet.ignored_trailer_bytes,**event})
    return {"profile":PROFILE,"input_sha256":hashlib.sha256(Path(path).read_bytes()).hexdigest(),
            "rf_hardware_validated":False,"packets":packets,"flows":len(tracker.flows),
            "accepted_complex_samples":accepted,"sequence_statuses":dict(statuses),
            "missing_at_delivery_slots":gap_slots,"rejected":dict(errors),"events":events,
            "scope":"candidate layout only; no Ethernet FCS check, no ADC continuity/epoch/cross-board synchronization proof"}


def main():
    p=argparse.ArgumentParser(description=__doc__); p.add_argument("pcap",type=Path)
    p.add_argument("--report",type=Path,required=True)
    args=p.parse_args(); report=args.report.resolve(); root=Path(__file__).resolve().parents[1]
    if report==root or root in report.parents: p.error("Write reports outside repository")
    result=inspect(args.pcap); report.parent.mkdir(parents=True,exist_ok=True)
    report.write_text(json.dumps(result,indent=2)+"\n",encoding="utf-8")
    print(json.dumps({k:v for k,v in result.items() if k not in ("events","scope")}))


if __name__=="__main__": main()
