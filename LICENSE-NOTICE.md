# Licence notice — Roots Classic for Horizon

This port carries the original mod's own assets and data and rewrites its
behaviour in Rust. The original licence and copyright notices are reproduced
verbatim in [LICENSE](LICENSE).

## Where the licence was read

- The pack jar `RootsClassic-1.21.1-1.5.10.jar` (SHA-1
  `7d02ec46e4d276ebf556cdd529a75108b4724efd`) declares `license="MIT"` in
  `META-INF/neoforge.mods.toml`, and the upstream repository's `LICENSE.txt` is
  "The MIT License (MIT) / Copyright (c) 2016 Team Roots".
- The jar is the ATM10 one, read for behaviour and assets only; the Rust is a
  clean-room rewrite, not a translation.

## The port

- Original: Roots Classic 1.21.1-1.5.10 by Elucent, Lothrazar and Mrbysco —
  MIT.
- Licence: **MIT**
- Port to Horizon by AdLf0208: the Rust runtime, the Horizon declarations and the
  build/verification tooling in this repository.
- Carried files: the mod's own textures, block/item models, blockstates and its
  `#rootsclassic:berries` item tag, copied byte-for-byte; the 26.3 data files
  (item declarations, loot tables, recipes, the `c:crops/wheat` tag) were written
  for 26.3 from the jar's values.
- No Mojang file is included.
