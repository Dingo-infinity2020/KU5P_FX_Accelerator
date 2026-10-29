"""Decode a read-only Si5338 inventory and its physical I2C trace."""
import argparse,csv,hashlib,json
from pathlib import Path

ERRORS={0:'OK',1:'Bus busy timeout',2:'Write-address NACK',3:'Pointer NACK',4:'Read-address NACK',5:'Transaction/stretch timeout',6:'Arbitration lost',7:'Invalid state'}

def decode_word(value):
    return dict(data=value&255,register=(value>>8)&255,busy=bool(value&(1<<16)),
        scl=bool(value&(1<<18)),sda=bool(value&(1<<19)),scl_drive_low=bool(value&(1<<20)),
        sda_drive_low=bool(value&(1<<21)),reader_reset=bool(value&(1<<22)),error=(value>>24)&15,
        completion_count=(value>>32)&65535,phase=(value>>48)&31,
        interrupt_n=bool(value&(1<<56)),fpga_i2c_lsb_net_high=bool(value&(1<<57)),clock_select=bool(value&(1<<58)))

def decode_registers(registers,page):
    if page!=0:return dict(page=page,identified=False,scope='Current page is not page0; no page-switch configuration write was issued')
    identified=(registers[2]&63)==38
    result=dict(page=page,identified=identified,revision_code=registers[0]&7,part_suffix_decimal=registers[2]&63)
    if not identified:
        result['scope']='Raw bytes do not identify the expected Si5338 family';return result
    status=registers[218]
    result.update(grade_code=registers[3]>>3,
        pll_loss_of_lock_reported=bool(status&16),feedback_los_reported=bool(status&8),
        input_los_reported=bool(status&4),calibration_in_progress=bool(status&1),
        pll_lol_reporting_enabled=not bool(registers[241]&128),
        i2c_1p8_mode=bool(registers[27]&128),i2c_address_register=registers[27]&127,
        p1_input_selection=((registers[29]>>3)&3)*8+((registers[28]>>2)&7),
        pfd_reference_selection=registers[29]>>5,
        outputs=[dict(index=i,power_down_bit=bool(registers[31+i]&1),
            multisynth_power_down=bool(registers[31+i]&2),
            r_input_selection=(registers[31+i]>>5)&7,r_divider_code=(registers[31+i]>>2)&7,
            disabled_by_oeb_register=bool(registers[230]&(16|(1<<i))),
            driver_format_code=registers[36+i]&7,driver_format_reserved=(registers[36+i]&7)==0) for i in range(4)],
        scope='Register controls/status only; not proof of output frequency, jitter or PCIe reference-clock health')
    return result

def read_dump(path):
    with path.open(newline='') as h:rows=list(csv.DictReader(h,delimiter='\t'))
    assert len(rows)==257 and [int(r['address']) for r in rows]==[255,*range(255),255]
    last=None
    for index,row in enumerate(rows):
        assert int(row['index'])==index and int(row['error'])==0
        value=int(row['result_hex'],16);decoded=decode_word(value)
        assert decoded['register']==int(row['address']) and decoded['data']==int(row['data_hex'],16)
        assert decoded['completion_count']==int(row['sequence']) and decoded['error']==0 and not decoded['busy']
        assert decoded['scl'] and decoded['sda'] and not decoded['scl_drive_low'] and not decoded['sda_drive_low']
        assert not decoded['reader_reset']
        command=int(row['command_hex'],16);assert command>>1==decoded['register']
        if last is not None:assert decoded['completion_count']==(last+1)&65535
        last=decoded['completion_count']
    assert rows[0]['data_hex']==rows[-1]['data_hex'],'Page selector changed'
    page=int(rows[0]['data_hex'],16)&1
    registers={int(r['address']):int(r['data_hex'],16) for r in rows}
    return dict(sha256=hashlib.sha256(path.read_bytes()).hexdigest(),transactions=len(rows),page=page,
        registers={f'{k:03d}':f'{v:02x}' for k,v in registers.items()},decoded=decode_registers(registers,page))

