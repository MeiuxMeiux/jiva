#!/usr/bin/env bash
# art-pack — alternate avatar packs from ONE sheet image: art-pack.sh run|init|slice <pack> [seed|key]
# run <pack> [seed]: art-gen.sh pack:<pack> (paid model, cached, ledgered; 4×3 sheet of 12 busts on #ff00ff)
#   → init → slice → contact sheet. Cheap lever: one ~$0.05–0.10 call per pack instead of 12.
# init <pack>: packs/<pack>/pack.json = yaml title (site label) + default colors + yaml names on 1–12
#   (13–24 keep default names), portraits on 1–12, then roster.sh gen (same silhouettes as default).
# slice <pack> <key>: site/art/raw/<key>.png → foreground mask (not magenta) at 1/4 scale → 4-connected blobs
#   (specks merged into the nearest bust, strays dropped; a blob ≥1.6× median height = two touching busts,
#   cut at its thinnest middle row) → need exactly 12, bbox ≥40% of median → rows by y, then x →
#   raw/<key>-NN.png (neighbours painted magenta, 24px magenta pad) → ART_PACK=<pack> art-post.sh NN <key>-NN.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
act=${1:-}; pack=${2:-}; arg=${3:-}
[[ $act =~ ^(run|init|slice)$ && $pack =~ ^[a-z0-9-]+$ && $pack != default ]] || {
  echo "usage: art-pack.sh run|init|slice <pack> [seed|key]  (pack ≠ default)" >&2; exit 2; }
model=${ART_MODEL:-openai/gpt-image-2}

init() {
  python3 -I - "$root" "$pack" <<'PY'
import json, pathlib, sys
import yaml
root, name = pathlib.Path(sys.argv[1]), sys.argv[2]
spec = yaml.safe_load((root / f"site/art/packs/{name}.yaml").read_text(encoding="utf-8"))
p = json.loads((root / "packs/default/pack.json").read_text(encoding="utf-8"))
p["name"] = name
if spec.get("title"):
    p["title"] = spec["title"]
for s, y in zip(p["slots"], spec["slots"]):
    s["name"] = y["name"]
d = root / "packs" / name; d.mkdir(parents=True, exist_ok=True)
lines = ",\n".join("  " + json.dumps(s, ensure_ascii=False) for s in p["slots"])
title = f',\n "title": {json.dumps(p["title"], ensure_ascii=False)}' if "title" in p else ""
(d / "pack.json").write_text(f'{{"name": {json.dumps(name)}{title},\n "queen": {json.dumps(p["queen"])},\n "slots": [\n{lines}\n ]}}\n',
                             encoding="utf-8")
PY
  "$root/scripts/roster.sh" gen "$pack" >/dev/null
}

slice() {
  python3 -I - "$root" "$1" <<'PY'
import pathlib, sys
from PIL import Image, ImageChops
root, key = pathlib.Path(sys.argv[1]), sys.argv[2]
sys.path.insert(0, str(root / "site/art"))
from artkey import components  # noqa: E402
im = Image.open(root / f"site/art/raw/{key}.png").convert("RGB")
r, g, b = im.split()
fg = ImageChops.subtract(ImageChops.darker(r, b), g).point(lambda v: 255 if v < 100 else 0)
small = fg.reduce(4).point(lambda v: 255 if v > 40 else 0)
big, lab = components(small, small=0.004)
sm = small.tobytes(); W = small.width
for _ in range(12 - len(big)):                 # two busts touching vertically → cut at the thinnest row
    hs = sorted(b[0][3] - b[0][1] for b in big); t = max(big, key=lambda b: b[0][3] - b[0][1])
    x0, y0, x1, y1 = t[0]
    if y1 - y0 < 1.6 * hs[len(hs) // 2]:
        break
    lo, hi = y0 + (y1 - y0) * 3 // 10, y0 + (y1 - y0) * 7 // 10
    cut = min(range(lo, hi), key=lambda y: sum(1 for x in range(x0, x1) if sm[y * W + x] and lab[y * W + x] in t[2]))
    big.remove(t); big += [[(x0, y0, x1, cut), 0, t[2], (y0, cut)], [(x0, cut, x1, y1), 0, t[2], (cut, y1)]]
if len(big) != 12:
    sys.exit(f"art-pack: found {len(big)} busts, need 12: {[b[0] for b in big]}")
ar = sorted((b[0][2] - b[0][0]) * (b[0][3] - b[0][1]) for b in big)
if ar[0] < 0.4 * ar[6]:
    sys.exit(f"art-pack: uneven busts (smallest bbox {ar[0]} < 40% of median {ar[6]}); stray art? regenerate")
big.sort(key=lambda b: (b[0][1] + b[0][3]) / 2)
order = [x for row in range(3) for x in sorted(big[row * 4:row * 4 + 4], key=lambda b: b[0][0] + b[0][2])]
w, h = small.size
own = {}
for k, b in enumerate(order, 1):
    for n in b[2]:
        own.setdefault(n, []).append((b[3] if len(b) > 3 else (0, h), k))
lmap = Image.frombytes("L", small.size, bytes(next((k for (a, z), k in own[n] if a <= i // w < z), 255) if n in own
                                              else (255 if n else 0) for i, n in enumerate(lab))).resize(im.size, Image.NEAREST)
mag = Image.new("RGB", im.size, (255, 0, 255))
for k, b in enumerate(order, 1):
    cy = b[3] if len(b) > 3 else (-5, h + 5)       # a cut bust stops exactly at its cut line
    x0, y0, x1, y1 = (max(0, b[0][0] * 4 - 20), max(0, b[0][1] * 4 - 20, cy[0] * 4),
                      min(im.width, b[0][2] * 4 + 20), min(im.height, b[0][3] * 4 + 20, cy[1] * 4))
    other = lmap.crop((x0, y0, x1, y1)).point(lambda v, k=k: 255 if v not in (0, k) else 0)
    c = Image.composite(mag.crop((x0, y0, x1, y1)), im.crop((x0, y0, x1, y1)), other)
    out = Image.new("RGB", (c.width + 48, c.height + 48), (255, 0, 255)); out.paste(c, (24, 24))
    out.save(root / f"site/art/raw/{key}-{k:02d}.png")
    print(f"slice {k:02d} {x1 - x0}x{y1 - y0}")
PY
  for n in 01 02 03 04 05 06 07 08 09 10 11 12; do ART_PACK=$pack "$root/scripts/art-post.sh" "$n" "$1-$n"; done
}

case $act in
  init) init ;;
  slice) [[ -n $arg ]] || { echo "art-pack: slice needs a raw key" >&2; exit 2; }; init; slice "$arg"
         ART_PACK=$pack "$root/scripts/art-post.sh" sheet ;;
  run) out=$("$root/scripts/art-gen.sh" "pack:$pack" "$model" "${arg:-0}"); echo "$out"
       key=$(sed -n 's#.*-> site/art/raw/\([0-9a-f]*\)\.png$#\1#p' <<<"$out")
       [[ -n $key ]] || { echo "art-pack: no key from art-gen" >&2; exit 1; }
       init; slice "$key"; ART_PACK=$pack "$root/scripts/art-post.sh" sheet
       "$root/scripts/roster.sh" check "$pack" ;;
esac
