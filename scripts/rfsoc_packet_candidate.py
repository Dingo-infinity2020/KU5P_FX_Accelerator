"""Authored, OFFLINE candidate decoder derived from locally reviewed metadata.

Wire layout and I/Q order still require a known-pattern RFSoC capture. This is
not a copy of RFSoC engineering sources and does not configure or contact it.
"""
from collections import OrderedDict
from dataclasses import dataclass
import ipaddress
from pathlib import Path
import struct

PROFILE = "rfsoc-static-candidate-v1"
HEAD = 0xAA55AA55
FORMAT_TAG = 0x11223344  # Raw format marker, not an inferred version number.
TAIL = 0xAA55AA5544332211
SAMPLES = 2048
META = struct.Struct("<IIIIQQ")
PAYLOAD_BYTES = 32+SAMPLES*4


class PacketError(ValueError): pass


def checksum(data):
    if len(data)%2: data+=b"\0"
    value=sum(struct.unpack(f"!{len(data)//2}H",data))
    while value>>16: value=(value&0xffff)+(value>>16)
    return (~value)&0xffff


def encode_payload(samples,channel,counter):
    if not 0<=channel<8 or not 0<=counter<1<<64 or len(samples)!=SAMPLES:
        raise ValueError("Expected channel 0..7, uint64 counter and 2048 I/Q pairs")
    return META.pack(HEAD,FORMAT_TAG,channel,16,counter,TAIL)+b"".join(struct.pack("<hh",i,q) for i,q in samples)


def decode_payload(payload):
    if len(payload)!=PAYLOAD_BYTES: raise PacketError("UDP user length must be 8224")
    head,tag,channel,dtype,counter,tail=META.unpack_from(payload)
    if head!=HEAD or tail!=TAIL: raise PacketError("Metadata marker mismatch")
    if tag!=FORMAT_TAG or dtype!=16: raise PacketError("Unsupported candidate format/type")
    if channel>=8: raise PacketError("Channel outside one board's 0..7 range")
    samples=tuple(struct.iter_unpack("<hh",payload[META.size:]))
    return channel,counter,samples


@dataclass(frozen=True)
class Packet:
    src_mac: str
    src_ip: str
    src_port: int
    dst_ip: str
    dst_port: int
    channel: int
    counter: int
    samples: tuple
    ignored_trailer_bytes: int
    udp_checksum_present: bool

    @property
    def flow_key(self): return self.src_mac,self.src_ip,self.src_port,self.channel


def encode_frame(samples,channel,counter,source=0,padding=54,udp_checksum=False):
    """Synthetic Ethernet/IPv4/UDP frame, no FCS; RFC documentation IP range."""
    if source not in (0,1) or padding<0: raise ValueError("Invalid fixture source/padding")
    payload=encode_payload(samples,channel,counter)
    src=ipaddress.IPv4Address(f"192.0.2.{10+source}").packed
    dst=ipaddress.IPv4Address("192.0.2.100").packed
    udp=struct.pack("!HHHH",4000,4001,len(payload)+8,0)
    if udp_checksum:
        pseudo=src+dst+struct.pack("!BBH",0,17,len(payload)+8)
        udp=udp[:6]+struct.pack("!H",checksum(pseudo+udp+payload) or 0xffff)
    ip=struct.pack("!BBHHHBBH4s4s",0x45,0,len(payload)+28,0,0x4000,64,17,0,src,dst)
    ip=ip[:10]+struct.pack("!H",checksum(ip))+ip[12:]
    eth=bytes.fromhex("0200000000ff")+bytes([2,0,0,0,0,10+source])+b"\x08\x00"
    return eth+ip+udp+payload+b"\xa5"*padding


