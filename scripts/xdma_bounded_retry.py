"""One legacy-driver positive retest. No install, reboot, arbitrary BAR CLI or H2C.

Only run after the documented host/image/driver baseline gates have passed.
An uncompleted cancellation enters HOLD with resources retained until recovery;
this is not a guarantee against a blocked kernel API or system crash.
"""
import argparse
import ctypes as ct
from ctypes import wintypes as wt
import json
from pathlib import Path
import struct
import threading
import time
from xdma_windows import WindowsFile, Overlapped
from pcie_pattern import verify

BAR_SIZE = 0x1000
RUN_ID = 1
SEED = 0x10203040
READS = frozenset((0, 4, 12, 0x30, 0x34, 0x1c, 0x20, 0x24))
WRITES = {8: (1, 2), 16: (2,), 20: (RUN_ID,), 24: (SEED,)}
RETAINED = []


class PendingIoRetained(RuntimeError):
    pass


def check_bar(offset, size, data=None):
    if (type(offset) is not int or type(size) is not int or offset < 0 or
            size <= 0 or offset > BAR_SIZE or size > BAR_SIZE - offset):
        raise ValueError('BAR range rejected before transport access')
    if size != 4 or offset % 4:
        raise ValueError('Only aligned four-byte registers are allowed')
    if data is None:
        if offset not in READS:
            raise ValueError('BAR read is outside retest whitelist')
    elif (offset not in WRITES or len(data) != 4 or
          struct.unpack('<I', data)[0] not in WRITES[offset]):
        raise ValueError('BAR write/value is outside retest whitelist')


class GuardedBar:
    """Validate before a lazy factory can even open the device."""
    def __init__(self, factory, audit=lambda *args, **kwargs: None):
        self.factory, self.audit, self.transport = factory, audit, None

    def access(self, offset, size, data=None):
        check_bar(offset, size, data)
        self.audit('bar_request', offset=offset, size=size,
                   value=None if data is None else struct.unpack('<I', data)[0])
        if self.transport is None:
            self.transport = self.factory()
        if data is None:
            result = self.transport.read(offset, size)
            if len(result) != size:
                raise RuntimeError('Short BAR read')
            self.audit('bar_read_complete', offset=offset,
                       value=struct.unpack('<I', result)[0])
            return result
        self.transport.write(offset, data)
        self.audit('bar_write_complete', offset=offset)

    def read32(self, offset):
        return struct.unpack('<I', self.access(offset, 4))[0]

    def write32(self, offset, value):
        self.access(offset, 4, struct.pack('<I', value))

    def close(self):
        if self.transport is not None:
            self.transport.close()


class RetestFile(WindowsFile):
    """Serialized overlapped I/O with bounded cancellation acknowledgement."""
    def __init__(self, path):
        super().__init__(path, timeout_ms=5000)
        self.pending = None

    def close(self):
        if self.pending is not None:
            raise PendingIoRetained('HOLD: no handle close while I/O is unacknowledged')
        super().close()

    def _transfer(self, offset, size, data=None):
        if self.pending is not None:
            raise PendingIoRetained('HOLD: further I/O prohibited')
        if (type(offset) is not int or type(size) is not int or not 0 <= offset < 1 << 64 or
                not 0 < size <= 4096 or (data is not None and len(data) != size)):
            raise ValueError('Retest transport range rejected')
        address = self.api.VirtualAlloc(None, size, 0x3000, 4)
        if not address:
            raise ct.WinError(ct.get_last_error())
        op = Overlapped(0, 0, offset & 0xffffffff, offset >> 32, self.event)
        actual = wt.DWORD()
        submitted = False
        complete = False
        try:
            if data is not None:
                ct.memmove(address, data, size)
            if not self.api.ResetEvent(self.event):
                raise ct.WinError(ct.get_last_error())
            fn = self.api.ReadFile if data is None else self.api.WriteFile
            submitted = True
            success = fn(self.handle, address, size, None, ct.byref(op))
            if not success:
                error = ct.get_last_error()
                if error != 997:
                    complete = True  # Submission rejected, no pending request.
                    raise ct.WinError(error)
                wait = self.api.WaitForSingleObject(self.event, self.timeout_ms)
                if wait != 0:
                    # Cancellation is a request, not evidence of completion.
                    self.api.CancelIoEx(self.handle, ct.byref(op))
                    acknowledged = self.api.WaitForSingleObject(self.event, 2000)
                    if acknowledged != 0:
                        raise PendingIoRetained('HOLD: cancellation not acknowledged')
                    ok = self.api.GetOverlappedResult(self.handle, ct.byref(op), ct.byref(actual), False)
                    error = 0 if ok else ct.get_last_error()
                    if error in (996, 997):
                        raise PendingIoRetained('HOLD: completion still pending')
                    complete = True
                    raise TimeoutError('Retest stopped after deadline; completion acknowledged')
            ok = self.api.GetOverlappedResult(self.handle, ct.byref(op), ct.byref(actual), False)
            error = 0 if ok else ct.get_last_error()
            if error in (996, 997):
                raise PendingIoRetained('HOLD: unexpected incomplete result')
            complete = True
            if not ok:
                raise ct.WinError(error)
            if actual.value > size:
                raise RuntimeError('Driver returned excessive byte count')
            return ct.string_at(address, actual.value) if data is None else actual.value
        finally:
            if submitted and not complete:
                # Keep every object alive; neither close nor another request is safe.
                self.pending = (address, op, actual)
                RETAINED.append(self)
            else:
                self.api.VirtualFree(address, 0, 0x8000)


