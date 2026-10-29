import csv,hashlib,json,os,sys,tempfile,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from cpll_board_capture import capture,suite,flags,trace,verify_build

HEADER=('index','build_hex','observation_hex','heartbeat_hex','refcounter_hex','events_hex','manual_reset','refresh_start_us','refresh_end_us')

def write_capture(path,cycle,released=True,negative=False,stale=False,glitch=False,build_id='465805e2'):
    path.parent.mkdir(parents=True,exist_ok=True)
    count=12 if released else 2
    initial=(cycle*3_000_000)+(500_000 if released else 0)
    seq=cycle if released else cycle-1
    active=sum(1<<b for b in (0,1,2,4,6,12,13,14,16))|(seq<<24)
    if not released:active=(active&~((1<<12)|(1<<13)))|(1<<10)|(1<<11)
    if negative:active&=~((1<<1)|(1<<2)|(1<<4)|(1<<13))
    rises=cycle if released else cycle-1
    falls=max(0,cycle-1 if released else cycle-2)
    with path.open('w',newline='') as h:
        w=csv.writer(h,delimiter='\t');w.writerow(HEADER)
        for i in range(count):
            ev_rise=rises+(glitch and i>3);ev_fall=falls+(glitch and i>3)
            events=ev_rise|(ev_fall<<32)|(ev_rise<<64)|(ev_fall<<96)
            if negative:events=0
            heartbeat=(initial*100+(0 if stale else i*10_000_000))&0xffffffff
            ref=(initial*100//8+(i*1_250_000 if released and not negative else 0))&0xffffffff
            current=active|(((heartbeat>>7)&1)<<15)
            observation=current|(0xffffffff<<32)|(0xffffffff<<64)
            start=initial+i*100_000
            w.writerow((i,build_id,f'{observation:024x}',f'{heartbeat:08x}',f'{ref:08x}',f'{events:032x}',int(not released),start,start+10))

def write_build(out,workspace,build_id='465805e2',prefix=None):
    src='rtl/test.sv';data=b'authored fixture';f=workspace/src;f.parent.mkdir(parents=True);f.write_bytes(data)
    archived=out/'source_snapshot'/src;archived.parent.mkdir(parents=True);archived.write_bytes(data)
    sources={src:hashlib.sha256(data).hexdigest()};artifacts={}
    prefix=prefix or ('lesson05h_cpll_source_top' if build_id=='465805e3' else 'lesson05g_cpll_top')
    for name in (prefix+'.bit',prefix+'.ltx',prefix+'_routed.dcp'):
        (out/name).write_bytes(name.encode());os.utime(out/name,(1_000_000_000,1_000_000_000))
        artifacts[name]=hashlib.sha256((out/name).read_bytes()).hexdigest()
    proof=dict(build_id=build_id,sources=sources,artifacts=artifacts,timing={'met':True},cdc_critical_no_waiver=0,
        route={'routable':9,'routed':9,'errors':0})
    (out/'verification.json').write_text(json.dumps(proof));(out/'inputs.json').write_text(json.dumps(dict(build_id=build_id,sources=sources)))
    hw=out/'hardware';hw.mkdir()
    (hw/'programmed.txt').write_text(f'configuration=JTAG_SRAM\nbuild={build_id}\njtag_hz=6000000\nprogrammed_unix=1000000001\n')
    (hw/'reset_actions.tsv').write_text('unix\trequested\treadback\n1\t1\t1\n2\t0\t0\n3\t1\t1\n4\t0\t0\n5\t1\t1\n6\t0\t0\n')
    for n in range(1,4):
        write_capture(hw/f'cycle{n}_held.tsv',n,False,build_id=build_id)
        write_capture(hw/f'cycle{n}_released.tsv',n,build_id=build_id)

class CpllBoardCaptureTest(unittest.TestCase):
    def test_invalid_control_observer_is_unknown(self):
        self.assertIsNone(flags(0)['cpllreset']);self.assertIsNone(flags(0)['cpllpd'])
        self.assertIs(flags(1<<16)['cpllreset'],False)

    def test_negative_lock_result_is_a_valid_capture(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'data.tsv';write_capture(p,1,negative=True)
            result=capture(p,1)
            self.assertFalse(result['released_window_passed'])
            self.assertFalse(result['samples'][0]['current']['cpll_lock'])
            self.assertTrue(result['checks']['heartbeat_advances'])

    def test_counter_ratio_and_stale_heartbeat(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'data.tsv';write_capture(p,1)
            result=capture(p,1)
            self.assertTrue(result['released_window_passed'])
            self.assertEqual(result['intervals'][0]['reference_mhz_relative_to_nominal_sysclk'],100)
            write_capture(p,1,stale=True)
            self.assertFalse(capture(p,1)['released_window_passed'])

    def test_returned_high_levels_cannot_hide_intermediate_drop(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'data.tsv';write_capture(p,1,glitch=True)
            result=capture(p,1)
            self.assertTrue(result['checks']['released_levels_good'])
            self.assertFalse(result['checks']['no_lock_or_txdone_events_during_observation'])
            self.assertFalse(result['released_window_passed'])

    def test_three_cycle_suite_checks_real_recovery_and_artifacts(self):
        with tempfile.TemporaryDirectory() as tmp:
            out=Path(tmp)/'build';out.mkdir();workspace=Path(tmp)/'workspace';write_build(out,workspace)
            result=suite(out,workspace);self.assertTrue(result['hardware_passed'])
            write_capture(out/'hardware/cycle2_released.tsv',2,negative=True)
            # Keep event chronology valid for a real persistent negative test.
            for n in range(1,4):
                write_capture(out/f'hardware/cycle{n}_held.tsv',n,False,negative=True)
                write_capture(out/f'hardware/cycle{n}_released.tsv',n,negative=True)
            result=suite(out,workspace);self.assertTrue(result['evidence_valid']);self.assertFalse(result['hardware_passed'])
            (out/'lesson05g_cpll_top.bit').write_bytes(b'changed')
            with self.assertRaises(ValueError):suite(out,workspace)

    def test_sequence_is_not_inferred_from_static_good_levels(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'data.tsv';write_capture(p,1)
            self.assertFalse(capture(p,2)['released_window_passed'])

    def test_e3_identity_is_explicit_and_cannot_mix_e2_captures(self):
        with tempfile.TemporaryDirectory() as tmp:
            out=Path(tmp)/'build';out.mkdir();workspace=Path(tmp)/'workspace';write_build(out,workspace,'465805e3')
            result=suite(out,workspace)
            self.assertTrue(result['hardware_passed']);self.assertEqual(result['build_id'],'465805e3')
            self.assertEqual(result['artifact_prefix'],'lesson05h_cpll_source_top')
            path=out/'hardware/cycle1_released.tsv'
            with self.assertRaises(ValueError):capture(path,1) # e2 default remains strict
            self.assertTrue(capture(path,1,'465805e3')['released_window_passed'])
            write_capture(out/'hardware/cycle2_held.tsv',2,False,build_id='465805e2')
            with self.assertRaises(ValueError):suite(out,workspace)

    def test_wrong_artifact_prefix_or_programmed_id_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            out=Path(tmp)/'build';out.mkdir();workspace=Path(tmp)/'workspace'
            write_build(out,workspace,'465805e3',prefix='lesson05g_cpll_top')
            with self.assertRaisesRegex(ValueError,'Artifact prefix'):verify_build(out,workspace)
        with tempfile.TemporaryDirectory() as tmp:
            out=Path(tmp)/'build';out.mkdir();workspace=Path(tmp)/'workspace';write_build(out,workspace,'465805e3')
            path=out/'hardware/programmed.txt';path.write_text(path.read_text().replace('465805e3','465805e2'))
            with self.assertRaisesRegex(ValueError,'programming metadata'):suite(out,workspace)

    def test_static_good_flags_without_reset_events_fail_suite(self):
        with tempfile.TemporaryDirectory() as tmp:
            out=Path(tmp)/'build';out.mkdir();workspace=Path(tmp)/'workspace';write_build(out,workspace)
            for path in (out/'hardware').glob('cycle*.tsv'):
                with path.open(newline='') as h:rows=list(csv.DictReader(h,delimiter='\t'))
                for row in rows:row['events_hex']='0'*32
                with path.open('w',newline='') as h:
                    w=csv.DictWriter(h,fieldnames=HEADER,delimiter='\t');w.writeheader();w.writerows(rows)
            result=suite(out,workspace)
            self.assertTrue(all(c['released']['checks']['released_levels_good'] for c in result['cycles']))
            self.assertFalse(result['hardware_passed'])

    def test_fragmented_ila_reconstruction_and_overlap(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'trace.csv';layout=Path(tmp)/'layout.tsv'
            probes=[('status_low',0,0,16),('status_high',0,16,16),('events',1,0,128)]
            with path.open('w',newline='') as h:
                w=csv.writer(h);w.writerow(['Sample in Buffer',*[p[0] for p in probes]])
                w.writerow(['Radix - UNSIGNED','HEX','HEX','HEX'])
                for i in range(8192):w.writerow([i,f'{((i//128)&1)<<15:x}','1','0'])
            def layout_write():
                with layout.open('w',newline='') as h:
                    w=csv.writer(h,delimiter='\t');w.writerow(['name','port','first_bit','width']);w.writerows(probes)
            layout_write();result=trace(path,layout,'465805e3')
            self.assertEqual(result['build_id'],'465805e3')
            self.assertTrue(result['same_domain_heartbeat_passed']);self.assertEqual(result['observed_transitions']['cpll_lock'],0)
            probes[1]=('status_high',0,15,16);layout_write()
            with self.assertRaises(ValueError):trace(path,layout)

if __name__=='__main__':unittest.main()
