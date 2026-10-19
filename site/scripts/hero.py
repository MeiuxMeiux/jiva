#!/usr/bin/env python3
"""hero render — site/src/hero/frames.txt (capture.sh) → hero.svg (animated) + hero-static.svg (final
frame, served under prefers-reduced-motion via <picture>). SMIL only: check.py bans <style>/script in
svg. The respawn reuses motion.css's dissolve/reform clip-path keyframes (parsed, % → bbox fractions).
If the capture holds a real respawn (a token count dropping), that row is used; otherwise the
highest-token soul is replayed through the respawn at the end of the loop. Stdlib. Usage: hero.py"""
import html, pathlib, re

ROOT = pathlib.Path(__file__).resolve().parent.parent
HERO = ROOT / "src" / "hero"
TEXT, BG, PINK, CYAN, GREEN, MUTE, LINE = "#f0e2e2", "#060128", "#ef4fbc", "#00ffd8", "#21ff00", "#a99fc0", "#2a2550"
W, ROW, TOP, STEP, FONT = 640, 34, 52, 0.8, "JetBrains Mono, ui-monospace, Menlo, monospace"
REBIRTH = 3.0  # seconds of the loop spent on the respawn


def parse():
    text = (HERO / "frames.txt").read_text(encoding="utf-8")
    date = re.search(r"capture (\d{4}-\d{2}-\d{2})", text).group(1)
    frames = []
    for chunk in text.split("=== frame ")[1:]:
        bar = re.search(r"^bar: (.+)$", chunk, re.M).group(1)
        rows = re.findall(r"^\s{4}(\S+)\t(\S+)\t(\d+)k$", chunk, re.M)
        inbox = re.findall(r"^\s{2}\d\d:\d\d (\S+)\s+(\S+?):? (.*)$", chunk, re.M)
        frames.append({"bar": bar, "rows": [(n, s, int(k)) for n, s, k in rows], "inbox": inbox})
    return date, frames


def notch_keys():
    css = (ROOT / "src" / "css" / "motion.css").read_text(encoding="utf-8")
    out = {}
    for name in ("dissolve", "reform"):
        body = re.search(rf"@keyframes {name} \{{(.*?)\n\}}", css, re.S).group(1)
        steps = re.findall(r"(\d+)%\s*\{\s*clip-path: polygon\(([^)]*)\)", body)
        pts = lambda p: " ".join(",".join(str(float(v.rstrip("%") or 0) / (100 if v.endswith("%") else 1))
                                          for v in xy.split()) for xy in p.split(","))
        out[name] = [(int(pc) / 100, pts(poly)) for pc, poly in steps]
    return out


def t(x, y, s, fill=TEXT, size=13, weight=400, anchor="start"):
    a = f' text-anchor="{anchor}"' if anchor != "start" else ""
    return (f'<text x="{x}" y="{y}" fill="{fill}" font-size="{size}" font-weight="{weight}"{a}>'
            f"{html.escape(s)}")


def shown(spans, total, anim):
    """visible only during [a, b) seconds of the loop; discrete opacity animation."""
    if not anim:
        return ""
    keys, vals = [0.0], ["0"]
    for a, b in spans:
        keys += [a / total, b / total]
        vals += ["1", "0"]
    if keys[1] == 0.0:
        keys, vals = keys[1:], vals[1:]
    return (f'<animate attributeName="opacity" calcMode="discrete" dur="{total}s" repeatCount="indefinite" '
            f'keyTimes="{";".join(f"{k:.4f}" for k in keys)}" values="{";".join(vals)}"/>')


def series(values, total, anim, draw):
    """one element per run of equal values; static mode keeps only the final value."""
    runs, out = [], []
    for i, v in enumerate(values):
        if runs and runs[-1][0] == v:
            runs[-1][2] = (i + 1) * STEP
        else:
            runs.append([v, i * STEP, (i + 1) * STEP])
    if not anim:
        return draw(runs[-1][0]) + "</text>"
    runs[-1][2] = total
    for v, a, b in runs:
        out.append(draw(v) + shown([(a, b)], total, True) + "</text>")
    return "".join(out)


