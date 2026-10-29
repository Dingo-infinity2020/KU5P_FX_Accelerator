import sys,unittest
from pathlib import Path
from fractions import Fraction
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from si5338_plan import identify,frequency_candidate,multisynth

class Si5338PlanTest(unittest.TestCase):
    def test_actual_grade_is_distinct_from_silicon_revision(self):
        result=identify({0:1,2:0x26,3:0x10,4:0,5:0})
        self.assertEqual((result['grade'],result['silicon_revision'],result['nvm_code']),('B','B',0))
        self.assertEqual(identify({0:1,2:0x26,3:0x18,4:0,5:0})['grade'],'C')

    def test_exact_candidate_ratios(self):
        result=frequency_candidate()
        self.assertEqual(result['feedback'],dict(integer=100,numerator=0,denominator=1,P1=12288,P2=0,P3=1))
        self.assertEqual(result['output'],dict(integer=25,numerator=0,denominator=1,P1=2688,P2=0,P3=1))
        self.assertFalse(result['ram_write_ready'])

    def test_fractional_ratio_matches_manual_example(self):
        self.assertEqual(multisynth(Fraction(995328,10000)),
            dict(integer=99,numerator=333,denominator=625,P1=12228,P2=124,P3=625))

    def test_invalid_dividers_and_frequency_ranges_are_rejected(self):
        for args in ({'input_hz':0},{'p_div':3},{'r_div':64},{'vco_hz':3_000_000_000},{'input_hz':1_000_000}):
            with self.assertRaises(ValueError):frequency_candidate(**args)
        with self.assertRaises(ValueError):multisynth(Fraction(11,2))

if __name__=='__main__':unittest.main()
