# roster — pack format + slots (v0 2026-10-13)

Names and avatars are cosmetic labels, never personalities. No art spend; no copyrighted names/art.
- Pack = `packs/<name>/pack.json`: `{"name", "boss": {slot:0,name,color}, "slots": [24 × {slot,name,
  color,avatar}]}`; avatar paths are relative to the pack dir (`avatars/NN.svg`).
- `scripts/roster.sh gen|check|show [pack]` (default pack: default). gen = deterministic 64×64
  silhouette SVGs (head with a notch + notch-cut shoulders, seeded by slot via random.Random("jiva-
  roster-N"), slot color, transparent, no text, 6 lines each). check exits 1 on: ≠24 slots, slots out
  of order, extra/missing keys, dup names/colors, non-word names, missing/non-svg avatars, contrast.
- Colors: 24-hue wheel, HLS(i/24, L .62, S .75). All ≥3:1 on #060128 (worst: slot 17 #5555e7 3.68).
  Contrast math duplicated from site/scripts/contrast.py on purpose (site/ isn't a dependency).
- Caps: soft 6 / hard 12 bodies ⇒ slots 1–12 are live, 13–24 are reserve (future caps, swaps).
- Session → slot: worker wN → slot N (w1→1 …). Boss = slot 0, reserved near-white #f2f0ff outside
  the wheel so it never collides with a worker. Desk/watchdog get no slot (not bodies).
- Test art (e.g. fan rosters) only in `packs/local/` (gitignored); run `roster.sh check local`.
- Optional top-level `"title"` = site label. 27 alt packs (art-pack.sh, notes/art.md) reuse default colors + silhouettes.
- Wrappers: `jiva roster [gen|check|show] [pack]`, `just roster action pack`. Dash serves pack.json +
  avatars/ (default pack); names render as a #060128 chip in slot color, so contrast holds in light mode.
- Binding (core/souls.sh): `.jiva/souls.json` {"wN": {"slot": k}}; lowest free live slot (1–12) on first sight,
  kept across respawn/rotate/up/down (flock souls.lock, tmp→mv). 13th → unbound, label = session name. Overrides wN→N.
- Surfaces: watchdog binds launched sessions each tick → state.json sessions[].soul {name,slot,color}; bar chips
  "Ash·w1 86k"; status/watch rows "Ash · w1"; pane title "Ash · w1" (windows never renamed; Claude retitles, re-set per tick).