def render(date, frames, anim):
    names = [n for n, _, _ in frames[-1]["rows"]]
    toks = {n: [dict((r[0], r[2]) for r in f["rows"]).get(n, 0) for f in frames] for n in names}
    drop = next((n for n in names if any(b < a - 20 for a, b in zip(toks[n], toks[n][1:]))), None)
    soul = drop or max(names, key=lambda n: toks[n][-1])
    at = next(i for i, (x, y) in enumerate(zip(toks[soul], toks[soul][1:]), 1) if y < x - 20) if drop else len(frames)
    total = round(len(frames) * STEP + (0 if drop else REBIRTH), 2)
    H = TOP + ROW * len(names) + 92
    o = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}" '
         f'font-family="{FONT}" role="img" aria-labelledby="ht"><title id="ht">Recording of a JIVA hive, '
         f'{date}: {html.escape(frames[-1]["bar"])}</title>',
         f'<rect width="{W}" height="{H}" fill="{BG}"/><rect x=".5" y=".5" width="{W - 1}" height="{H - 1}" '
         f'fill="none" stroke="{LINE}"/>', t(16, 28, "tmux -L jiva · watchdog every 5s", MUTE, 12) + "</text>",
         t(W - 16, 28, f"recorded {date}", MUTE, 12, anchor="end") + "</text>"]
    if anim:
        k, m, half = notch_keys(), at * STEP, REBIRTH / 2  # dissolve before the respawn, re-form after
        keys = [0] + [(m - half + p * half) / total for p, _ in k["dissolve"]] + \
               [(m + p * half) / total for p, _ in k["reform"][1:]]
        vals = [k["dissolve"][0][1]] + [v for _, v in k["dissolve"] + k["reform"][1:]]
        if keys[-1] < 1:
            keys, vals = keys + [1], vals + [vals[-1]]
        o.append(f'<clipPath id="notch" clipPathUnits="objectBoundingBox"><polygon points="{vals[0]}">'
                 f'<animate attributeName="points" dur="{total}s" repeatCount="indefinite" '
                 f'keyTimes="{";".join(f"{x:.4f}" for x in keys)}" values="{";".join(vals)}"/></polygon></clipPath>')
        if not drop:
            toks[soul] = toks[soul] + [12]  # replayed: fresh body, handoff read, ~12k of boot context
    for i, n in enumerate(names):
        y = TOP + ROW * i
        st = [dict((r[0], r[1]) for r in f["rows"]).get(n, "-") for f in frames]
        clip = ' clip-path="url(#notch)"' if anim and n == soul else ""
        o.append(f'<g{clip}><rect x="12" y="{y}" width="{W - 24}" height="{ROW - 4}" fill="#0e092f" '
                 f'stroke="{LINE}"/>' + t(26, y + 20, n, TEXT, 13, 600) + "</text>")
        o.append(series(st, total, anim, lambda v, y=y: t(130, y + 20, v, MUTE if v == "idle" else CYAN)))
        o.append(series(toks[n], total, anim, lambda v, y=y: t(W - 26, y + 20, f"{v}k", CYAN, anchor="end")))
        o.append(series(toks[n], total, anim, lambda v, y=y: f'<rect x="200" y="{y + 12}" height="6" '
                        f'width="{min(v, 200) * 1.6:.0f}" fill="{PINK if v >= 170 else CYAN}">'
                        ).replace("</text>", "</rect>") + "</g>")
    y = TOP + ROW * len(names) + 22
    comb = [" ".join(f["inbox"][-1]) if f["inbox"] else "" for f in frames]
    if anim and not drop:
        comb.append(f"{soul} handoff · stop → watchdog respawns {soul}")
    o.append(series(comb, total, anim, lambda v: t(16, y, v[:74], MUTE, 12)))
    bars = [f["bar"] for f in frames]
    yb = H - 34
    o.append(f'<rect x="0" y="{yb}" width="{W}" height="34" fill="{PINK}"/>' + t(14, yb + 22, "[jiva]", BG, 13, 700)
             + "</text>" + f'<rect x="{W - 300}" y="{yb + 13}" width="8" height="8" fill="{GREEN}" stroke="{BG}"/>')
    o.append(series(bars, total, anim, lambda v: t(W - 286, yb + 22, v, BG, 13, 700)))
    cur = '<animate attributeName="opacity" values="1;0" dur="1.1s" calcMode="discrete" repeatCount="indefinite"/>'
    o.append(f'<rect x="{W - 22}" y="{yb + 10}" width="8" height="15" fill="{BG}">{cur if anim else ""}</rect></svg>')
    return "\n".join(o) + "\n"


if __name__ == "__main__":
    date, frames = parse()
    for name, anim in (("hero.svg", True), ("hero-static.svg", False)):
        (HERO / name).write_text(render(date, frames, anim), encoding="utf-8")
        print(f"hero: {name} {(HERO / name).stat().st_size / 1024:.1f} KB · {len(frames)} frames")
