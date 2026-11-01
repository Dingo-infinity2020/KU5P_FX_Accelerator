"""Report XDMA parent/child configuration without assuming propagation.

Generated files are read-only inputs. A strict expected hard-core attribute is
an explicit engineering contract, not inferred from the parent GUI option.
"""
import argparse,hashlib,json,re
from pathlib import Path

def xci(path):
    data=json.loads(path.read_text())['ip_inst']
    result={}
    for group in ('component_parameters','model_parameters','runtime_parameters'):
        values={}
        for key,items in data['parameters'][group].items():
            if len(items)!=1 or 'value' not in items[0]:raise ValueError('Ambiguous XCI parameter: '+key)
            values[key]=items[0]['value']
        result[group]=values
    return result

def boolean(value):
    if not isinstance(value,str) or value.lower() not in ('true','false'):
        raise ValueError('Invalid boolean configuration')
    return value.lower()=='true'

def compare(parent,child, *, expected_hard_disable=None):
    p=parent['component_parameters'];c=child['component_parameters'];m=child['model_parameters']
    requested=boolean(p['enable_lane_reversal'])
    disabled=boolean(c['PL_DISABLE_LANE_REVERSAL'])
    if boolean(m['PL_DISABLE_LANE_REVERSAL'])!=disabled:
        raise ValueError('Child component/model lane-reversal attributes disagree')
    if expected_hard_disable is not None and (type(expected_hard_disable) is not bool or disabled!=expected_hard_disable):
        raise ValueError('Hard-core lane-reversal contract failed')
    return dict(parent_lane_reversal_requested=requested,child_hard_disable=disabled,
        relation='INTENT_NOT_REALIZED_IN_CHILD' if requested and disabled else 'NO_ENABLED_INTENT_CONFLICT',
        parent_model_exposes_lane_reversal=any('LANE_REVERSAL' in k.upper() for k in parent['model_parameters']),
        child_managed=child['runtime_parameters'].get('MANAGED'),
        parent_width=p['pl_link_cap_max_link_width'],parent_speed=p['pl_link_cap_max_link_speed'],
        scope='Generated configuration only; no primitive, physical mapping, root-port capability or L0 proof')

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--parent',type=Path,required=True);p.add_argument('--child',type=Path,required=True)
    p.add_argument('--expected-hard-disable',choices=['true','false']);p.add_argument('--output',type=Path,required=True)
    a=p.parse_args()
    result=compare(xci(a.parent),xci(a.child),expected_hard_disable=None if a.expected_hard_disable is None else boolean(a.expected_hard_disable))
    result['input_sha256']={k:hashlib.sha256(v.read_bytes()).hexdigest() for k,v in [('parent',a.parent),('child',a.child)]}
    with a.output.open('x') as h:json.dump(result,h,indent=2);h.write('\n')
    print(json.dumps(result))

if __name__=='__main__':main()
