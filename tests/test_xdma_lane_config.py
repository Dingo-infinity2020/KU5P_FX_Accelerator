import json,sys,tempfile,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from check_xdma_lane_config import boolean,compare,xci

class LaneContractTests(unittest.TestCase):
    def fixture(self,parent='true',child='TRUE',model='TRUE'):
        p=dict(component_parameters=dict(enable_lane_reversal=parent,pl_link_cap_max_link_width='X4',pl_link_cap_max_link_speed='8.0_GT/s'),model_parameters={},runtime_parameters={})
        c=dict(component_parameters=dict(PL_DISABLE_LANE_REVERSAL=child),model_parameters=dict(PL_DISABLE_LANE_REVERSAL=model),runtime_parameters=dict(MANAGED='TRUE'))
        return p,c
    def test_conflicting_intent_is_reported(self):
        self.assertEqual(compare(*self.fixture())['relation'],'INTENT_NOT_REALIZED_IN_CHILD')
    def test_disabled_parent_is_not_proof_of_board_success(self):
        self.assertEqual(compare(*self.fixture(parent='false'))['relation'],'NO_ENABLED_INTENT_CONFLICT')
    def test_model_disagreement_rejected(self):
        with self.assertRaisesRegex(ValueError,'disagree'):compare(*self.fixture(model='FALSE'))
    def test_strict_candidate_contract_rejects_old_discrepancy(self):
        with self.assertRaisesRegex(ValueError,'contract failed'):compare(*self.fixture(),expected_hard_disable=False)
    def test_enabled_candidate_contract(self):
        self.assertFalse(compare(*self.fixture(child='FALSE',model='FALSE'),expected_hard_disable=False)['child_hard_disable'])
    def test_invalid_bool_is_not_silently_false(self):
        for v in ['0','yes','',0,None]:
            with self.subTest(v=v),self.assertRaises(ValueError):boolean(v)
    def test_xci_schema_and_duplicate_values(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/'sample.xci'
            data=dict(ip_inst=dict(parameters=dict(component_parameters=dict(k=[dict(value='true')]),model_parameters={},runtime_parameters={})))
            p.write_text(json.dumps(data));self.assertEqual(xci(p)['component_parameters']['k'],'true')
            data['ip_inst']['parameters']['component_parameters']['k'].append(dict(value='false'))
            p.write_text(json.dumps(data))
            with self.assertRaisesRegex(ValueError,'Ambiguous'):xci(p)

if __name__=='__main__':unittest.main()
