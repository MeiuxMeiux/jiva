#!/usr/bin/env bash
# roster — pack tooling: gen|check|show [pack]. Pack = packs/<pack>/pack.json (default: default).
# gen: deterministic notch silhouette SVGs (seeded by slot, slot color, transparent, no text).
# check: 24 slots, unique names/colors, avatars exist, contrast ≥3:1 on #060128; exits 1 on any fail.
# show: slot/name/color table. Names and avatars are cosmetic labels, never personalities.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
action=${1:-check}; pack=${2:-default}
dir="$root/packs/$pack"
case $action in gen|check|show) ;; *) echo "usage: roster.sh gen|check|show [pack]" >&2; exit 2;; esac
[[ -f $dir/pack.json ]] || { echo "roster: no $dir/pack.json" >&2; exit 1; }
exec python3 -I - "$action" "$dir" <<'PY'
import json, math, pathlib, random, re, sys

BG, NEED, SLOTS = (6, 1, 40), 3.0, 24
KEYS = {"slot", "name", "color", "avatar", "portrait"}
action, d = sys.argv[1], pathlib.Path(sys.argv[2])


def rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


def lum(c):  # WCAG 2 relative luminance (same math as site/scripts/contrast.py)
    ch = [v / 255 for v in c]
    ch = [v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in ch]
    return 0.2126 * ch[0] + 0.7152 * ch[1] + 0.0722 * ch[2]


