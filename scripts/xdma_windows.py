"""Windows user-mode client for the conventional XDMA user/c2h_0 nodes.

Requires an installed compatible driver; never installs a driver or changes
boot settings. The interface path must be provided explicitly. Real hardware
validation is separate from the ordinary-file transport and fake-device tests.
"""
import argparse
import ctypes as ct
from ctypes import wintypes as wt
import json
import os
from pathlib import Path
import struct
import time
from pcie_pattern import MAGIC,verify


class Overlapped(ct.Structure):
    _fields_=[('Internal',ct.c_size_t),('InternalHigh',ct.c_size_t),
              ('Offset',wt.DWORD),('OffsetHigh',wt.DWORD),('hEvent',wt.HANDLE)]


class WindowsFile:
    """Page-aligned, serialized overlapped I/O. Also testable with ordinary files."""
    def __init__(self,path,timeout_ms=5000):
        if os.name!='nt':raise RuntimeError('Windows transport requires Windows')
        if not 1<=timeout_ms<=60000:raise ValueError('Timeout must be 1..60000 ms')
        self.timeout_ms=timeout_ms;self.api=ct.WinDLL('kernel32',use_last_error=True)
        definitions={
            'CreateFileW':([wt.LPCWSTR,wt.DWORD,wt.DWORD,ct.c_void_p,wt.DWORD,wt.DWORD,wt.HANDLE],wt.HANDLE),
            'CreateEventW':([ct.c_void_p,wt.BOOL,wt.BOOL,wt.LPCWSTR],wt.HANDLE),
            'CloseHandle':([wt.HANDLE],wt.BOOL),'ResetEvent':([wt.HANDLE],wt.BOOL),
            'WaitForSingleObject':([wt.HANDLE,wt.DWORD],wt.DWORD),
            'VirtualAlloc':([ct.c_void_p,ct.c_size_t,wt.DWORD,wt.DWORD],ct.c_void_p),
            'VirtualFree':([ct.c_void_p,ct.c_size_t,wt.DWORD],wt.BOOL),
            'ReadFile':([wt.HANDLE,ct.c_void_p,wt.DWORD,ct.POINTER(wt.DWORD),ct.POINTER(Overlapped)],wt.BOOL),
            'WriteFile':([wt.HANDLE,ct.c_void_p,wt.DWORD,ct.POINTER(wt.DWORD),ct.POINTER(Overlapped)],wt.BOOL),
            'GetOverlappedResult':([wt.HANDLE,ct.POINTER(Overlapped),ct.POINTER(wt.DWORD),wt.BOOL],wt.BOOL),
            'CancelIoEx':([wt.HANDLE,ct.POINTER(Overlapped)],wt.BOOL),
        }
        for name,(args,result) in definitions.items():
            fn=getattr(self.api,name);fn.argtypes=args;fn.restype=result
        self.handle=self.api.CreateFileW(str(path),0xc0000000,3,None,3,0x40000000,None)
        if self.handle==ct.c_void_p(-1).value:raise ct.WinError(ct.get_last_error())
        self.event=self.api.CreateEventW(None,True,False,None)
        if not self.event:
            error=ct.get_last_error();self.api.CloseHandle(self.handle);raise ct.WinError(error)
    def close(self):
        if self.handle is not None:
            self.api.CloseHandle(self.handle);self.api.CloseHandle(self.event);self.handle=None
    def __enter__(self):return self
    def __exit__(self,*args):self.close()
    def _transfer(self,offset,size,data=None):
        if not 0<=offset<1<<64 or not 0<size<=16*1024*1024:raise ValueError('Invalid I/O range')
        address=self.api.VirtualAlloc(None,size,0x3000,4)
        if not address:raise ct.WinError(ct.get_last_error())
        operation=Overlapped(0,0,offset&0xffffffff,offset>>32,self.event);actual=wt.DWORD()
        try:
            if data is not None:ct.memmove(address,data,size)
            self.api.ResetEvent(self.event)
            fn=self.api.ReadFile if data is None else self.api.WriteFile
            success=fn(self.handle,address,size,None,ct.byref(operation))
            if not success:
                error=ct.get_last_error()
                if error!=997:raise ct.WinError(error)
                status=self.api.WaitForSingleObject(self.event,self.timeout_ms)
                if status!=0:
                    self.api.CancelIoEx(self.handle,ct.byref(operation))
                    # Drain cancellation before releasing the OVERLAPPED or DMA
                    # buffer. A compatible driver must complete cancellation.
                    self.api.GetOverlappedResult(self.handle,ct.byref(operation),ct.byref(actual),True)
                    if status==258:raise TimeoutError('XDMA I/O timeout (cancellation drained)')
                    raise ct.WinError(ct.get_last_error())
            if not self.api.GetOverlappedResult(self.handle,ct.byref(operation),ct.byref(actual),False):
                raise ct.WinError(ct.get_last_error())
            if actual.value>size:raise RuntimeError('Driver returned excessive byte count')
            return ct.string_at(address,actual.value) if data is None else actual.value
        finally:self.api.VirtualFree(address,0,0x8000)
    def read(self,offset,size):return self._transfer(offset,size)
    def write(self,offset,data):
        if self._transfer(offset,len(data),bytes(data))!=len(data):raise RuntimeError('Short driver write')


