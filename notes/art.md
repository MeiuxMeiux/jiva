# art — image pipeline (v1 2026-10-17)

- `scripts/art-gen.sh <NN|pack:NAME|scene:NAME> <model> [seed]` → site/art/raw/<sha256(model+prompt+size+seed
  [+quality])[:24]>.png (gitignored); cache hit = no call. Ledger raw/ledger.tsv (ts model job cost key); hard stop
  when ledger total + est ≥ prompts.yaml `budget` (5.70). Jobs: slots (prompts.yaml), site/art/packs/NAME.yaml,
  site/art/scenes.yaml; each may set size/quality/est. Key only via keys.sh → env; image url must be https.
- gpt-image-2 ignores `background: transparent` (fake checkerboard): prompt flat #ff00ff, key it out
  (site/art/artkey.py). Never magenta/pink on a character. Glow art (emblems) → black bg + `unglow` instead.
- Prices (paid): 1024² medium $0.0537, 1536×1024 medium $0.0435, 1024² high $0.212, 1536×1024 high $0.166.
  `:free` = 3/day, low only. Run ≤4 calls at once (hard-stop check races).
- PACK SHEETS (the lever): one 1536×1024 medium image = 12 busts in a 4×3 grid → `scripts/art-pack.sh run NAME`
  (gen → init pack.json from yaml title/names + default colors → slice by magenta connected components, touching
  pairs cut at the thinnest row → art-post → contact.html → roster check). $0.0435/pack vs $0.64 per-slot; 256px
  quality holds. Fails loudly on ≠12 busts or a bust <40% of median (stray sparkles: say "no floating particles").
- `ART_PACK=NAME scripts/art-post.sh NN key|all|sheet`: picks in site/art/final/picks[-NAME].tsv; crop key
  <sheet>-NN books 1/12 of the sheet. Alt packs: despeck + 256-colour png (git weight); default stays byte-stable.
- `scripts/art-scene.sh run|post SCENE [key]` → site/src/img (crop | seamless tile | 3×3 emblem sheet);
  file → use in site/src/img/MANIFEST.md (hero-bg, header-banner, section-tile, emblem-<section id> ×9).
- Packs (28): default(anime) + comic-book old-masters fake-humans halloween fuzzy hip-hop laureates pixel-art
  robots claymation aliens ukiyo-e noir cyberpunk steampunk pirates astronauts knights wizards vikings chefs
  dinosaurs cats dogs mythic royals stained-glass. Site cap ≈30 packs.
- Rejected/redone: comic-book v0 (OpenAI safety 400, unbilled), halloween v1 (franchise-like stitched monster +
  gill-man), hip-hop v1 (brand logos/monogram), noir v1 (blonde starlet likeness, cigarettes), wizards v1 (loose
  sparkles broke slicing). Prompt rules: originals, no logos/letters, no real likenesses.
- Spend: 2026-10-13 $0.6979 (default pack); 2026-10-17 +$1.8683 (32 sheets $1.39, scenes $0.47) = $2.5662.
