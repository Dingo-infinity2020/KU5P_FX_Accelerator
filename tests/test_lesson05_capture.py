"""Reject incomplete/corrupt hardware captures instead of hiding bad samples."""
import csv
from pathlib import Path
import sys
import tempfile
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"scripts"))
from check_lesson05_hardware import parse_capture


class CaptureParsing(unittest.TestCase):
    def parse(self,valid="1",meta="deadbeef"):
        with tempfile.TemporaryDirectory(prefix="lesson05-capture-") as directory:
            p=Path(directory)/"capture.csv"
            cross=(0x123<<64)|((1<<64)-9)
            with p.open("w",newline="",encoding="utf-8") as stream:
                w=csv.writer(stream)
                w.writerow(["Sample in Buffer","Sample in Window","TRIGGER","debug_valid",
                            "debug_meta[393:0]","debug_auto_a[63:0]","debug_auto_b[63:0]","debug_cross[127:0]"])
                w.writerow(["Radix - UNSIGNED","UNSIGNED","UNSIGNED","HEX","HEX","HEX","HEX","HEX"])
                w.writerow([0,0,1,valid,meta,"7f","aa",f"{cross:032x}"])
            return list(parse_capture(p))

    def test_wide_bus_and_negative_imaginary_bit_pattern(self):
        expected=(0x7f<<586)|(0xaa<<522)|(0x123<<458)|(((1<<64)-9)<<394)|0xdeadbeef
        self.assertEqual(self.parse(),[expected])

    def test_unknown_bits_are_rejected(self):
        with self.assertRaises(AssertionError): self.parse(meta="deadbeex")

    def test_invalid_rows_are_rejected_instead_of_skipped(self):
        with self.assertRaises(AssertionError): self.parse(valid="0")

    def test_probe_overflow_is_rejected_instead_of_truncated(self):
        with self.assertRaises(AssertionError): self.parse(valid="3")


if __name__=="__main__": unittest.main()
