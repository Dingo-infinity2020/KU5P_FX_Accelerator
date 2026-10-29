import struct
from pathlib import Path
import sys
import tempfile
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"scripts"))
from rfsoc_packet_candidate import (PacketError,SequenceTracker,checksum,decode_frame,decode_payload,
    encode_frame,encode_payload,read_pcap,write_pcap)
from prepare_rfsoc_fixtures import samples
from inspect_rfsoc_pcap import inspect


class CandidatePackets(unittest.TestCase):
    def test_literal_metadata_and_signed_iq_bytes(self):
        data=[(1,-2),(-32768,32767)]+[(0,0)]*2046
        payload=encode_payload(data,5,0x0102030405060708)
        self.assertEqual(payload[:32].hex(),"55aa55aa44332211050000001000000008070605040302011122334455aa55aa")
        self.assertEqual(payload[32:40].hex(),"0100feff0080ff7f")
        self.assertEqual(decode_payload(payload),(5,0x0102030405060708,tuple(data)))

    def test_known_ipv4_checksum(self):
        self.assertEqual(checksum(bytes.fromhex("450000730000400040110000c0a80001c0a800c7")),0xb861)

    def test_padding_is_not_sampling_data(self):
        frame=encode_frame(samples(0,7,0),7,0)
        self.assertEqual(len(frame),8320)
        packet=decode_frame(frame)
        self.assertEqual(len(packet.samples),2048)
        self.assertEqual(packet.ignored_trailer_bytes,54)
        self.assertFalse(packet.udp_checksum_present)

    def test_optional_udp_checksum_detects_corruption(self):
        frame=encode_frame(samples(0,0,0),0,0,udp_checksum=True)
        self.assertTrue(decode_frame(frame).udp_checksum_present)
        damaged=bytearray(frame); damaged[80]^=1
        with self.assertRaisesRegex(PacketError,"UDP checksum"): decode_frame(damaged)

    def test_malformed_metadata_length_and_ip(self):
        frame=encode_frame(samples(0,0,0),0,0)
        for index in (42,46,50,54,66):
            bad=bytearray(frame); bad[index]^=0x80
            with self.assertRaises(PacketError): decode_frame(bad)
        with self.assertRaisesRegex(PacketError,"Truncated"): decode_frame(frame[:200])
        bad=bytearray(frame); bad[22]^=1
        with self.assertRaisesRegex(PacketError,"IPv4 header checksum"): decode_frame(bad)

    def test_duplicate_late_and_gap_are_distinct(self):
        tracker=SequenceTracker()
        events=[tracker.observe(decode_frame(encode_frame(samples(0,0,c),0,c))) for c in (0,2,1,2,3)]
        self.assertEqual([e["status"] for e in events],["first","gap","late","duplicate","in_order"])
        self.assertEqual([e["gap_before"] for e in events],[0,1,0,0,0])
        self.assertEqual(sum(e["accepted"] for e in events),3)

    def test_same_channel_on_two_sources_is_not_merged(self):
        tracker=SequenceTracker()
        for source in (0,1):
            self.assertEqual(tracker.observe(decode_frame(encode_frame(samples(source,0,0),0,0,source)))["status"],"first")
        self.assertEqual(len(tracker.flows),2)

    def test_uint64_wrap_and_explicit_new_session(self):
        tracker=SequenceTracker()
        for i,c in enumerate(((1<<64)-1,0,1)):
            packet=decode_frame(encode_frame(samples(0,0,c),0,c))
            self.assertEqual(tracker.observe(packet)["status"],"first" if i==0 else "in_order")
        packet=decode_frame(encode_frame(samples(0,0,0),0,0))
        self.assertEqual(SequenceTracker().observe(packet)["status"],"first")

    def test_pcap_and_report_counts(self):
        with tempfile.TemporaryDirectory(prefix="rfsoc-candidate-") as directory:
            p=Path(directory)/"test.pcap"
            frames=[encode_frame(samples(s,ch,c),ch,c,s) for c in range(2) for s in range(2) for ch in range(8)]
            write_pcap(p,frames)
            self.assertEqual(list(read_pcap(p)),frames)
            report=inspect(p)
            self.assertEqual((report["packets"],report["flows"],report["accepted_complex_samples"]),(32,16,65536))
            self.assertEqual(report["rejected"],{})
            self.assertFalse(report["rf_hardware_validated"])
            p.write_bytes(p.read_bytes()[:-1])
            with self.assertRaisesRegex(PacketError,"Truncated PCAP"): list(read_pcap(p))


if __name__=="__main__": unittest.main()
