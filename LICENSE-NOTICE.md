# Licence notice — Roots Classic for Horizon

- **Original mod:** Roots Classic 1.21.1-1.5.10, Copyright (c) 2016 Team Roots
  (authors Elucent, Lothrazar, Mrbysco), <https://github.com/Lothrazar/RootsClassic>.
- **Licence as read from the artefact:** `license="MIT"` in the jar's
  `META-INF/neoforge.mods.toml`
  (`RootsClassic-1.21.1-1.5.10.jar`, SHA-1 `7d02ec46e4d276ebf556cdd529a75108b4724efd`,
  kept at `ports/_shared/carry-work/rootsclassic/`), and the repository's
  `LICENSE.txt` ("The MIT License (MIT) / Copyright (c) 2016 Team Roots").
  Rank **0** (permissive).
- **What is carried here:** the mod's own textures, block/item models,
  blockstates and its `#rootsclassic:berries` item tag, copied byte-for-byte
  from that jar; the data files 26.3 spells differently (item definitions, loot
  tables, recipes, the `c:crops/wheat` tag the recipes need) were rewritten for
  26.3 from the jar's values. The Rust is a clean-room rewrite from the
  upstream source's *behaviour*, not a translation.
- **Status:** local-only until the maintainer approves publishing
  (ARCHITECTURE.md §8). MIT allows redistribution and derivatives; the original
  copyright and this notice travel with the port.
