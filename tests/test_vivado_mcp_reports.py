"""Report parser regression tests; no Vivado installation needed."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("compat",Path(__file__).resolve().parents[1]/"scripts/vivado_mcp_server.py")
compat = importlib.util.module_from_spec(spec)
spec.loader.exec_module(compat)


class ReportTests(unittest.TestCase):
    def test_current_table_and_starred_lut(self):
        report = """
| CLB LUTs* | 6345 | 0 | 0 | 216960 | 2.92 |
| CLB Registers | 11632 | 0 | 0 | 433920 | 2.68 |
| Block RAM Tile | 10 | 0 | 0 | 480 | 2.08 |
| DSPs | 52 | 0 | 0 | 1824 | 2.85 |
"""
        result = compat.parse_utilization(report)
        self.assertEqual(result["lut"]["used"],6345)
        self.assertEqual(result["lut"]["available"],216960)
        self.assertEqual(result["ff"]["used"],11632)
        self.assertEqual(result["bram"]["used"],10)
        self.assertEqual(result["dsp"]["used"],52)

    def test_legacy_table_and_fractional_bram(self):
        result = compat.parse_utilization("| Slice LUTs | 200 | 0 | 10000 | 2.0 |\n| Block RAM Tile | 0.5 | 0 | 100 | 0.5 |")
        self.assertEqual(result["lut"]["used"],200)
        self.assertEqual(result["bram"]["used"],0.5)

    def test_unknown_is_not_zero(self):
        result = compat.parse_utilization("No design is open")
        self.assertIsNone(result["dsp"]["used"])
        self.assertIsNone(result["dsp"]["percent"])
        self.assertFalse(result["dsp"]["parsed"])

    def test_timing_columns_and_constraint_scope(self):
        report = """
WNS(ns) TNS(ns) TNS Failing Endpoints TNS Total Endpoints WHS(ns) THS(ns) THS Failing Endpoints THS Total Endpoints WPWS(ns) TPWS(ns) TPWS Failing Endpoints TPWS Total Endpoints
------- ------- --------------------- ------------------- ------- ------- --------------------- ------------------- -------- -------- ---------------------- --------------------
5.732 0.000 0 41449 0.039 0.000 0 41449 4.427 0.000 0 14524
1. checking no_clock (0)
5. checking no_input_delay (99)
6. checking no_output_delay (334)
"""
        result = compat.parse_timing_summary(report)
        self.assertEqual(result["wns"],5.732)
        self.assertEqual(result["whs"],0.039)
        self.assertTrue(result["met"])
        self.assertEqual(result["constraint_checks"]["no_input_delay"],99)

    def test_hold_and_pulse_width_failures(self):
        header="WNS(ns) TNS(ns) WHS(ns) THS(ns) WPWS(ns) TPWS(ns)\n"
        result=compat.parse_timing_summary(header+"1 0 0 100 -0.1 -1.0 2 100 1 0 0 10\n")
        self.assertFalse(result["met"])
        self.assertEqual(result["failing_endpoints"],2)
        result=compat.parse_timing_summary(header+"1 0 0 100 0.1 0 0 100 -0.5 -2 4 10\n")
        self.assertFalse(result["met"])

    def test_no_timing_data(self):
        result=compat.parse_timing_summary("No timing paths")
        self.assertFalse(result["met"])
        self.assertIsNone(result["wns"])
        self.assertIsNone(result["failing_endpoints"])

    def test_simulation_mode_spelling(self):
        self.assertEqual(compat.simulation_command("behavioral"),"launch_simulation -mode behavioral")
        self.assertEqual(compat.simulation_command("post_synth_func"),
                         "launch_simulation -mode post-synthesis -type functional")

    def test_simulation_mode_rejects_invalid_input(self):
        with self.assertRaises(ValueError):
            compat.simulation_command("behav")


if __name__ == "__main__":
    unittest.main()
