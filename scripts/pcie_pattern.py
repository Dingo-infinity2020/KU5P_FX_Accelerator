"""Independent byte contract for authored XDMA test packets; not RFSoC data."""
import struct

MAGIC=0x35445846
PACKET_BYTES=4096


def packet(index,count,run_id,seed):
    header=struct.pack('<8I',MAGIC,1,run_id,index,count,PACKET_BYTES,seed,0)
    body=struct.pack('<1016I',*((seed+index*1024+w)&0xffffffff for w in range(8,1024)))
    return header+body


def signature(data):
    value=0
    for base in range(0,len(data),32):
        folded=0
        for k,w in enumerate(struct.unpack('<8I',data[base:base+32])):
            shift=k+1
            folded^=((w<<shift)|(w>>(32-shift)))&0xffffffff
        value=(((value<<1)|(value>>31))^folded)&0xffffffff
    return value


def verify(data,count,run_id,seed):
    if len(data)!=count*PACKET_BYTES:raise ValueError('Unexpected capture length')
    for index in range(count):
        actual=data[index*PACKET_BYTES:(index+1)*PACKET_BYTES]
        expected=packet(index,count,run_id,seed)
        if actual!=expected:
            offset=next(i for i,(a,b) in enumerate(zip(actual,expected)) if a!=b)
            raise ValueError(f'Packet {index}, byte {offset}: expected {expected[offset]:02x}, got {actual[offset]:02x}')
    return {'packets':count,'bytes':len(data),'signature':f'{signature(data):08x}'}
