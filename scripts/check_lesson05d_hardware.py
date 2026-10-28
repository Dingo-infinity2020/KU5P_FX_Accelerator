"""Record SRAM configuration and observed PCIe state without assuming link-up."""
import argparse
import csv
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
from pcie_evidence import verify_sources


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build-dir', type=Path, required=True)
    parser.add_argument('--status-label', default='after_rescan')
    parser.add_argument('--windows-report', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    out = args.build_dir.resolve()
    if out == root or root in out.parents:
        parser.error('Use an external build directory')
    if not args.status_label or any(c not in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-' for c in args.status_label):
        parser.error('Invalid status label')
    proof = json.loads((out/'verification.json').read_text())
    assert proof['timing']['met'], 'Timing not met'
    source_locations=verify_sources(out,root,proof['sources'])
    for name, key in (('lesson05d_pcie_top.bit', 'bitstream_sha256'),
                      ('lesson05d_pcie_top.ltx', 'ltx_sha256'),
                      ('lesson05d_pcie_top_routed.dcp', 'checkpoint_sha256')):
        assert sha(out/name) == proof[key], f'Changed artifact: {name}'
    programmed = dict(line.split('=', 1) for line in (out/'hardware/programmed.txt').read_text().splitlines())
    assert programmed['configuration'] == 'JTAG_SRAM' and programmed['device'] == 'xcku5p'
    assert int(programmed['bit_bytes']) == (out/'lesson05d_pcie_top.bit').stat().st_size
    assert int(programmed['programmed_unix']) >= (out/'lesson05d_pcie_top.bit').stat().st_mtime
    status_path = out/'hardware'/f'{args.status_label}.tsv'
    with status_path.open(newline='') as handle:
        rows = list(csv.DictReader(handle, delimiter='\t'))
    assert len(rows) == 6
    samples = []
    expected_build = proof['monitor_build_id']
    fields = ('link_up', 'done', 'axi_reset_n', 'msi_enabled', 'perst_n', 'gt_powergood', 'ref_clock_recent', 'axi_clock_recent')
    if not proof.get('status_bit7_represents_axi_activity',True):
        fields = fields[:-1]+('calibration_clock_recent',)
    for index, row in enumerate(rows):
        assert int(row['index']) == index and int(row['build_hex'], 16) == int(expected_build, 16)
        value = int(row['status_hex'], 16)
        assert 0 <= value < 256
        samples.append(dict(status_hex=f'{value:02x}', **{name: bool(value & (1 << bit)) for bit, name in enumerate(fields)}))
    windows = json.loads(args.windows_report.read_text(encoding='utf-8-sig'))
    expected_device = proof.get('expected_device_id', '9038')
    assert windows['expected_vendor'] == '10EE' and windows['expected_device'] == expected_device
    hardware_scripts = ('tcl/lesson05d_hardware.tcl', 'scripts/check_lesson05d_hardware.py', 'scripts/pcie_evidence.py',
                        'scripts/inspect_pcie_windows.ps1', 'scripts/xdma_windows.py',
                        'tests/test_xdma_windows.py')
    if proof.get('training_debug'):
        hardware_scripts += ('scripts/check_pcie_training.py',)
    if proof.get('phy_debug'):
        hardware_scripts += ('scripts/check_pcie_phy.py',)
    result = dict(verified_at_utc=datetime.now(timezone.utc).isoformat(),
        configuration='JTAG_SRAM', configuration_done_observed=True,
        bitstream_sha256=proof['bitstream_sha256'], ltx_sha256=proof['ltx_sha256'],
        build_id=expected_build, status_samples=samples,
        physical_link_observed=any(s['link_up'] for s in samples),
        reference_clock_activity_observed=any(s['ref_clock_recent'] for s in samples),
        axi_clock_activity_observed=any(s['axi_clock_recent'] for s in samples) if proof.get('status_bit7_represents_axi_activity',True) else None,
        gt_powergood_observed=any(s['gt_powergood'] for s in samples),
        host_enumerated=windows['endpoint_count'] > 0,
        endpoint_count=windows['endpoint_count'], host_dma_tested=False,
        negotiated_link_speed=None, negotiated_link_width=None,
        scope='JTAG configuration and readonly VIO/PnP observation; BAR and DMA not tested',
        windows_report_sha256=sha(args.windows_report), status_sha256=sha(status_path),
        hardware_source_sha256={name: sha(root/name) for name in hardware_scripts},
        verified_source_locations=source_locations)
    if proof.get('phy_debug'):
        result.update(phy_debug=True,
            exported_power_on_signal='XDMA sys_clk_ce_out derives from common !rst_txpisopd; not four raw GT power-good outputs')
    if proof.get('pcie_lanes') == 4:
        reset_log = out/'hardware/local_reset_actions.tsv'
        with reset_log.open(newline='') as handle:
            actions = list(csv.DictReader(handle, delimiter='\t'))
        assert actions and int(actions[0]['readback']) == 1
        assert all(int(row['requested']) == int(row['readback']) for row in actions)
        assert int(actions[-1]['readback']) == 0, 'Local endpoint reset is still asserted'
        result.update(local_reset_readback=0, local_reset_log_sha256=sha(reset_log),
                      expected_device_id=expected_device, configured_lanes=4)
    (out/'hardware_verification.json').write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps(result))


if __name__ == '__main__':
    main()
