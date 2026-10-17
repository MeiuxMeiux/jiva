#!/usr/bin/env bash
# art-post — art-post.sh <slot NN> <raw key> | all | sheet
# <NN> <key>: site/art/raw/<key>.png (flat #ff00ff chroma backdrop; the image API paints fake checkerboards
#   instead of real alpha) → key out magenta (edge flood + pure-magenta islands, soft edge + despill), trim the
#   alpha bbox, square-pad (bottom-aligned bust), ≤256px → packs/default/avatars/NN.png (lossless) + NN.webp
#   (lossless alpha, ≤40 KB) + NN-s.webp (128px site thumb, lossy alpha, ≤8 KB); records slot/key/model/cost
#   in site/art/final/picks.tsv. all: re-post every pick from the raw cache (no API calls, ledger untouched).
# ART_PACK=<name> (env, default "default") targets packs/<name> + final/picks-<name>.tsv; a raw key <sheet>-NN
#   (an art-pack.sh crop) books 1/12 of the sheet's ledger cost. Keying lives in site/art/artkey.py.
# sheet: packs/<pack>/contact.html — all picks with name, slot color, cost (relative files, no network).
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
[[ ${1:-} == sheet || ${1:-} == all || $# -eq 2 ]] || { echo "usage: art-post.sh <slot NN> <raw key> | all | sheet" >&2; exit 2; }
exec python3 -I - "$root" "$@" <<'PY'
import html, io, json, os, pathlib, sys
from PIL import Image

root = pathlib.Path(sys.argv[1]); args = sys.argv[2:]
sys.path.insert(0, str(root / "site/art"))
from artkey import despeck, keyout  # noqa: E402  (site/art/artkey.py, shared with art-pack/art-scene)
name = os.environ.get("ART_PACK", "default")
pack = root / "packs" / name
picks = root / "site/art/final" / ("picks.tsv" if name == "default" else f"picks-{name}.tsv")


def read_picks():
    rows = {}
    if picks.is_file():
        for ln in picks.read_text().splitlines()[1:]:
            f = ln.split("\t"); rows[f[0]] = f
    return rows


def post(slot, key):
    raw = root / f"site/art/raw/{key}.png"
    if not raw.is_file():
        sys.exit(f"art-post: no {raw}")
    im = keyout(Image.open(raw).convert("RGB"))
    im = despeck(im, 80) if name != "default" else im  # default picks predate despeck; keep them byte-stable
    bbox = im.getchannel("A").getbbox()
    if not bbox:
        sys.exit("art-post: image keyed to nothing")
    im = im.crop(bbox)
    s = max(im.size)
    sq = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    sq.paste(im, ((s - im.width) // 2, s - im.height))
    sq = sq.resize((256, 256), Image.LANCZOS) if s > 256 else sq
    av = pack / "avatars"; av.mkdir(parents=True, exist_ok=True)
    png = sq if name == "default" else sq.quantize(256, method=Image.FASTOCTREE, dither=Image.FLOYDSTEINBERG)
    png.save(av / f"{slot}.png", optimize=True)    # alt packs: 256-colour png keeps git light (raw cache = master)
    for q in range(90, 20, -5):                      # lossy colour, lossless alpha, shrink to ≤40 KB
        buf = io.BytesIO(); sq.save(buf, "WEBP", quality=q, alpha_quality=100, method=6)
        if buf.tell() <= 40 * 1024:
            break
    (av / f"{slot}.webp").write_bytes(buf.getvalue())
    th = sq.resize((128, 128), Image.LANCZOS)
    for tq in range(80, 5, -5):                      # site thumb: lossy colour + alpha, ≤8 KB
        tb = io.BytesIO(); th.save(tb, "WEBP", quality=tq, alpha_quality=max(tq, 50), method=6)
        if tb.tell() <= 8 * 1024:
            break
    (av / f"{slot}-s.webp").write_bytes(tb.getvalue())
    led = {}
    for ln in (root / "site/art/raw/ledger.tsv").read_text().splitlines()[1:]:
        f = ln.split("\t"); led[f[4]] = f
    rows = read_picks()
    base, n = (key, 1) if key in led else (key.rsplit("-", 1)[0], 12)  # sheet crop <key>-NN: 1/12 of the sheet
    rows[slot] = [slot, key, led[base][1], f"{float(led[base][3]) / n:.6f}"]
    picks.parent.mkdir(parents=True, exist_ok=True)
    picks.write_text("slot\tkey\tmodel\tcost\n" + "".join("\t".join(rows[k]) + "\n" for k in sorted(rows)))
    print(f"post {slot} <- {key}: {buf.tell() // 1024} KB webp q{q}, {(av / f'{slot}.png').stat().st_size // 1024} KB png,"
          f" thumb {tb.tell()} B q{tq}")


def sheet():
    p = json.loads((pack / "pack.json").read_text(encoding="utf-8"))
    rows, cards, total = read_picks(), [], 0.0
    for s in p["slots"]:
        nn = f"{s['slot']:02d}"
        if nn not in rows:
            continue
        cost = float(rows[nn][3]); total += cost
        c, n = html.escape(s["color"]), html.escape(s["name"])
        cards.append(f'<figure style="--c:{c}"><img src="avatars/{nn}.webp" alt="{n}" width="256" height="256">'
                     f'<figcaption><b>{nn} {n}</b><span>{c}</span><span>${cost:.4f}</span></figcaption></figure>')
    css = ("body{margin:0;padding:24px 16px;background:#060128;color:#f0e2e2;font:14px/1.4 system-ui,sans-serif}"
           "h1{font-size:18px;margin:0 0 16px}main{display:grid;gap:16px;grid-template-columns:repeat(auto-fill,"
           "minmax(180px,1fr))}figure{margin:0;padding:10px;background:#0d0640;border:2px solid var(--c);"
           "clip-path:polygon(14px 0,100% 0,100% calc(100% - 14px),calc(100% - 14px) 100%,0 100%,0 14px)}"
           "img{width:100%;height:auto;display:block}figcaption{display:flex;justify-content:space-between;"
           "gap:6px;margin-top:6px}b{color:var(--c)}span{opacity:.8;font-size:12px}"
           "html{scrollbar-color:#ef4fbc #060128}")
    out = pack / "contact.html"
    out.write_text('<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" '
                   f'content="width=device-width,initial-scale=1"><title>{html.escape(name)} pack portraits</title>'
                   f'<style>{css}</style></head><body><h1>packs/{html.escape(name)} — {len(cards)} portraits, total '
                   f'${total:.4f}</h1><main>{"".join(cards)}</main></body></html>\n', encoding="utf-8")
    print(f"sheet: {out.relative_to(root)} ({len(cards)} portraits, ${total:.4f})")


if args[0] == "sheet":
    sheet()
elif args[0] == "all":
    for nn, row in read_picks().items():
        post(nn, row[1])
else:
    post(args[0], args[1])
PY
