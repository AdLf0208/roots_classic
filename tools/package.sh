#!/usr/bin/env bash
# Package both artifacts, from the port's own sources:
#  - the `.hmod` in content/ via the pin's cargo-horizon-mod (build + check); it is then
#    copied into mixins/rootsclassic/data/ so the bundle embeds exactly the built file;
#  - the source-only `.hnmod` in the port root (tools/package.py, deterministic bytes),
#    which carries that content, and is checked as a native bundle.
# Run inside a build slot (it compiles the packaging tool):
#   ports/tools/build-slot.sh run --job rootsclassic-pack --port ports/rootsclassic \
#       --step package -- env CARGO_INCREMENTAL=0 tools/package.sh
set -euo pipefail

PORT=$(cd "$(dirname "$0")/.." && pwd)
HORIZON=${HORIZON:-$(cd "$PORT/../_shared/pins" && pwd)/horizon-1d63e0a}
LOGS=$PORT/target/ladder
mkdir -p "$LOGS"
cd "$PORT"

CARGO_TARGET_DIR=$PORT/target/carry-tools
export CARGO_TARGET_DIR
(cd content && cargo run --locked --offline --quiet \
    --manifest-path "$HORIZON/crates/cargo-horizon-mod/Cargo.toml" -- horizon-mod build) \
    2>&1 | tee "$LOGS/package-hmod.log"
cp content/target/horizon-mod/rootsclassic.hmod content/rootsclassic.hmod
(cd content && cargo run --locked --offline --quiet \
    --manifest-path "$HORIZON/crates/cargo-horizon-mod/Cargo.toml" -- horizon-mod check rootsclassic.hmod) \
    2>&1 | tee -a "$LOGS/package-hmod.log"
# The bundle's `data/` must be this exact build: tools/package.py refuses a stale copy.
cp content/rootsclassic.hmod mixins/rootsclassic/data/rootsclassic-content.hmod

python3 tools/package.py | tee "$LOGS/package-hnmod.log"

# The `.hnmod` is the delivered artifact: check it as the launcher reads it.
cargo horizon-mod check rootsclassic.hnmod --kind native-mod 2>&1 | tee "$LOGS/package-hnmod-check.log"

echo "== artifacts =="
for f in content/rootsclassic.hmod mixins/rootsclassic/data/rootsclassic-content.hmod rootsclassic.hnmod; do
    [ -f "$f" ] || { echo "missing $f"; exit 1; }
    size=$(stat -c %s "$f")
    sha=$(sha256sum "$f" | cut -d' ' -f1)
    entries=$(python3 -c "import zipfile,sys; print(len(zipfile.ZipFile(sys.argv[1]).namelist()))" "$f")
    echo "$f size=$size sha256=$sha entries=$entries"
done
cmp -s content/rootsclassic.hmod mixins/rootsclassic/data/rootsclassic-content.hmod \
    || { echo "the embedded copy is not the built content mod"; exit 1; }
python3 - <<'PY'
import zipfile
with zipfile.ZipFile('rootsclassic.hnmod') as archive:
    name = 'mixins/rootsclassic/data/rootsclassic-content.hmod'
    assert name in archive.namelist(), f'the bundle does not carry {name}'
    print(f"bundle carries {name} ({archive.getinfo(name).file_size} B)")
PY