def decode_frame(frame):
    if len(frame)<42: raise PacketError("Truncated Ethernet/IPv4/UDP")
    if frame[12:14]!=b"\x08\x00": raise PacketError("Candidate profile requires untagged IPv4")
    ip=frame[14:34]
    version,total,fragment,protocol=ip[0],struct.unpack_from("!H",ip,2)[0],struct.unpack_from("!H",ip,6)[0],ip[9]
    if version!=0x45: raise PacketError("Candidate requires IPv4 without options")
    if fragment&0xbfff: raise PacketError("Fragmented/reserved IPv4 packet unsupported")
    if protocol!=17: raise PacketError("Not UDP")
    if checksum(ip)!=0: raise PacketError("Bad IPv4 header checksum")
    if total!=20+8+PAYLOAD_BYTES: raise PacketError("Unexpected IPv4 total length")
    if len(frame)<14+total: raise PacketError("Truncated IP datagram")
    udp=frame[34:14+total]
    sp,dp,length,csum=struct.unpack_from("!HHHH",udp)
    if length!=len(udp): raise PacketError("UDP/IP length mismatch")
    if csum and checksum(ip[12:20]+struct.pack("!BBH",0,17,length)+udp)!=0:
        raise PacketError("Bad nonzero UDP checksum")
    channel,counter,samples=decode_payload(udp[8:])
    return Packet(frame[6:12].hex(":"),str(ipaddress.IPv4Address(ip[12:16])),sp,
                  str(ipaddress.IPv4Address(ip[16:20])),dp,channel,counter,samples,
                  len(frame)-(14+total),bool(csum))


class SequenceTracker:
    """Conservative delivery order: late packets are reported, not recovered.

    A forward gap is a missing-at-delivery slot, not proof of physical loss.
    Recreate this object for an explicitly declared new acquisition session.
    """
    def __init__(self,history=1024): self.flows={}; self.history=history

    def observe(self,packet):
        key=packet.flow_key; count=packet.counter; gap=0
        if key not in self.flows:
            state={"expected":(count+1)&((1<<64)-1),"seen":OrderedDict()}
            self.flows[key]=state; status="first"
        else:
            state=self.flows[key]
            delta=(count-state["expected"])&((1<<64)-1)
            if count in state["seen"]: status="duplicate"
            elif delta==0: status="in_order"; state["expected"]=(count+1)&((1<<64)-1)
            elif delta<1<<63:
                status="gap"; gap=delta; state["expected"]=(count+1)&((1<<64)-1)
            else: status="late"
        state["seen"][count]=None
        if len(state["seen"])>self.history: state["seen"].popitem(last=False)
        return {"status":status,"accepted":status in ("first","in_order","gap"),"gap_before":gap}


def write_pcap(path,frames):
    with Path(path).open("wb") as out:
        out.write(struct.pack("<IHHIIII",0xa1b2c3d4,2,4,0,0,65535,1))
        for n,frame in enumerate(frames):
            # Synthetic host-arrival timestamps, unrelated to ADC sample time.
            out.write(struct.pack("<IIII",n//1000000,n%1000000,len(frame),len(frame))); out.write(frame)


def read_pcap(path):
    with Path(path).open("rb") as stream:
        hdr=stream.read(24)
        if len(hdr)!=24: raise PacketError("Truncated PCAP header")
        endian={b"\xd4\xc3\xb2\xa1":"<",b"\xa1\xb2\xc3\xd4":">"}.get(hdr[:4])
        if endian is None: raise PacketError("Use classic microsecond PCAP, not PCAPNG")
        _,major,minor,_,_,snaplen,linktype=struct.unpack(endian+"IHHIIII",hdr)
        if (major,minor,linktype)!=(2,4,1): raise PacketError("Expected PCAP 2.4 Ethernet")
        while True:
            record=stream.read(16)
            if not record: break
            if len(record)!=16: raise PacketError("Truncated PCAP record header")
            _,_,included,original=struct.unpack(endian+"IIII",record)
            if included!=original or included>snaplen: raise PacketError("Truncated/invalid PCAP snapshot")
            frame=stream.read(included)
            if len(frame)!=included: raise PacketError("Truncated PCAP frame")
            yield frame
