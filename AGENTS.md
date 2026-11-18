# Working on this Horizon native mod

This is a **flat SDK package** (mod API 0.2): `horizon-mod.toml` + `Cargo.toml` + `src/lib.rs`
(`impl mod_api::Hooks`) + `src/runtime.rs` (the pure rules and their tests) + `assets/` + `data/`.
Horizon retired the `.hnmod` container in the mod-API merge (#16941), so there is no
`compatibility.json`, `mixins/<id>/`, `horizon-mixin.toml`, plan/injection schema,
`rust-toolchain.toml` or `content/` here, and none of them should be recreated. `notes.md` →
`## Migration to the SDK format` is the current state; everything above it is the retired bundle's
history.

> **Build slots (v2):** every build/test goes through the campaign runner
> (`ports/tools/build-slot.sh` from the campaign root). It **blocks in the kernel** until a slot is
> free, so **never poll and never background a build**; a timeout exits **75**. It does **not**
> `cd` into the port — wrap the command (`bash -c 'cd ports/<id> && …'`) and never pass
> `--target-dir`. Read `../_shared/build-slots-usage.md` before running anything.

```sh
ports/tools/build-slot.sh run --job sdk-rc --port ports/rootsclassic --step test \
    -- bash -c 'cd ports/rootsclassic && cargo test'
ports/tools/build-slot.sh run --job sdk-rc --port ports/rootsclassic --step build \
    -- bash -c 'cd ports/rootsclassic && rm -f Cargo.lock && cargo horizon-mod build'
ports/tools/build-slot.sh run --job sdk-rc --port ports/rootsclassic --step check \
    -- bash -c 'cd ports/rootsclassic && cargo horizon-mod check rootsclassic.hmod'
# the whole ladder, with its logs:
ports/tools/build-slot.sh run --job sdk-rc --port ports/rootsclassic --step check \
    -- bash ports/rootsclassic/tools/sdk-ladder.sh
```

- `cargo horizon-mod` uses the pinned SDK in `.horizon/sdk/` (gitignored, never packed). It can be
  seeded from a green sibling port (`cp -a ../imfast/.horizon/sdk .horizon/sdk`, same pin) instead
  of waiting for a fetch. `build` packs the `.hmod`; it does **not** compile against the game —
  that is `horizon-launcher native-build . --instance <instance> --trust-native-code`.
- **`src/runtime.rs` is byte-identical to the retired bundle's `runtime.rs` and must stay so**
  (`cmp` against `../_shared/evidence/rootsclassic/retired-hnmod-0.1.0/mixins/rootsclassic/runtime.rs`).
  `cargo fmt` formats it too: check `cmp` after every fmt run and restore, do not let the
  formatter win. New rule → a test in `runtime.rs`; new glue → a private fn and a test in
  `lib.rs`.
- `Cargo.lock` must not be in the package: `cargo test`/`clippy` write one, so delete it in the
  same command as each `cargo horizon-mod build`, and edit nothing else between the build and the
  quoted sha256 (a README edit changes the artifact).
- Only the API the SDK publishes: `cargo horizon-mod hooks <text>` finds the exact method; never
  guess a name, and record an API gap in `notes.md` instead of faking one.
- The delivered package is `rootsclassic.hmod` **in the port root**, never in `target/`;
  `LICENSE` and `LICENSE-NOTICE.md` travel inside it.
- Content stays where the default package layout puts it: `assets/rootsclassic/` and
  `data/rootsclassic/` (plus `data/c/`). `tools/carry_content.py --check` must report
  `79 files, 0 pending` after any content edit.
- Keep the port separate from Horizon and horizon-mixins; never modify the pin checkouts, never
  commit binaries, exported sources or Minecraft assets, and never put Mojang files in the tree.
- `python3 ports/tools/check-skills.py --notes ports/rootsclassic` must stay green, and `notes.md`
  records every claim with its command and output.