def read32(device,offset):
    data=device.read(offset,4)
    if len(data)!=4:raise RuntimeError('Short register read')
    return struct.unpack('<I',data)[0]


def capture(user,c2h,packets,run_id,seed):
    if not 1<=packets<=4096 or not 0<=run_id<1<<32 or not 0<=seed<1<<32:raise ValueError('Invalid test configuration')
    identity=(read32(user,0),read32(user,4),read32(user,0x30),read32(user,0x34))
    if identity!=(MAGIC,1,0x465805d1,4096):raise RuntimeError('Endpoint identity mismatch; no control writes issued')
    status=read32(user,12)
    if not status&16:raise RuntimeError('PCIe link is not up')
    if status&1:raise RuntimeError('Endpoint is busy; existing run left untouched')
    for offset,value in ((8,2),(16,packets),(20,run_id),(24,seed),(8,1)):
        user.write(offset,struct.pack('<I',value))
    started=time.perf_counter();data=bytearray()
    for index in range(packets):
        packet_data=bytearray()
        while len(packet_data)<4096:
            part=c2h.read(0,4096-len(packet_data))
            if not part:raise RuntimeError(f'Empty C2H completion in packet {index}')
            packet_data+=part
        data+=packet_data
    deadline=time.monotonic()+5
    while True:
        status=read32(user,12)
        if status&2 and not status&1:break
        if time.monotonic()>deadline:raise TimeoutError('Endpoint did not report done')
        time.sleep(0.01)
    elapsed=time.perf_counter()-started
    result=verify(bytes(data),packets,run_id,seed)
    counts=(read32(user,28),read32(user,32),read32(user,36))
    if counts!=(packets*128,packets,int(result['signature'],16)):raise RuntimeError('Endpoint counters/signature mismatch')
    result.update(run_id=run_id,seed=seed,elapsed_seconds=elapsed,
        scope='finite known-pattern driver readback; not sustained PCIe bandwidth measurement')
    return bytes(data),result


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--device-interface',required=True,help='Explicit XDMA interface base path, without a node suffix')
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--packets',type=int,default=2);p.add_argument('--run-id',type=lambda s:int(s,0),default=1)
    p.add_argument('--seed',type=lambda s:int(s,0),default=0x10203040)
    p.add_argument('--timeout-ms',type=int,default=5000)
    a=p.parse_args();root=Path(__file__).resolve().parents[1];out=a.output.resolve()
    if out==root or root in out.parents:p.error('Store capture outside repository')
    if not a.device_interface.startswith('\\\\?\\'):p.error('Expected an explicit Windows device interface path')
    base=a.device_interface.rstrip('\\')
    with WindowsFile(base+'\\user',a.timeout_ms) as user,WindowsFile(base+'\\c2h_0',a.timeout_ms) as c2h:
        data,result=capture(user,c2h,a.packets,a.run_id,a.seed)
    out.parent.mkdir(parents=True,exist_ok=True);out.write_bytes(data)
    result['host_driver_readback_completed']=True
    out.with_suffix(out.suffix+'.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result))


if __name__=='__main__':main()
