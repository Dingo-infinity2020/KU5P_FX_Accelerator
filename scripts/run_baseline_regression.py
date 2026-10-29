"""Bounded M0 offline regression. Never connects to or programs hardware."""
import argparse
from datetime import datetime, timezone
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
ERROR = re.compile(r"^\s*(?:FATAL(?:_ERROR)?|ERROR|Fatal|Error)(?:\s*:|\s*\[)", re.M)


def sha(path):
    with path.open('rb') as handle:
        return hashlib.file_digest(handle, 'sha256').hexdigest()


def git(*args):
    return subprocess.check_output(['git', '-C', str(ROOT), *args]).decode('utf-8').strip()


def inventory():
    names = git('ls-files', '-z', '--cached', '--others', '--exclude-standard').split('\0')
    return {n: sha(ROOT / n) for n in sorted(set(names)) if n and (ROOT / n).is_file()}


def new_output(path, root=ROOT):
    path, root = path.resolve(), root.resolve()
    if path == root or root in path.parents:
        raise ValueError('Output must be outside the source repository')
    path.mkdir(parents=True, exist_ok=False)
    return path


def accept_result(code, text, marker=None, expected=None):
    if code != 0:
        raise ValueError(f'Process failed: {code}')
    if ERROR.search(text):
        raise ValueError('Error/Fatal diagnostic despite exit status')
    if marker is not None:
        if not marker.is_file():
            raise ValueError('Missing fresh PASS marker')
        value = marker.read_text().strip()
        if not re.fullmatch(expected, value):
            raise ValueError(f'Incomplete PASS marker: {value}')
        return value
    if expected is not None:
        if not re.search('^'+expected+'$', text, re.M):
            raise ValueError('Missing reference-generation completion marker')
        return dict(reference_generation=True)
    matches = re.findall(r'^Ran (\d+) tests? in .*$', text, re.M)
    if len(matches) != 1 or int(matches[0]) == 0 or not re.search(r'^OK\s*$', text, re.M):
        raise ValueError('Missing complete unittest result')
    if re.search(r'^OK\s*\(', text, re.M):
        raise ValueError('Skipped/expected failures need explicit review')
    return dict(tests=int(matches[0]), failures=0, skipped=0)


def qualify_version(code, text):
    # The 2026.1 Windows launcher returns 1 for informational -version.
    # This exception is restricted to that probe, never simulation/builds.
    if code not in (0, 1) or ERROR.search(text) or not re.search(r'^vivado v2026\.1\b', text, re.I | re.M):
        raise ValueError('Expected exact Vivado 2026.1 version output')
    return dict(version=text.splitlines()[0], informational_exit_code=code)


def run_job(name, command, output, timeout, marker=None, expected=None):
    log = output / (name + '.log')
    started = time.time()
    result = dict(name=name, command=[str(v) for v in command], started_utc=datetime.now(timezone.utc).isoformat(),
                  timeout_seconds=timeout, evidence_level='SIM', status='FAIL')
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE='1', PYTHONIOENCODING='utf-8')
    with log.open('x', encoding='utf-8') as handle:
        process = subprocess.Popen(command, cwd=ROOT, env=env, stdout=handle, stderr=subprocess.STDOUT)
        try:
            code = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            # Terminate only this launcher's owned process tree, never MCP/hw_server.
            if os.name == 'nt':
                subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'], stdout=handle, stderr=subprocess.STDOUT)
            else:
                process.kill()
            process.wait()
            code = -1
            result['reason'] = 'Bounded job timed out'
    result.update(exit_code=code, elapsed_seconds=round(time.time()-started, 3), log_sha256=sha(log))
    text = log.read_text(encoding='utf-8', errors='replace')
    # Some wrappers print PASS after xsim reports a runtime Error. Audit every
    # nested runtime/build log, not only the wrapper's last line.
    job_dir = output / name
    logs = list(job_dir.rglob('*.log')) if job_dir.exists() else []
    result['nested_log_sha256'] = {str(p.relative_to(output)): sha(p) for p in logs}
    try:
        combined = text + '\n' + '\n'.join(p.read_text(errors='replace') for p in logs)
        if marker is not None and marker.exists() and marker.stat().st_mtime < started:
            raise ValueError('Stale PASS marker')
        result['acceptance'] = accept_result(code, combined, marker, expected)
        result['status'] = 'PASS'
    except ValueError as error:
        result.setdefault('reason', str(error))
    return result


