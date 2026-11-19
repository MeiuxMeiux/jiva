# site/src/img — scene art (generated; source: site/art/scenes.yaml, scripts/art-scene.sh)

Regenerate from the raw cache without spend: `scripts/art-scene.sh post <scene> <raw key>` (keys in site/art/raw/ledger.tsv).
Palette (2026-11-19 re-skin, brief 4.4): Indigo Night #0b0a2a, Lotus Cream #f6ead8, Marigold #f2a900, Vermilion #e2452b,
Peacock #0f7c82. hero-bg (clay oil lamps on indigo water), header-banner + section-tile (block-print marigolds) come from
site/art/wc/jobs.json (ImageRouter, ledgered); emblems are the old line art recoloured to flat marigold. All webp; emblems carry alpha.

| file | size | intended use |
|---|---|---|
| hero-bg.webp | 1600×900, 54 KB | `#top` hero background (first paint); left half kept dark for the headline, lit clay lamps fill the right, darkened toward the left |
| header-banner.webp | 1600×120, 24 KB | header/top strip banner (first paint); block-print marigold strip under a heavy veil |
| section-tile.webp | 384×384, 11 KB | seamless repeating `.band` section background (block-print marigolds, shown at 7% opacity) |
| emblem-problem.webp | 144×144, transparent | §01 The problem — tangled overlapping terminal windows |
| emblem-how.webp | 144×144, transparent | §02 How it works — one node fanning out to two (desk/queen/workers) |
| emblem-verbs.webp | 144×144, transparent | §03 Six verbs — six arrows circling a centre |
| emblem-ceiling.webp | 144×144, transparent | §04 Reincarnation at ~200k (`#ceiling`) — phoenix in a cycle arrow |
| emblem-souls.webp | 144×144, transparent | §05 The party (`#souls`) — three bust silhouettes |
| emblem-dashboard.webp | 144×144, transparent | §06 The watchdog view — eye inside a radar gauge |
| emblem-security.webp | 144×144, transparent | §07 Security, plainly — padlock on a shield |
| emblem-install.webp | 144×144, transparent | §08 Built with itself (`#install`) — hand drawing a gear |
| emblem-reference.webp | 144×144, transparent | §09 Reference — open book with ribbons |

Emblems are 144px sources meant to display at 72px (2× density).
