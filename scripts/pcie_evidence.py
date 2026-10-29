"""Verify build source bytes, including archived historical source snapshots."""
import hashlib


def verify_sources(out, root, expected):
    verified = {}
    for name, digest in expected.items():
        candidates = [('workspace', root/name),
                      ('source_snapshot', out/'source_snapshot'/name),
                      ('source_snapshot_d5', out/'source_snapshot_d5'/name)]
        for location, path in candidates:
            if path.is_file() and hashlib.sha256(path.read_bytes()).hexdigest() == digest:
                verified[name] = location
                break
        else:
            raise AssertionError(f'Build source unavailable or changed: {name}')
    return verified
