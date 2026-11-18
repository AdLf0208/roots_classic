#!/usr/bin/env bash
# The SDK ladder for rootsclassic, in one lease, with every log kept as evidence.
# Run: BUILD_LOCAL=1 ports/tools/build-slot.sh run --job sdk-rc --port ports/rootsclassic \
#          --step check -- bash tools/sdk-ladder.sh
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
PORT=$ROOT/rootsclassic
EV=$ROOT/_shared/evidence/rootsclassic/sdk-0b14f8a
mkdir -p "$EV"
cd "$PORT"
export CARGO_INCREMENTAL=0
status=0

run() { # name command...
    local name=$1; shift
    { "$@" 2>&1; echo "${name}_EXIT:$?"; } | tee "$EV/$name.log" | tail -3
    grep -q "${name}_EXIT:0$" "$EV/$name.log" || status=1
}

# 1. the carried rules, byte for byte, and their own tests
{
    cmp src/runtime.rs "$ROOT/_shared/evidence/rootsclassic/retired-hnmod-0.1.0/mixins/rootsclassic/runtime.rs" \
        && echo "runtime.rs is byte-identical to the retired .hnmod's"
    sha256sum src/runtime.rs
} > "$EV/runtime-carry.log" 2>&1
cmp -s src/runtime.rs "$ROOT/_shared/evidence/rootsclassic/retired-hnmod-0.1.0/mixins/rootsclassic/runtime.rs" \
    || status=1

# 2. compile + every test (14 runtime + 5 glue)
run unit cargo test

# 3. lints of this crate only
{ cargo fmt --check 2>&1; echo "FMT_EXIT:$?"; } | tee "$EV/fmt.log" | tail -2
grep -q "FMT_EXIT:0$" "$EV/fmt.log" || status=1
run clippy cargo clippy --all-targets --offline -- -D warnings

# `cargo fmt` can reformat src/runtime.rs; the byte-for-byte rule outranks the formatter.
cmp -s src/runtime.rs "$ROOT/_shared/evidence/rootsclassic/retired-hnmod-0.1.0/mixins/rootsclassic/runtime.rs" \
    || { echo "runtime.rs changed during the ladder"; status=1; }

# 4. the package (twice: the bytes must not move) and the registry's checks
run build bash -c 'rm -f Cargo.lock && cargo horizon-mod build'
cp target/horizon-mod/rootsclassic.hmod ./rootsclassic.hmod
sha256sum rootsclassic.hmod > "$EV/sha256-first.txt"
run build-again bash -c 'rm -f Cargo.lock && cargo horizon-mod build'
cmp -s target/horizon-mod/rootsclassic.hmod ./rootsclassic.hmod \
    || { echo "the second build differs from the first" | tee -a "$EV/sha256-first.txt"; status=1; }
sha256sum rootsclassic.hmod > "$EV/sha256.txt"
cat "$EV/sha256-first.txt" "$EV/sha256.txt" | tee "$EV/sha256-both.txt"

run check cargo horizon-mod check rootsclassic.hmod
run fits cargo horizon-mod fits rootsclassic.hmod --build nightly
{ cargo horizon-mod check rootsclassic.hmod --uses 2>&1; echo "USES_EXIT:$?"; } \
    | tee "$EV/uses.log" | tail -2
python3 - "$PORT" "$EV" <<'EOF'
import json, sys, zipfile
port, ev = sys.argv[1], sys.argv[2]
z = zipfile.ZipFile(f"{port}/rootsclassic.hmod")
names = z.namelist()
with open(f"{ev}/package-entries.log", "w") as out:
    out.write(f"{len(names)} entries\n")
    for name in names:
        out.write(name + "\n")
uses = json.loads(z.read("uses.json"))
with open(f"{ev}/uses.json", "w") as out:
    json.dump(uses, out, indent=1)
    out.write("\n")
print(len(names), "entries;", len(uses["entries"]), "uses entries")
EOF

# 5. the content is still what the jar carries
{ python3 tools/carry_content.py --check 2>&1; echo "CARRY_EXIT:$?"; } \
    | tee "$EV/carry-check.log" | tail -2
grep -q "CARRY_EXIT:0$" "$EV/carry-check.log" || status=1

echo "LADDER_STATUS=$status"
exit "$status"
