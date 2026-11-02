import ctypes as ct
from pathlib import Path
import struct
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'scripts'))
from xdma_bounded_retry import GuardedBar, RetestFile, PendingIoRetained, RETAINED, retest
from pcie_pattern import packet
from test_xdma_windows import FakeEndpoint


class ClosingEndpoint(FakeEndpoint):
    def close(self):
        self.closed = True


class PendingApi:
    def __init__(self, acknowledged):
        self.buffer = ct.create_string_buffer(4096)
        self.waits = iter((258, 0 if acknowledged else 258))
        self.freed = 0
        self.result_waits = []
    def VirtualAlloc(self, *args): return ct.addressof(self.buffer)
    def VirtualFree(self, *args): self.freed += 1
    def ResetEvent(self, *args): return True
    def ReadFile(self, *args): ct.set_last_error(997); return False
    def WaitForSingleObject(self, *args): return next(self.waits)
    def CancelIoEx(self, *args): return True
    def GetOverlappedResult(self, handle, op, actual, wait):
        self.result_waits.append(wait)
        ct.set_last_error(995)
        return False


class BoundedRetry(unittest.TestCase):
    def tearDown(self):
        RETAINED.clear()  # Fake requests only; never applied to real I/O.

    def test_original_crash_and_other_invalid_accesses_never_open_transport(self):
        calls = []
        bar = GuardedBar(lambda: calls.append('OPEN'))
        for offset, size in ((0x1000, 4), (0xfff, 4), (-1, 4), (0, 0),
                             ((1 << 64)-4, 8), (0xffc, 4), (1, 4)):
            with self.subTest(offset=offset, size=size), self.assertRaises(ValueError):
                bar.access(offset, size)
        for offset, value in ((0x1000, 0), (0, 1), (8, 3), (16, 4096), (24, 0)):
            with self.subTest(write=offset, value=value), self.assertRaises(ValueError):
                bar.write32(offset, value)
        self.assertEqual(calls, [])

    def test_identity_busy_and_link_fail_before_dma_open_or_control_write(self):
        for endpoint in (ClosingEndpoint(magic=0), ClosingEndpoint(busy=True), ClosingEndpoint()):
            if endpoint.reg[0] == 0x35445846 and endpoint.reg[12] == 16:
                endpoint.reg[12] = 0
            calls = []
            with self.assertRaises(RuntimeError):
                retest(GuardedBar(lambda: endpoint), lambda: calls.append('DMA_OPEN'))
            self.assertEqual(endpoint.writes, [])
            self.assertEqual(calls, [])

    def test_finite_short_reads_match_literal_contract_and_budget(self):
        endpoint = ClosingEndpoint()
        trace = []
        data, result = retest(GuardedBar(lambda: endpoint), lambda: endpoint,
                              lambda event, **kw: trace.append((event, kw)))
        self.assertEqual(data, packet(0, 2, 1, 0x10203040)+packet(1, 2, 1, 0x10203040))
        self.assertEqual(result, {'packets': 2, 'bytes': 8192, 'signature': '0556ac08'})
        self.assertEqual(endpoint.writes, [(8, 2), (16, 2), (20, 1), (24, 0x10203040), (8, 1)])
        self.assertFalse(getattr(endpoint, 'closed', False))
        self.assertLessEqual(sum(e == 'c2h_request' for e, _ in trace), 64)
        self.assertTrue(all(kw['offset'] == 0 and kw['size'] <= 4096
                            for e, kw in trace if e == 'c2h_request'))

    def test_bad_pattern_and_excessive_and_empty_results_stop(self):
        for mode in ('corrupt', 'excess', 'empty', 'tiny'):
            endpoint = ClosingEndpoint()
            class BadData:
                def read(self, offset, size):
                    if mode == 'excess': return b'X'*(size+1)
                    if mode == 'empty': return b''
                    if mode == 'tiny': return b'X'
                    return b'X'*size
                def close(self): pass
            with self.subTest(mode=mode), self.assertRaises((RuntimeError, ValueError)):
                retest(GuardedBar(lambda: endpoint), BadData)

    def test_counter_mismatch_stops(self):
        endpoint = ClosingEndpoint()
        original = endpoint.read
        endpoint.read = lambda off, size: struct.pack('<I', 999) if off == 28 else original(off, size)
        with self.assertRaisesRegex(RuntimeError, 'counters'):
            retest(GuardedBar(lambda: endpoint), lambda: endpoint)

    def transport_with_api(self, acknowledged):
        file = RetestFile.__new__(RetestFile)
        file.api = PendingApi(acknowledged)
        file.handle, file.event, file.timeout_ms, file.pending = 123, 456, 5000, None
        return file

    def test_unacknowledged_cancel_retains_buffer_and_prevents_close_and_io(self):
        file = self.transport_with_api(False)
        with self.assertRaises(PendingIoRetained): file.read(0, 4)
        self.assertIsNotNone(file.pending)
        self.assertIn(file, RETAINED)
        self.assertEqual(file.api.freed, 0)
        with self.assertRaises(PendingIoRetained): file.close()
        with self.assertRaises(PendingIoRetained): file.read(0, 4)

    def test_acknowledged_cancel_frees_only_after_completion_and_never_wait_true(self):
        file = self.transport_with_api(True)
        with self.assertRaises(TimeoutError): file.read(0, 4)
        self.assertIsNone(file.pending)
        self.assertEqual(file.api.freed, 1)
        self.assertEqual(file.api.result_waits, [False])

    def test_actual_safe_transport_ordinary_file_only(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'ordinary.bin'
            path.write_bytes(b'\0'*8192)
            with RetestFile(path) as file:
                data = bytes(range(256))*16
                file.write(0, data)
                self.assertEqual(file.read(0, 4096), data)
                self.assertEqual(file.read(4096, 4), b'\0'*4)


if __name__ == '__main__': unittest.main()