def historical_artifacts(root):
    """Rehash existing proofs/artifacts; never turn them into a fresh test."""
    results = []
    for name in ('lesson05_board', 'lesson05c_pipeline', 'lesson05i_pcie_boot_attempt4'):
        folder = root / name
        proof = folder / 'verification.json'
        result = dict(name=name, evidence_level='HISTORICAL_FILE_RECHECK', status='HOLD')
        if not proof.is_file():
            result['reason'] = 'Historical proof unavailable'
            results.append(result)
            continue
        data = json.loads(proof.read_text())
        checks = []
        candidates = dict(data.get('artifacts', {}))
        for key, filename in [('synth_checkpoint_sha256', 'two_channel_pfb_fx_pipeline_synth.dcp'),
                              ('routed_checkpoint_sha256', 'two_channel_pfb_fx_pipeline_routed.dcp')]:
            if key in data:
                candidates[filename] = data[key]
        for filename, digest in candidates.items():
            path = (folder / filename).resolve()
            if folder.resolve() not in path.parents:
                raise ValueError('Unsafe artifact path in historical proof')
            checks.append(dict(name=filename, matches=path.is_file() and sha(path)==digest, expected_sha256=digest))
        result.update(proof_sha256=sha(proof), artifacts=checks,
                      current_source_matches={n: (ROOT/n).is_file() and sha(ROOT/n)==digest for n,digest in data['sources'].items()},
                      status='PASS' if checks and all(c['matches'] for c in checks) else 'HOLD',
                      scope='Saved bytes rehashed only; no fresh synthesis, route or board acceptance')
        results.append(result)
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--vivado-bin', type=Path, required=True)
    parser.add_argument('--history-root', type=Path, required=True)
    parser.add_argument('--hdl', action='store_true', help='Run existing bounded HDL regressions, no synthesis/hardware')
    args = parser.parse_args()
    output = new_output(args.output_dir)
    sources = inventory()
    for name in sources:
        target = output / 'source_snapshot' / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT/name, target)
    manifest = dict(schema_version=1, started_utc=datetime.now(timezone.utc).isoformat(),
                    source_commit=git('rev-parse', 'HEAD'), branch=git('branch', '--show-current'),
                    worktree_status=git('status', '--short'), sources=sources,
                    python_version=sys.version, vivado_bin=str(args.vivado_bin.resolve()),
                    hardware_actions=False, synthesis_run=False, routed_run=False,
                    jobs=[], historical=historical_artifacts(args.history_root), status='RUNNING')
    path = output / 'regression.json'

    def save():
        temporary = output / 'regression.partial.json'
        temporary.write_text(json.dumps(manifest, indent=2)+'\n', encoding='utf-8')
        temporary.replace(path)

    save()
    try:
        version = subprocess.run([str(args.vivado_bin/'vivado.bat'), '-version'], cwd=output,
                                 stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
        version_text = version.stdout.decode('utf-8', errors='replace')
        (output/'vivado_version.txt').write_text(version_text, encoding='utf-8')
        manifest['tools'] = dict(vivado=qualify_version(version.returncode, version_text), numpy_version=importlib.metadata.version('numpy'))
    except (ValueError, OSError, subprocess.SubprocessError, importlib.metadata.PackageNotFoundError) as error:
        manifest.update(status='HOLD', reason=f'Tool qualification failed: {error}')
        save()
        return 1
    save()
    jobs = [('python', [sys.executable, '-B', '-m', 'unittest', 'discover', '-s', 'tests', '-v'], 180, None, None)]
    if args.hdl:
        shell = shutil.which('pwsh') or shutil.which('powershell')
        if not shell:
            parser.error('PowerShell unavailable')
        for name, script, timeout, marker, pattern in [
            ('boot', 'run_pcie_boot_test.ps1', 240, 'simulation_pass.txt', r'PASS boot_diagnostics_checks=14'),
            ('training', 'run_pcie_training_monitor_test.ps1', 240, 'simulation_pass.txt', r'PASS training_monitor_checks=9'),
            ('application', 'run_pcie_application_test.ps1', 240, 'simulation_pass.txt', r'PASS packets=29 beats=3712 .+'),
            ('pipeline', 'run_pipeline.ps1', 900, 'simulation_pass.txt', r'PASS windows=90 .+')]:
            if name == 'application':
                jobs.append(('application_vectors', [sys.executable, '-B', str(ROOT/'scripts/generate_pcie_vectors.py'),
                    '--output-dir', str(output/'application')], 30, None, r'PCIE_VECTORS packets=29 beats=3712'))
            command = [shell, '-NoProfile', '-File', str(ROOT/'scripts'/script), '-VivadoBin', str(args.vivado_bin), '-BuildDir', str(output/name)]
            if name == 'pipeline':
                command += ['-Python', sys.executable]
            jobs.append((name, command, timeout, output/name/marker, pattern))
    else:
        manifest['jobs'].append(dict(name='hdl', status='SKIP', reason='--hdl not requested'))
    for name, command, timeout, marker, pattern in jobs:
        result = run_job(name, command, output, timeout, marker, pattern)
        manifest['jobs'].append(result)
        save()
        print(f"M0_JOB {name} {result['status']}", flush=True)
        if result['status'] != 'PASS':
            # Preserve failure and stop rather than masking it with later PASS.
            break
    manifest['sources_unchanged'] = inventory() == sources
    manifest['status'] = 'PASS' if (manifest['sources_unchanged'] and
        all(j['status']=='PASS' for j in manifest['jobs']) and all(h['status']=='PASS' for h in manifest['historical'])) else 'HOLD'
    manifest['finished_utc'] = datetime.now(timezone.utc).isoformat()
    save()
    print(f"M0_REGRESSION {manifest['status']} {path}")
    return 0 if manifest['status']=='PASS' else 1


if __name__ == '__main__':
    sys.exit(main())
