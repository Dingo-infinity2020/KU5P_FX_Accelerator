"""Reject misleading startup evidence: wrong image, stale source and mixed epochs."""
import csv,tempfile,unittest
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from pcie_boot_capture import snapshot,event_files,raw

class StartupEvidenceFailures(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.path=Path(self.temp.name)/'capture.tsv'
    def rows(self):
        result=[]
        for i in range(2):
            m=(100+i*100)|(7<<64)|(2<<80)|(1<<91)
            result.append(dict(unix_ms=str(1000+i*200),index=str(i),build_hex='465805e4',
                raw_hex='800000000000000f',clocks_hex=f'{(1<<96)|i:032x}',
                training_hex='00000000000000000000000000000000',metadata_hex=f'{m:032x}'))
        return result
    def write(self,rows):
        with self.path.open('w',newline='') as h:
            w=csv.DictWriter(h,fieldnames=list(rows[0]),delimiter='\t');w.writeheader();w.writerows(rows)
    def test_negative_hardware_is_valid_observation(self):
        self.write(self.rows());s=snapshot(self.path)
        self.assertTrue(s['evidence_valid']);self.assertFalse(s['training_sequence_changes'])
        self.assertEqual(s['samples'][0]['raw']['groups']['cplllock'],0)
    def test_wrong_firmware_rejected(self):
        r=self.rows();r[1]['build_hex']='465805e0';self.write(r)
        with self.assertRaises(ValueError):snapshot(self.path)
    def test_frozen_independent_observer_rejected(self):
        r=self.rows();r[1]['metadata_hex']=r[0]['metadata_hex'];self.write(r)
        with self.assertRaises(ValueError):snapshot(self.path)
    def test_invalid_raw_observer_stays_unknown(self):
        s=raw((1<<63)-1)
        self.assertFalse(s['valid']);self.assertIsNone(s['groups']['cplllock']);self.assertIsNone(s['qpll1lock'])
    def event_rows(self):
        return [dict(index=str(i),epoch='7',event_hex=f'{100+i*100:064x}',
            metadata_hex=f'{1000|(7<<64)|(2<<80)|(1<<91):032x}') for i in range(2)]
    def test_mixed_epochs_rejected(self):
        r=self.event_rows();r[1]['epoch']='8';self.write(r)
        with self.assertRaises(ValueError):event_files([self.path])
    def test_invalid_ram_read_rejected(self):
        r=self.event_rows();r[0]['metadata_hex']=f'{(7<<64)|(2<<80):032x}';self.write(r)
        with self.assertRaises(ValueError):event_files([self.path])
    def test_missing_event_prefix_rejected(self):
        r=self.event_rows();r[1]['index']='3';self.write(r)
        with self.assertRaises(ValueError):event_files([self.path])
    def test_nonchronological_records_rejected(self):
        r=self.event_rows();r[1]['event_hex']=r[0]['event_hex'];self.write(r)
        with self.assertRaises(ValueError):event_files([self.path])

    def test_unbounded_words_have_unknown_provenance(self):
        self.write(self.event_rows());d=event_files([self.path])
        self.assertTrue(d['format_valid'])
        self.assertEqual(d['temporal_provenance']['status'],'UNKNOWN')
        self.assertEqual(d['temporal_provenance']['record_epoch_status'],'UNKNOWN_E4_WORD_HAS_NO_EPOCH')

    def test_bounded_capture_and_expected_count(self):
        self.write(self.event_rows())
        d=event_files([self.path],capture_start_cycles=100,previous_observed_cycles=99,
                      expected_epoch=7,expected_entries=2)
        self.assertEqual(d['temporal_provenance']['status'],'BOUNDED_TIME_PASS')

    def test_old_word_can_be_ordered_but_fails_provenance(self):
        self.write(self.event_rows());d=event_files([self.path],previous_observed_cycles=150)
        self.assertTrue(d['format_valid'])
        self.assertEqual(d['temporal_provenance']['status'],'FAIL')
        self.assertIn('EVENT_PREDATES_PREVIOUS_OBSERVATION',d['temporal_provenance']['reasons'])

    def test_start_mismatch_is_not_repaired(self):
        self.write(self.event_rows());d=event_files([self.path],capture_start_cycles=101)
        self.assertEqual(d['events'][0]['timestamp_cycles'],100)
        self.assertEqual(d['temporal_provenance']['status'],'FAIL')

    def test_previous_bound_is_strict(self):
        self.write(self.event_rows())
        self.assertEqual(event_files([self.path],previous_observed_cycles=100)['temporal_provenance']['status'],'FAIL')

    def test_lower_bound_does_not_prove_capture_identity(self):
        self.write(self.event_rows())
        self.assertEqual(event_files([self.path],previous_observed_cycles=50)['temporal_provenance']['status'],'LOWER_BOUND_ONLY')

    def test_future_event_rejected(self):
        r=self.event_rows();r[1]['event_hex']=f'{1001:064x}';self.write(r)
        with self.assertRaisesRegex(ValueError,'later than'):event_files([self.path])

    def test_wrong_expected_epoch_rejected(self):
        self.write(self.event_rows())
        with self.assertRaisesRegex(ValueError,'Unexpected'):event_files([self.path],expected_epoch=8)

    def test_expected_capture_cannot_be_partial(self):
        self.write(self.event_rows())
        with self.assertRaisesRegex(ValueError,'Incomplete'):event_files([self.path],expected_entries=3)

    def test_metadata_entries_change_rejected(self):
        r=self.event_rows();r[1]['metadata_hex']=f'{1000|(7<<64)|(3<<80)|(1<<91):032x}';self.write(r)
        with self.assertRaisesRegex(ValueError,'entry count changed'):event_files([self.path],expected_entries=2)

    def test_bound_types_and_ranges_rejected(self):
        self.write(self.event_rows())
        for kwargs in [dict(capture_start_cycles=-1),dict(previous_observed_cycles=1<<64),
                       dict(capture_start_cycles=True),dict(expected_epoch=65536),dict(expected_entries=513)]:
            with self.subTest(kwargs=kwargs),self.assertRaises(ValueError):event_files([self.path],**kwargs)

    def test_full_64_bit_timestamp_not_low_word_only(self):
        r=self.event_rows();start=0x12345678fffffff0
        for i,row in enumerate(r):
            row['event_hex']=f'{start+i*32:064x}'
            row['metadata_hex']=f'{(start+1000)|(7<<64)|(2<<80)|(1<<91):032x}'
        self.write(r);d=event_files([self.path],capture_start_cycles=start)
        self.assertEqual(d['events'][1]['timestamp_cycles'],start+32)
        self.assertEqual(d['temporal_provenance']['status'],'BOUNDED_TIME_PASS')

    def test_retained_first_timestamp_failure_regression(self):
        # Sanitized real e4 timestamps, not inferred replacements for raw words.
        r=self.event_rows()
        for row,t in zip(r,[244641140,4260663719941]):
            row['event_hex']=f'{t:064x}'
            row['metadata_hex']=f'{4291700877395|(7<<64)|(2<<80)|(1<<91):032x}'
        self.write(r);d=event_files([self.path],previous_observed_cycles=10516269668)
        self.assertEqual(d['temporal_provenance']['status'],'FAIL')
        self.assertEqual(d['events'][0]['timestamp_cycles'],244641140)

if __name__=='__main__':unittest.main()
