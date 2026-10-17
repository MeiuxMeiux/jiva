#!/usr/bin/env python3
"""contrast check — WCAG 2 relative-luminance ratio of the palette pairs in src/css/tokens.css.
Text pairs need ≥ 4.5:1, accent ≥ 3:1. On a FAIL it proposes the nearest passing hex (fg mixed
toward white or black in 1% steps, whichever passes first). Prints every ratio; exits 1 on a FAIL."""
import pathlib, re, sys

TOKENS = pathlib.Path(__file__).resolve().parent.parent / "src" / "css" / "tokens.css"
PAIRS = [("text", "background", 4.5), ("primary", "background", 4.5),
         ("secondary", "background", 4.5), ("accent", "background", 3.0)]


def rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


def lum(c):
    ch = [v / 255 for v in c]
    ch = [v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in ch]
    return 0.2126 * ch[0] + 0.7152 * ch[1] + 0.0722 * ch[2]


def ratio(a, b):
    la, lb = sorted((lum(a), lum(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


def nearest(fg, bg, need):
    for step in range(1, 101):
        for end in ((255, 255, 255), (0, 0, 0)):
            c = tuple(round(f + (e - f) * step / 100) for f, e in zip(fg, end))
            if ratio(c, bg) >= need:
                return "#%02x%02x%02x" % c
    return None


def main():
    text = TOKENS.read_text(encoding="utf-8")
    tok = dict(re.findall(r"--([a-z]+):\s*(#[0-9a-fA-F]{6})\b", text))
    bad = []
    for fg, bg, need in PAIRS:
        if fg not in tok or bg not in tok:
            bad.append(f"contrast: --{fg} or --{bg} missing from tokens.css")
            continue
        r = ratio(rgb(tok[fg]), rgb(tok[bg]))
        ok = r >= need
        print(f"site-check: contrast {fg} {tok[fg]} on {bg} {tok[bg]} = {r:.2f}:1 "
              f"(need {need}) {'ok' if ok else 'FAIL'}")
        if not ok:
            bad.append(f"contrast: {fg}/{bg} {r:.2f} < {need}; nearest passing --{fg}: "
                       f"{nearest(rgb(tok[fg]), rgb(tok[bg]), need)}")
    for line in bad:
        print("FAIL", line)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