def retest(bar, c2h_factory, audit=lambda *args, **kwargs: None):
    identity = tuple(bar.read32(off) for off in (0, 4, 12, 0x30, 0x34))
    if identity[:2] != (0x35445846, 1) or identity[3:] != (0x465805d1, 4096):
        raise RuntimeError('Identity mismatch: no source writes issued')
    if not identity[2] & 16 or identity[2] & 1:
        raise RuntimeError('Link down or busy: no source writes issued')
    c2h = c2h_factory()
    finished = False
    try:
        for off, value in ((8, 2), (16, 2), (20, RUN_ID), (24, SEED), (8, 1)):
            bar.write32(off, value)
        data = bytearray()
        for index in range(64):
            if len(data) == 8192:
                break
            request = min(4096, 8192 - len(data))
            audit('c2h_request', index=index, offset=0, size=request)
            part = c2h.read(0, request)
            if not 0 < len(part) <= request:
                raise RuntimeError('Empty/excessive C2H completion')
            data.extend(part)
            audit('c2h_complete', index=index, bytes=len(part), total=len(data))
        if len(data) != 8192:
            raise RuntimeError('C2H request-count budget exhausted')
        result = verify(bytes(data), 2, RUN_ID, SEED)
        status, beats, packets, sig = (bar.read32(off) for off in (12, 28, 32, 36))
        if status & 0x13 != 0x12 or (beats, packets, sig) != (256, 2, int(result['signature'], 16)):
            raise RuntimeError('Completion status/counters/signature mismatch')
        finished = True
        return bytes(data), result
    finally:
        # Caller owns observation/close on normal completion; never close pending I/O.
        if not finished and c2h not in RETAINED:
            c2h.close()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--device-interface', required=True)
    p.add_argument('--evidence-dir', type=Path, required=True)
    a = p.parse_args()
    root = Path(__file__).resolve().parents[1]
    out = a.evidence_dir.resolve()
    if out == root or root in out.parents or not out.is_dir():
        p.error('Use a pre-created evidence directory outside source')
    base = a.device_interface.rstrip('\\')
    if not base.startswith('\\\\?\\') or not base.lower().endswith('#{74c7e4a9-6d5d-4a70-bc0d-20691dff9e9d}'):
        p.error('Expected explicit XDMA base interface path')
    with (out/'attempt-consumed.json').open('x') as f:
        json.dump({'interface': base, 'scope': 'one 8192-byte C2H attempt'}, f)
    log = (out/'operations.jsonl').open('x', buffering=1)
    def audit(event, **kwargs):
        log.write(json.dumps({'event': event, 'monotonic': time.monotonic(), **kwargs})+'\n')
    bar = GuardedBar(lambda: RetestFile(base+'\\user'), audit)
    opened = []
    def open_c2h():
        transport = RetestFile(base+'\\c2h_0')
        opened.append(transport)
        return transport
    try:
        data, result = retest(bar, open_c2h, audit)
        (out/'capture.bin').write_bytes(data)
        (out/'result.json').write_text(json.dumps(result, indent=2)+'\n')
        audit('functional_pass_observe_60_seconds')
        time.sleep(60)
        for transport in opened:
            transport.close()
        bar.close()
        audit('handles_closed_observe_60_seconds')
        time.sleep(60)
        audit('bounded_run_complete_not_driver_acceptance')
    except BaseException as error:
        audit('STOP', error=repr(error), retained=bool(RETAINED))
        if RETAINED:
            print('HOLD_PENDING_IO: resources retained; manual recovery required. Do not kill this process.', flush=True)
            while True:
                try:
                    threading.Event().wait(30)
                except KeyboardInterrupt:
                    print('HOLD retained; use the documented host recovery procedure.', flush=True)
        raise
    finally:
        if not RETAINED:
            for transport in opened:
                transport.close()
            bar.close()
            log.close()


if __name__ == '__main__':
    main()
