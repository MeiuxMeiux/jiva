# site — static page, local only (v0 2026-10-13). Run: `just site-dev` (build + serve 127.0.0.1:<20000-60000>)
· `just site-build` · `just site-check` (builds first). Recipes live in site/site.just (root `import?`).
- src/index.html = `<!-- @include partials/x.html -->` shell; css/site.css = @imports. Both assembled
  into site/build/ (gitignored): edit partials, not build. Scripts are stdlib python3 -I. Mobile ≤860px: sections
  display:block (grid-column overrides lost to specificity). Minifier: HTML ws collapse except <pre>, CSS punct only, JS drops
  blank/`//` lines (no JS relying on ASI there). CSP twice: src/index.html meta + deploy/apache-jiva.conf, must match.
- site-check: html-validate if on PATH (else stdlib; `npx -y html-validate@8.18.2 site/build/index.html` clean 10-17).
  Bans third-party urls, style=, on*=, inline script/style, javascript:; files ≤150 lines (build/ exempt); initial load
  < 400 KB (minus assets.lazy(): other packs, manifest, tile/emblem art, raw .md) + whole build < 3 MB (286 KB / 1.05 MB @12 packs).
- build content-hashes css/js/woff2 + sha384 SRI. check.py then runs links.py (lychee or stdlib; SRI),
  contrast.py (WCAG; FAIL names nearest passing hex), drift.py, a11y.py. Header + robots asserts in check.py.
- v0.2 hero = real recording: `bash site/scripts/capture.sh [120] [5]` (read-only: .jiva/bar, capture-pane
  -p, jiva status/inbox; redacts tokens/abs paths/shas/branches) → src/hero/frames.txt; then
  `python3 -I site/scripts/hero.py` → hero.svg (SMIL) + hero-static.svg (<picture> reduced-motion). Both
  committed; build only copies. SMIL not CSS: check bans <style> in svg. Notch = motion.css keyframes,
  parsed by hero.py (CSS copy is otherwise unused). 2026-10-13 capture holds a real w1 respawn (86k→37k).
- Hero bar = watchdog format `N live · N flag · NNNk · 5h N%`; dashboard labels = state.json fields. Deploy is run by a person, never an agent (docs/DEPLOY.md). `just site-verify <url>` = verify.sh, curl only. site-dev uses scripts/serve.py: http.server strips `..` and serves / (200), which hid the check. verify-assets.sh: HEAD every ref, FAIL empty/wrong Content-Type (live .webp went untyped + nosniff).
- favicon.svg + og.svg hand-written in src/; `bash site/scripts/raster.sh` renders og.png (1200×630), apple-touch-icon, favicon.ico (committed). seo.py: head/OG/robots+sitemap/keepers/security.txt + leak scan of build (only jiva@meiuxmeiux.com, security.txt's first Contact, is exempt). No manifest (CSP default-src none).
- drift.py: `jiva <x>`/`just <x>` inside <code>/<pre> (+ hero frames, + verbs <ol>) must be in `jiva help` /
  `just --list` (FAIL); unnamed WARN, zeroed by partials/reference.html (§08; GENERATED, gitignored, by
  reference.py, site-build step 1). `drift.py <scratch src>` proves FAIL. Copy facts ← core/, not notes.
- a11y.py (build/index.html): lang, one h1, no heading skips, img alt, svg role=img named (+ hero/*.svg),
  link text, :focus-visible, reduced-motion (motion.css + <picture> static source), tokens == the fixed 5-colour palette (a11y.py PALETTE).
- Shots: serve over http (SRI blocks file://); playwright chrome-headless-shell --window-size=W,5600 --screenshot
  (#anchor = blank). Interactive: no playwright pkg; drive the shell over CDP with node 22's global WebSocket. contrast.py: tokens vs bg only; <code> on .sample needs its own rule. .cmd soft-wraps.
- Scrollbars never grey: css/scroll.css (:root scrollbar-color inherits; Chromium 121+ then ignores ::-webkit-*). scrollbars.py: palette hexes via var(), no greys; argv[1] = plant.
- §05 rotator: assets.py (via build.py) takes every packs/<n>/ (not local) with pack.json + avatars/01..12-s.webp
  → avatars/<n>/NN-s.<h>.webp + avatars/packs.<h>.json {v,packs:[{id,label,slots:[{slot,name,color|null,src}]}]}, default
  first. js/souls.js fetches on scroll; 6s auto, input freezes the bar in place (dimmed), resumes 3s after pointer leaves; morph = rotor.css. SITE_PACKS=<dir> = fake packs. Art:
  src/img/{hero-bg,header-banner,section-tile,emblem-<id>}.webp → generated --art-* css (art.css) iff present.
