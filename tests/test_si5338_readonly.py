from pathlib import Path
import csv,sys,tempfile,unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from si5338_readonly import decode_word,decode_registers,decode_trace,read_trace

def protocol_samples(read_nack=1):
    values=[]
    def hold(scl,sda):
        for _ in range(10):
            values.append(scl|(sda<<1)|(1<<4)|(((len(values)//16)&1)<<7))
    hold(1,1)
    for words in (((0xe0,0),(218,0)),((0xe1,0),(4,read_nack))):
        hold(1,0)
        for byte,ack in words:
            for bit in [*((byte>>n)&1 for n in range(7,-1,-1)),ack]:
                hold(0,bit);hold(1,bit)
        hold(0,0);hold(1,0);hold(1,1)
    while len(values)<8192:hold(1,1)
    return values[:8192]

class Si5338ReadonlyTest(unittest.TestCase):
    def test_status_fields_are_not_confused_with_error_or_straps(self):
        value=0xa5|(218<<8)|(1<<18)|(1<<19)|(17<<32)|(3<<56)
        data=decode_word(value)
        self.assertEqual((data['data'],data['register'],data['completion_count']),(0xa5,218,17))
        self.assertTrue(data['scl'] and data['sda'] and data['fpga_i2c_lsb_net_high'] and data['interrupt_n'])
        self.assertFalse(data['busy'] or data['reader_reset'] or data['clock_select'])
        self.assertEqual(data['error'],0)

    def test_output_disable_and_masked_lol_are_preserved(self):
        registers=dict.fromkeys(range(256),0);registers[2]=0x66
        registers[218]=0x14;registers[230]=4;registers[241]=0x80
        registers[33]=1
        data=decode_registers(registers,0)
        self.assertTrue(data['identified'] and data['input_los_reported'] and data['pll_loss_of_lock_reported'])
        self.assertFalse(data['pll_lol_reporting_enabled'])
        self.assertTrue(data['outputs'][2]['power_down_bit'] and data['outputs'][2]['disabled_by_oeb_register'])
        self.assertFalse(data['outputs'][0]['disabled_by_oeb_register'])

    def test_page1_and_wrong_family_are_not_decoded_as_si5338(self):
        self.assertFalse(decode_registers({},1)['identified'])
        self.assertFalse(decode_registers({0:0,2:0},0)['identified'])

    def test_static_lines_are_not_a_successful_i2c_trace(self):
        with self.assertRaises(AssertionError):decode_trace([3]*8192)

    def test_read_transaction_rejects_missing_final_nack(self):
        self.assertEqual(decode_trace(protocol_samples())['data'],4)
        with self.assertRaises(AssertionError):decode_trace(protocol_samples(0))

    def test_fragmented_ila_layout_reconstructs_and_rejects_overlap(self):
        values=protocol_samples()
        probes=[('lines',0,0,2),('drive',0,2,2),('busy',0,4,1),('heartbeat',0,5,3),('busy_copy',1,0,1)]
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'capture.csv';layout=Path(tmp)/'layout.tsv'
            with path.open('w',newline='') as h:
                w=csv.writer(h);w.writerow(['Sample in Buffer',*[p[0] for p in probes]])
                w.writerow(['Radix - UNSIGNED',*['HEX']*len(probes)])
                for i,v in enumerate(values):
                    w.writerow([i,*[f'{((v>>first)&((1<<width)-1)) if port==0 else ((v>>4)&1):x}' for _,port,first,width in probes]])
            def write_layout():
                with layout.open('w',newline='') as h:
                    w=csv.writer(h,delimiter='\t');w.writerow(['name','port','first_bit','width']);w.writerows(probes)
            write_layout();self.assertEqual(read_trace(path,layout)['register'],218)
            probes[1]=('drive',0,1,2);write_layout()
            with self.assertRaises(AssertionError):read_trace(path,layout)

    def test_reserved_output_format_is_not_interpreted_as_lvds(self):
        registers=dict.fromkeys(range(256),0);registers[2]=38;registers[33]=2
        data=decode_registers(registers,0)['outputs'][2]
        self.assertTrue(data['driver_format_reserved'] and data['multisynth_power_down'])

if __name__=='__main__':unittest.main()
