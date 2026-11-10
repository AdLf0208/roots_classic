#!/usr/bin/env python3
"""Audit the real pinned export: deterministic staging, only planned ASTs, an
unchanged checkout.

This build has two modules (the runtime and its support glue) and three
injections (the content_root embedding, API 75 loot drops, API 74 consume effect).
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

import horizon


def run(command, **kwargs):
    result = subprocess.run(command, capture_output=True, text=True, **kwargs)
    if result.returncode:
        raise RuntimeError(result.stdout + result.stderr)
    return result


def snapshot(root):
    return {str(path.relative_to(root)): (hashlib.sha256(path.read_bytes()).hexdigest(),
                                          path.stat().st_mtime_ns)
            for path in root.rglob('*') if path.is_file()}


def audit(original, stage, plan):
    run(['cargo', 'run', '--quiet', '--locked', '--offline', '-p', 'native-mod-source-audit',
         '--', str(original), str(stage), str(plan)], cwd=horizon.ROOT)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--horizon', type=Path, default=horizon.DEFAULT_HORIZON)
    args = parser.parse_args()
    checkout = args.horizon.resolve()
    status = subprocess.check_output(['git', '-C', str(checkout), 'status', '--porcelain'])
    before = {p: (checkout / p).read_bytes() for p in horizon.COMPAT['source_sha256']}
    (horizon.ROOT / 'target').mkdir(exist_ok=True)
    with horizon.lock(horizon.ROOT / 'target/stage.lock'):
        with tempfile.TemporaryDirectory(prefix='native-stage-test-', dir=horizon.ROOT / 'target') as scratch:
            root = Path(scratch)
            output, changed = horizon.mixin_stage(checkout, root)
            assert changed
            first = snapshot(output)
            second, changed = horizon.mixin_stage(checkout, root)
            assert second == output and not changed and first == snapshot(output)
            plan = json.loads((root / 'plan.json').read_text())
            assert plan['schema'] == horizon.COMPAT['mixin_schema']
            assert len(plan['injections']) == 3 and len(plan['modules']) == 2
            original = next((root / 'original').glob('*/.horizon-mod-template.json')).parent
            audit(original, output, root / 'plan.json')
    assert all((checkout / p).read_bytes() == content for p, content in before.items())
    assert subprocess.check_output(['git', '-C', str(checkout), 'status', '--porcelain']) == status
    print(json.dumps({'status': 'ok', 'original_checkout_unchanged': True,
                      'only_planned_asts_changed': True,
                      'deterministic_bytes_and_mtimes': True,
                      'injections': 3, 'modules': 2}, indent=2))


if __name__ == '__main__':
    main()
