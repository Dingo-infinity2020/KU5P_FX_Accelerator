"""Reject false green results: a simulator may exit zero after runtime errors."""
import sys
from pathlib import Path
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from run_baseline_regression import accept_result, new_output


class AcceptanceTests(unittest.TestCase):
    def marker_case(self, code, text, contents='PASS checks=14'):
        with tempfile.TemporaryDirectory() as folder:
            marker = Path(folder)/'pass.txt'
            if contents is not None:
                marker.write_text(contents)
            return accept_result(code, text, marker, r'PASS checks=14')

    def test_runtime_error_after_pass_rejected(self):
        for message in ['Error: XPM assertion', 'ERROR: stopped', 'FATAL_ERROR: license', 'Fatal: stopped', 'ERROR [Common 17-39] failed']:
            with self.subTest(message=message), self.assertRaises(ValueError):
                self.marker_case(0, 'PASS checks=14\n'+message)

    def test_exit_failure_with_pass_rejected(self):
        with self.assertRaises(ValueError):
            self.marker_case(1, 'PASS checks=14')

    def test_missing_or_partial_marker_rejected(self):
        for value in [None, 'PASS checks=13', 'PASS checks=14\nFAIL', '']:
            with self.subTest(value=value), self.assertRaises(ValueError):
                self.marker_case(0, 'PASS', value)

    def test_complete_pass_and_warning_accepted(self):
        self.assertEqual(self.marker_case(0, 'WARNING: simulation is not hardware\nPASS checks=14'), 'PASS checks=14')

    def test_empty_or_failed_unittest_rejected(self):
        for text in ['Ran 0 tests in 0.0s\nOK', 'Ran 2 tests in 0.0s\nFAILED', 'Ran 2 tests in 0.0s\nOK (skipped=1)']:
            with self.subTest(text=text), self.assertRaises(ValueError):
                accept_result(0, text)

    def test_unittest_count(self):
        self.assertEqual(accept_result(0, 'Ran 7 tests in 0.01s\n\nOK\n')['tests'], 7)

    def test_existing_evidence_never_reused(self):
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaises(FileExistsError):
                new_output(Path(folder), Path(folder)/'repo')

    def test_in_repo_output_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            for output in [Path(folder), Path(folder)/'nested']:
                with self.assertRaises(ValueError):
                    new_output(output, Path(folder))


if __name__ == '__main__':
    unittest.main()
