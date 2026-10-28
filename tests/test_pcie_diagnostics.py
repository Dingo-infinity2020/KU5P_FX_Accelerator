import hashlib
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'scripts'))
from check_pcie_clock_capture import measure
from check_pcie_phy import decode
from pcie_evidence import verify_sources


class DiagnosticsTest(unittest.TestCase):
    def test_clock_ratios_and_stopped_source(self):
        values=[(i//128%2)|((int(i*1.25)//128%2)<<1) for i in range(4096)]
        self.assertEqual(measure(values,0)['frequency_mhz_relative_to_nominal_sysclk'],100)
        self.assertAlmostEqual(measure(values,1)['frequency_mhz_relative_to_nominal_sysclk'],125,delta=0.05)
        self.assertIsNone(measure([0]*4096,0)['frequency_mhz_relative_to_nominal_sysclk'])

    def test_irregular_edges_do_not_claim_a_clock_frequency(self):
        levels=[]
        for period in (100,300,80,400,120):
            levels.extend([0]*(period//2)+[1]*(period-period//2))
        result=measure(levels,0)
        self.assertFalse(result['stable_periods_observed'])
        self.assertIsNone(result['frequency_mhz_relative_to_nominal_sysclk'])

    def test_raw_power_bits_do_not_contaminate_legacy_fields(self):
        value=sum(1<<b for b in (16,17,18,19,26,29))
        fields=decode(value,raw_power=True)
        self.assertTrue(all(fields['raw_gt_powergood'].values()))
        self.assertEqual(fields['ip_power_on'],1)
        self.assertEqual(fields['qpll_locks'],0)
        self.assertEqual(fields['phy_reset_flags'],2)

    def test_source_archive_fallback_requires_exact_digest(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)/'root';out=Path(directory)/'out'
            root.mkdir();(out/'source_snapshot').mkdir(parents=True)
            (root/'source.tcl').write_bytes(b'new')
            saved=out/'source_snapshot/source.tcl';saved.write_bytes(b'old')
            expected={'source.tcl':hashlib.sha256(b'old').hexdigest()}
            self.assertEqual(verify_sources(out,root,expected),{'source.tcl':'source_snapshot'})
            saved.write_bytes(b'corrupt')
            with self.assertRaises(AssertionError):verify_sources(out,root,expected)


if __name__=='__main__':unittest.main()
