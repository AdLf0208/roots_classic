#!/usr/bin/env bash
# The SDK ladder for rootsclassic 0.2.1 (slice 2), in one lease, with every log kept as evidence.
# Run from the campaign root:
#   BUILD_LOCAL=1 ports/tools/build-slot.sh run --job W1-rootsclassic --port ports/rootsclassic \
#       --step check -- bash ports/rootsclassic/tools/sdk-ladder.sh
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
PORT=$ROOT/rootsclassic
EV=$ROOT/_shared/evidence/rootsclassic/sdk-0a875da
RETIRED=$ROOT/_shared/evidence/rootsclassic/retired-hnmod-0.1.0/mixins/rootsclassic/runtime.rs
mkdir -p "$EV"
cd "$PORT"
export CARGO_INCREMENTAL=0
status=0

run() { # name command...
    local name=$1; shift
    { "$@" 2>&1; echo "${name}_EXIT:$?"; } | tee "$EV/$name.log" | tail -3
    grep -q "${name}_EXIT:0$" "$EV/$name.log" || status=1
}

# 1. slice 1's rules are untouched: the retired file is a byte prefix of the current one, and the
#    slice-2 section is appended after it (`cargo fmt` may reflow only the new part).
{
    retired=$(stat -c%s "$RETIRED")
    head -c "$retired" src/runtime.rs | cmp - "$RETIRED" \
        && echo "slice 1 of runtime.rs is still byte-identical to the retired .hnmod's (${retired} B prefix)"
    echo "slice 1 prefix bytes: $retired; whole file bytes: $(stat -c%s src/runtime.rs)"
    sha256sum src/runtime.rs
} > "$EV/runtime-carry.log" 2>&1
head -c "$(stat -c%s "$RETIRED")" src/runtime.rs | cmp -s - "$RETIRED" || status=1

# 2. compile + every test (14 slice-1 runtime + 7 slice-2 runtime + 8 glue). The log is
#    `sdk-test.log` as well, because `verify-sdk-package.py` reads that exact name.
run unit cargo test
cp "$EV/unit.log" "$ROOT/_shared/evidence/rootsclassic/sdk-test.log"

# 3. lints of this crate only
{ cargo fmt --check 2>&1; echo "FMT_EXIT:$?"; } | tee "$EV/fmt.log" | tail -2
grep -q "FMT_EXIT:0$" "$EV/fmt.log" || status=1
run clippy cargo clippy --all-targets -- -D warnings

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
# The pin run is a tautology; a *different* nightly is the real question. Both logs are kept
# under the names the brief asks for, both from the delivered file.
run sdk-fits cargo horizon-mod fits rootsclassic.hmod --build 0a875da
run sdk-fits-other cargo horizon-mod fits rootsclassic.hmod --build 0b14f8a
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
print("Cargo.lock packed:", any(name.endswith("Cargo.lock") for name in names))
EOF

# 5. the content is still what the jar carries
{ python3 tools/carry_content.py --check 2>&1; echo "CARRY_EXIT:$?"; } \
    | tee "$EV/carry-check.log" | tail -2
grep -q "CARRY_EXIT:0$" "$EV/carry-check.log" || status=1

echo "LADDER_STATUS=$status"
exit "$status"
