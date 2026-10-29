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
            metadata_hex=f'{(7<<64)|(2<<80)|(1<<91):032x}') for i in range(2)]
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

if __name__=='__main__':unittest.main()
