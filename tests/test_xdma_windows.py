from pathlib import Path
import os
import struct
import sys
import tempfile
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from pcie_pattern import packet,signature,verify
from xdma_windows import WindowsFile,capture


class FakeEndpoint:
    def __init__(self,magic=0x35445846,busy=False):
        self.reg={0:magic,4:1,0x30:0x465805d1,0x34:4096,12:17 if busy else 16}
        self.writes=[];self.data=b''
    def read(self,offset,size):
        if size==4 and offset in self.reg:return struct.pack('<I',self.reg[offset])
        # Deliberate short read exercises capture reassembly.
        result=self.data[:min(size,137)];self.data=self.data[len(result):];return result
    def write(self,offset,data):
        value=struct.unpack('<I',data)[0];self.writes.append((offset,value));self.reg[offset]=value
        if offset==8 and value==1:
            count,rid,seed=(self.reg[n] for n in (16,20,24))
            self.data=b''.join(packet(i,count,rid,seed) for i in range(count))
            self.reg.update({12:18,28:count*128,32:count,36:signature(self.data)})


class WindowsClient(unittest.TestCase):
    def test_literal_header_and_wrapped_data(self):
        data=packet(0,1,0x01020304,0xfffffff0)
        self.assertEqual(data[:32].hex(),'465844350100000004030201000000000100000000100000f0ffffff00000000')
        self.assertEqual(struct.unpack_from('<I',data,64)[0],0)
        damaged=bytearray(data);damaged[900]^=1
        with self.assertRaisesRegex(ValueError,'byte 900'):verify(damaged,1,0x01020304,0xfffffff0)
        with self.assertRaisesRegex(ValueError,'length'):verify(data[:-1],1,0x01020304,0xfffffff0)
    def test_fake_driver_short_reads(self):
        endpoint=FakeEndpoint();data,result=capture(endpoint,endpoint,3,7,0xfffffff0)
        self.assertEqual(len(data),12288);self.assertEqual(result['packets'],3)
        self.assertEqual(endpoint.writes,[(8,2),(16,3),(20,7),(24,0xfffffff0),(8,1)])
    def test_identity_or_busy_guard_prevents_writes(self):
        for endpoint in (FakeEndpoint(magic=0),FakeEndpoint(busy=True)):
            with self.assertRaises(RuntimeError):capture(endpoint,endpoint,1,1,0)
            self.assertEqual(endpoint.writes,[])
    @unittest.skipUnless(os.name=='nt','Win32 transport test')
    def test_actual_win32_overlapped_io_on_ordinary_file(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'transport.bin';path.write_bytes(b'\0'*8192)
            with WindowsFile(path) as file:
                data=bytes(range(256))*16;file.write(4096,data)
                self.assertEqual(file.read(4096,4096),data)
                self.assertEqual(file.read(0,16),b'\0'*16)


if __name__=='__main__':unittest.main()
