#!/usr/bin/env bash
# One lease: the in-game scenario, then (only if it passed) the selftest and the e2e log
# checks. Lives in the port so the remote runner syncs it too.
#
# SDK format (2026-11-18): there is no `.hnmod` and no `tools/package.sh` any more — the
# package is `cargo horizon-mod build` (one flat `.hmod`), and the game must be the one the
# launcher built with it. See the STATUS header of `tools/e2e.sh`.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
PORT=$ROOT/rootsclassic
EV=$ROOT/_shared/evidence/rootsclassic
cd "$PORT"
mkdir -p "$EV"

status=0
{ bash tools/e2e.sh 2>&1; echo "E2E_EXIT=$?"; } | tee "$EV/e2e-sdk.log"
if grep -q "^EXIT:0$" "$EV/e2e-sdk.log"; then
    echo "e2e PASS"
else
    echo "e2e failed; skipping the selftest"
    echo "RUN_STATUS=1"
    exit 1
fi

{ SELFTEST=1 bash tools/e2e.sh 2>&1; echo "E2E_SELFTEST_EXIT=$?"; } | tee "$EV/e2e-sdk-selftest.log"
grep -q "^EXIT:0$" "$EV/e2e-sdk-selftest.log" && { echo "selftest exited 0: not fail-capable"; status=1; }

{ python3 "$ROOT/tools/check-e2e-logs.py" rootsclassic --strict 2>&1; echo "CHECKER_EXIT=$?"; } \
    | tee "$EV/check-e2e-logs.log"

echo "RUN_STATUS=$status"
exit "$status"
