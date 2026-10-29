from pathlib import Path
import sys,unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from check_gt_isolation import decode,heartbeat_bounds

class GTIsolationTest(unittest.TestCase):
    def test_layout_separates_qpll_reset_and_powergood(self):
        fields=decode(15|(1<<4)|(1<<25)|(1<<29))
        self.assertTrue(fields['qpll1lock']);self.assertTrue(fields['monitor_mmcm_locked'])
        self.assertTrue(all(fields['raw_gt_powergood'].values()))
        self.assertEqual(fields['txpmaresetdone'],0);self.assertIsNone(fields['txresetdone'])
        self.assertFalse(fields['reset_all']);self.assertFalse(fields['manual_reset'])

    def test_host_rate_bracket_handles_counter_wrap(self):
        first=0xfffffff0;last=(first+200_000_000)&0xffffffff
        rows=[dict(heartbeat_hex=f'{first:08x}',refresh_start_us=0,refresh_end_us=1000),
              dict(heartbeat_hex=f'{last:08x}',refresh_start_us=2_000_000,refresh_end_us=2_001_000)]
        result=heartbeat_bounds(rows)
        self.assertLess(result['min_mhz'],100);self.assertGreater(result['max_mhz'],100)
        self.assertLess(result['max_mhz'],101)

    def test_stale_heartbeat_does_not_claim_a_frequency(self):
        rows=[dict(heartbeat_hex='00000001',refresh_start_us=0,refresh_end_us=1),
              dict(heartbeat_hex='00000001',refresh_start_us=100,refresh_end_us=101)]
        with self.assertRaises(AssertionError):heartbeat_bounds(rows)

if __name__=='__main__':unittest.main()