def ratio(a, b):
    la, lb = sorted((lum(a), lum(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


def svg(slot, color):
    r = random.Random(f"jiva-roster-{slot}")  # str seed: stable across runs and python versions
    hr, hy, sw = r.randint(12, 16), r.randint(22, 27), r.randint(20, 27)  # head r, head y, half shoulders
    sy, n = hy + hr + r.randint(3, 6), r.randint(5, 9)                      # shoulder top, notch depth
    side = -1 if r.random() < 0.5 else 1                                    # notch side
    rot = r.uniform(-0.5, 0.5)                                              # notch angle jitter
    # head: polygon around the circle; points inside the notch wedge fold to an inward vertex
    pts = []
    for i in range(32):
        t = 2 * math.pi * i / 32
        dx, dy = math.cos(t), math.sin(t)
        if abs(math.atan2(dy, dx * side) - rot) < 0.45:
            dx, dy = dx * 0.55, dy * 0.55
        pts.append(f"{32 + hr * dx:.1f},{hy + hr * dy:.1f}")
    # shoulders: rounded top, the notch-side corner cut, flat base at the frame edge
    lx, rx = 32 - sw, 32 + sw
    if side < 0:
        body = f"M{lx} {sy + n} L{lx + n} {sy} Q32 {sy - 7} {rx} {sy} L{rx} 64 L{lx} 64 Z"
    else:
        body = f"M{lx} {sy} Q32 {sy - 7} {rx - n} {sy} L{rx} {sy + n} L{rx} 64 L{lx} 64 Z"
    return "\n".join([
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="64" height="64">',
        f'  <g fill="{color}">',
        f'    <polygon points="{" ".join(pts)}"/>',
        f'    <path d="{body}"/>',
        "  </g>",
        "</svg>", ""])


bad = []
try:
    p = json.loads((d / "pack.json").read_text(encoding="utf-8"))
except (OSError, ValueError) as e:
    print(f"FAIL roster: pack.json unreadable: {e}"); sys.exit(1)
slots = p.get("slots") if isinstance(p, dict) else None
if not isinstance(slots, list):
    print("FAIL roster: pack.json has no slots list"); sys.exit(1)

if action == "show":
    boss = p.get("boss")
    if boss:
        print(f"{0:>4}  {boss.get('name', 'Boss'):<8}  {boss.get('color', '')}  (boss, reserved)")
    for s in slots:
        live = "live" if s.get("slot", 99) <= 12 else "reserve"
        print(f"{s.get('slot', '?'):>4}  {s.get('name', '?'):<8}  {s.get('color', '?')}  {live}")
    sys.exit(0)

if action == "gen":
    for s in slots:
        out = d / s["avatar"]
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(svg(s["slot"], s["color"]), encoding="utf-8")
    print(f"roster: wrote {len(slots)} avatars into {d / 'avatars'}")
    sys.exit(0)

# check
if p.get("name") != d.name:
    bad.append(f"name {p.get('name')!r} != dir {d.name!r}")
if len(slots) != SLOTS:
    bad.append(f"{len(slots)} slots, need {SLOTS}")
seen = {"slot": set(), "name": set(), "color": set()}
for i, s in enumerate(slots, 1):
    if not isinstance(s, dict) or not {"slot", "name", "color", "avatar"} <= set(s) <= KEYS:
        bad.append(f"slot #{i}: keys must be slot,name,color,avatar[,portrait]"); continue
    if s["slot"] != i:
        bad.append(f"slot #{i}: slot={s['slot']} (must be {i}, in order)")
    if not re.fullmatch(r"[A-Z][a-z]{1,9}", str(s["name"])):
        bad.append(f"slot {i}: name {s['name']!r} must be one capitalised word, ≤10 chars")
    if not re.fullmatch(r"#[0-9a-f]{6}", str(s["color"])):
        bad.append(f"slot {i}: color {s['color']!r} must be lowercase #rrggbb"); continue
    for k in ("name", "color"):
        v = str(s[k]).lower()
        if v in seen[k]:
            bad.append(f"slot {i}: duplicate {k} {s[k]}")
        seen[k].add(v)
    cr = ratio(rgb(s["color"]), BG)
    if cr < NEED:
        bad.append(f"slot {i}: {s['color']} on #060128 = {cr:.2f}:1 < {NEED}")
    av = d / str(s["avatar"])
    if not av.is_file() or ".." in str(s["avatar"]):
        bad.append(f"slot {i}: avatar {s['avatar']} missing")
    elif not av.read_text(encoding="utf-8").lstrip().startswith("<svg") or len(av.read_text().splitlines()) > 40:
        bad.append(f"slot {i}: avatar {s['avatar']} not an svg ≤40 lines")
    if "portrait" in s:  # optional raster: NN.webp (≤40 KB) + NN.png sibling, both real files
        pt = d / str(s["portrait"])
        pn = pt.with_suffix(".png")
        if ".." in str(s["portrait"]) or pt.suffix != ".webp" or not pt.is_file() or not pn.is_file():
            bad.append(f"slot {i}: portrait {s['portrait']} needs .webp + .png files")
        elif pt.read_bytes()[8:12] != b"WEBP" or pn.read_bytes()[:4] != b"\x89PNG" or pt.stat().st_size > 40960:
            bad.append(f"slot {i}: portrait {s['portrait']} not webp ≤40 KB + png")
        th = pt.with_name(pt.stem + "-s.webp")  # optional 128px site thumb twin (art-post.sh)
        if th.is_file() and (th.read_bytes()[8:12] != b"WEBP" or th.stat().st_size > 8192):
            bad.append(f"slot {i}: thumb {th.name} not webp ≤8 KB")
boss = p.get("boss")
if boss is not None:
    bc = str(boss.get("color", ""))
    if boss.get("slot") != 0 or not re.fullmatch(r"#[0-9a-f]{6}", bc) or bc in seen["color"]:
        bad.append("boss must be slot 0 with a unique lowercase #rrggbb color")
    elif ratio(rgb(bc), BG) < NEED:
        bad.append(f"boss color {bc} under {NEED}:1")
for b in bad:
    print("FAIL roster:", b)
print(f"roster: {d.name} {'FAIL' if bad else 'ok'} ({len(slots)} slots, {len(bad)} problems)")
sys.exit(1 if bad else 0)
PY
