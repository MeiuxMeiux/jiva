#!/usr/bin/env bash
# art-scene — site scene art: art-scene.sh run|post <scene> [key]  (scenes in site/art/scenes.yaml)
# run <scene>: art-gen.sh scene:<scene> (paid model, cached, ledgered) then post.
# post <scene> <key>: site/art/raw/<key>.png → site/src/img/<out> by the scene's post mode:
#   crop    — cover-crop to w×h (vertical centre at `band`), LANCZOS, webp stepped down to ≤ kb KB.
#   tile    — seamless: blend the image with its half-offset roll under a centre-weighted mask (edges come
#             from the rolled copy, so opposite edges match), resize to w×h, ≤ kb KB.
#   emblems — 3×3 sheet on black: glow mask at 1/4 → blobs unioned per grid cell (by centre) → unglow
#             (alpha = brightness) → trim, centred square, w px → emblem-<id>.webp (≤ kb KB, transparent).
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
act=${1:-}; scene=${2:-}; key=${3:-}
[[ $act =~ ^(run|post)$ && $scene =~ ^[a-z0-9-]+$ ]] || { echo "usage: art-scene.sh run|post <scene> [key]" >&2; exit 2; }
if [[ $act == run ]]; then
  out=$("$root/scripts/art-gen.sh" "scene:$scene" "${ART_MODEL:-openai/gpt-image-2}" "${ART_SEED:-0}"); echo "$out"
  key=$(sed -n 's#.*-> site/art/raw/\([0-9a-f]*\)\.png$#\1#p' <<<"$out")
fi
[[ -n $key ]] || { echo "art-scene: no raw key" >&2; exit 1; }
exec python3 -I - "$root" "$scene" "$key" <<'PY'
import pathlib, sys
import yaml
from PIL import Image, ImageChops, ImageDraw, ImageFilter
root, name, key = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
sys.path.insert(0, str(root / "site/art"))
from artkey import components, despeck, unglow, webp_under  # noqa: E402
sc = yaml.safe_load((root / "site/art/scenes.yaml").read_text(encoding="utf-8"))["scenes"][name]
im = Image.open(root / f"site/art/raw/{key}.png").convert("RGB")
dst = root / "site/src/img"; dst.mkdir(parents=True, exist_ok=True)
W, H, kb = sc["w"], sc["h"], sc["kb"]


def save(img, fname, alpha=False):
    data, q = webp_under(img, kb, alpha_q=90 if alpha else 100)
    if len(data) > kb * 1024:
        sys.exit(f"art-scene: {fname} {len(data)} B > {kb} KB even at q{q}")
    (dst / fname).write_bytes(data)
    print(f"scene {name} -> site/src/img/{fname} {img.size[0]}x{img.size[1]} {len(data) // 1024} KB q{q}")


if sc["post"] == "crop":
    s = max(W / im.width, H / im.height)
    r = im.resize((round(im.width * s), round(im.height * s)), Image.LANCZOS)
    y = min(max(0, round(r.height * sc.get("band", 0.5) - H / 2)), r.height - H)
    x = (r.width - W) // 2
    save(r.crop((x, y, x + W, y + H)), sc["out"])
elif sc["post"] == "tile":
    w, h = im.size
    rolled = ImageChops.offset(im, w // 2, h // 2)
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).rectangle((w // 4, h // 4, w * 3 // 4, h * 3 // 4), fill=255)
    m = m.filter(ImageFilter.GaussianBlur(w // 10))       # 255 in the middle, 0 at every edge
    save(Image.composite(im, rolled, m).resize((W, H), Image.LANCZOS), sc["out"])
else:
    ids = sc["ids"]
    fg = im.convert("L").point(lambda v: 255 if v > 40 else 0).reduce(4).point(lambda v: 255 if v > 20 else 0)
    big, _ = components(fg, small=0.0005)
    cells = {}                                             # union blobs per 3×3 cell (by blob centre)
    for b in big:
        c = (int(3 * (b[0][1] + b[0][3]) / 2 / fg.height), int(3 * (b[0][0] + b[0][2]) / 2 / fg.width))
        o = cells.get(c, b)
        cells[c] = [(min(o[0][0], b[0][0]), min(o[0][1], b[0][1]), max(o[0][2], b[0][2]), max(o[0][3], b[0][3]))]
    if len(cells) != len(ids):
        sys.exit(f"art-scene: emblems fill {len(cells)} of 9 grid cells: {sorted(cells)}")
    order = [cells[c] for c in sorted(cells)]
    for eid, b in zip(ids, order):
        x0, y0, x1, y1 = (max(0, b[0][0] * 4 - 24), max(0, b[0][1] * 4 - 24),
                          min(im.width, b[0][2] * 4 + 24), min(im.height, b[0][3] * 4 + 24))
        e = despeck(unglow(im.crop((x0, y0, x1, y1))), 60)
        e = e.crop(e.getchannel("A").getbbox())
        s = max(e.size) + 8
        sq = Image.new("RGBA", (s, s), (0, 0, 0, 0)); sq.paste(e, ((s - e.width) // 2, (s - e.height) // 2))
        save(sq.resize((W, H), Image.LANCZOS), f"emblem-{eid}.webp", alpha=True)
PY