def decode_trace(values):
    # The 12.5MHz ILA oversamples this ~100kHz bus. Qualify SDA start/stop
    # transitions with 160ns SCL stability to reject edge-quantization artifacts.
    scl=[v&1 for v in values];sda=[(v>>1)&1 for v in values]
    events=[]
    for i in range(2,len(values)-2):
        if sda[i]!=sda[i-1] and all(scl[i-2:i+3]):events.append((i,'start' if sda[i]==0 else 'stop'))
    assert [kind for _,kind in events]==['start','stop','start','stop'],'Incomplete/unexpected I2C frames'
    frames=[]
    for a,b in ((events[0][0],events[1][0]),(events[2][0],events[3][0])):
        edges=[i for i in range(a+1,b) if scl[i] and not scl[i-1]]
        bits=[sda[min(i+3,b-1)] for i in edges]
        assert len(bits)==19 and bits[-1]==0,'Expected two 9-bit words plus STOP clock'
        words=[]
        for offset in (0,9):
            value=0
            for bit in bits[offset:offset+8]:value=(value<<1)|bit
            words.append(dict(byte_hex=f'{value:02x}',ack_bit=bits[offset+8]))
        frames.append(words)
    assert frames[0][0]==dict(byte_hex='e0',ack_bit=0)
    assert frames[0][1]['ack_bit']==0 and frames[1][0]==dict(byte_hex='e1',ack_bit=0)
    assert frames[1][1]['ack_bit']==1,'Single-byte read must end with master NACK'
    return dict(frames=frames,register=int(frames[0][1]['byte_hex'],16),data=int(frames[1][1]['byte_hex'],16),
        configuration_data_bytes_written=0,scope='Selected physical trace: pointer-only write, then one-byte read; no configuration-data write')

def read_trace(path,layout=None,column=None):
    with path.open(newline='',encoding='utf-8-sig') as h:rows=list(csv.DictReader(h))
    assert rows[0]['Sample in Buffer'].startswith('Radix');radix=rows.pop(0)
    assert len(rows)==8192
    assert [int(r['Sample in Buffer']) for r in rows]==list(range(8192))
    if layout is None:
        assert column and radix[column]=='HEX'
        values=[int(r[column],16) for r in rows]
    else:
        with layout.open(newline='') as h:probes=list(csv.DictReader(h,delimiter='\t'))
        values=[0]*len(rows);mask=0;busy=None
        for probe in probes:
            port,first,width=(int(probe[k]) for k in ('port','first_bit','width'))
            assert port in (0,1) and width>0 and first>=0
            columns=[k for k in rows[0] if k==probe['name'] or k.startswith(probe['name']+'[')]
            assert len(columns)==1 and radix[columns[0]]=='HEX'
            raw=[int(r[columns[0]],16) for r in rows]
            assert all(0<=v<(1<<width) for v in raw)
            if port==1:
                assert busy is None and first==0 and width==1
                busy=raw;continue
            part_mask=((1<<width)-1)<<first
            assert not mask&part_mask,'Overlapping ILA fragments'
            mask|=part_mask
            values=[v|(part<<first) for v,part in zip(values,raw)]
        assert mask==255 and busy is not None,'Incomplete ILA layout'
        assert busy==[(v>>4)&1 for v in values],'Duplicated busy probes disagree'
    result=decode_trace(values)
    from check_pcie_clock_capture import measure
    result['capture_clock_calibration']=measure(values,7,monitor_mhz=12.5,divisor=256)
    result['csv_sha256']=hashlib.sha256(path.read_bytes()).hexdigest()
    if layout:result['layout_sha256']=hashlib.sha256(layout.read_bytes()).hexdigest()
    return result

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('action',choices=('dump','trace'))
    p.add_argument('path',type=Path);p.add_argument('--output',type=Path,required=True);p.add_argument('--column');p.add_argument('--layout',type=Path)
    a=p.parse_args()
    if a.action=='dump':result=read_dump(a.path)
    else:
        result=read_trace(a.path,a.layout,a.column)
    a.output.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k!='registers'}))

if __name__=='__main__':main()
