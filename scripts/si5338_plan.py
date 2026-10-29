"""Offline Si5338 identity and frequency arithmetic; never emits I2C writes."""
import argparse
from fractions import Fraction
import json
from pathlib import Path

from si5338_readonly import read_dump

GRADES={ord(letter)-64:letter for letter in 'ABCDEFGHJKLMNPQ'}

def identify(registers):
    suffix=registers[2]&63
    code=registers[3]>>3
    revision=registers[0]&7
    return dict(family_identified=suffix==38,base_part_number=suffix,
        grade_code=code,grade=GRADES.get(code),silicon_revision_code=revision,
        silicon_revision={0:'A',1:'B'}.get(revision),
        nvm_code=((registers[3]&1)<<16)|(registers[4]<<8)|registers[5])

def multisynth(ratio):
    ratio=Fraction(ratio)
    a,b=divmod(ratio.numerator,ratio.denominator)
    c=ratio.denominator
    if not (8<=a<=567 or (a in (4,6) and b==0)):
        raise ValueError('Unsupported MultiSynth ratio')
    if b>=1<<30 or c>=1<<30:
        raise ValueError('Ratio would require truncation; not supported here')
    return dict(integer=a,numerator=b,denominator=c,
        P1=(128*ratio.numerator)//c-512,P2=(128*b)%c,P3=c)

def frequency_candidate(input_hz=25_000_000,output_hz=100_000_000,vco_hz=2_500_000_000,p_div=1,r_div=1):
    if input_hz<=0 or output_hz<=0 or p_div not in (1,2,4,8,16,32) or r_div not in (1,2,4,8,16,32):
        raise ValueError('Invalid positive frequency or divider')
    pfd=Fraction(input_hz,p_div)
    if not 5_000_000<=pfd<=40_000_000 or not 2_200_000_000<=vco_hz<=2_840_000_000:
        raise ValueError('PFD or VCO out of range')
    return dict(input_hz=input_hz,output_hz=output_hz,vco_hz=vco_hz,p_div=p_div,r_div=r_div,
        pfd_hz=str(pfd),feedback=multisynth(Fraction(vco_hz)/pfd),
        output=multisynth(Fraction(vco_hz,output_hz*r_div)),
        arithmetic_only=True,ram_write_ready=False,
        scope='Divider arithmetic only; not a complete register table, PLL/driver configuration, or write authorization')

def inventory_plan(path):
    dump=read_dump(path)
    if dump['page']!=0:raise ValueError('Identity requires page0')
    identity=identify({int(k):int(v,16) for k,v in dump['registers'].items()})
    if not identity['family_identified'] or identity['grade'] is None:
        raise ValueError('Unknown device identity')
    return dict(inventory_sha256=dump['sha256'],identity=identity,
        schematic_grade='C',identity_matches_schematic_grade=identity['grade']=='C',
        candidate=frequency_candidate(),ram_write_ready=False,
        missing_prerequisites=[
            'Reconcile readback grade with schematic and actual board revision',
            'Verify physical VDDO2 supply and GT input electrical requirements',
            'Produce and audit a complete ClockBuilder or Reference-Manual configuration table and allowed masks',
            'Back up every affected configuration page and original page selection',
            'Implement and test bounded RAM write, calibration, masked readback and external-device restore',
            'Validate the selected input and the resulting output in hardware'],
        scope='Offline preparation only; no hardware connection or bus-write commands')

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--dump',type=Path,required=True)
    p.add_argument('--output',type=Path)
    a=p.parse_args();result=inventory_plan(a.dump)
    payload=json.dumps(result,indent=2)+'\n'
    if a.output:a.output.write_text(payload,encoding='utf-8')
    print(payload,end='')

if __name__=='__main__':main()
