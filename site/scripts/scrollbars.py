#!/usr/bin/env python3
"""scrollbar check — standing rule: no grey scrollbars, ever. Reads build/css/site*.css (the bundle).
- the bundle sets scrollbar-color, and every color in it resolves (var() via :root) to a palette hex
- every scrollbar rule (scrollbar-color / ::-webkit-scrollbar*) is free of greys: named gray/grey/
  silver/darkgray…, #rgb/#rrggbb with r==g==b (except #000/#fff), rgb()/rgba() with r==g==b
- ::-webkit-scrollbar-thumb is styled. Optional argv[1] = a css file to check instead (plant tests)."""
import pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PALETTE = ("text", "background", "primary", "secondary", "accent")
GREY_NAMES = re.compile(r"\b(?:\w*gr[ae]y|silver|gainsboro|whitesmoke)\b", re.I)


def is_grey_hex(h):
    h = h.lower().lstrip("#")
    if len(h) in (3, 4):
        h = "".join(c * 2 for c in h[:3])
    r, g, b = h[0:2], h[2:4], h[4:6]
    return r == g == b and r not in ("00", "ff")


def greys(decl):
    out = GREY_NAMES.findall(decl)
    out += [h for h in re.findall(r"#[0-9a-fA-F]{3,8}\b", decl) if is_grey_hex(h)]
    for m in re.finditer(r"rgba?\(\s*(\d+)[\s,]+(\d+)[\s,]+(\d+)", decl):
        if m.group(1) == m.group(2) == m.group(3) and m.group(1) not in ("0", "255"):
            out.append(m.group(0))
    return out


def main():
    if len(sys.argv) > 1:
        css = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
    else:
        files = sorted((ROOT / "build" / "css").glob("site*.css"))
        if not files:
            print("scrollbars: FAIL no built css bundle (run site-build)")
            return 1
        css = files[0].read_text(encoding="utf-8")
    tok = dict(re.findall(r"--([a-z]+):\s*(#[0-9a-fA-F]{6})\b", css))
    pal = {tok[k].lower() for k in PALETTE if k in tok}
    bad = []
    rules = re.findall(r"([^{}]*)\{([^{}]*)\}", css)
    sb = [(s.strip(), b) for s, b in rules if "scrollbar" in s or "scrollbar" in b]
    colors = [m for _, b in sb for m in re.findall(r"scrollbar-color\s*:\s*([^;}]+)", b)]
    if not colors:
        bad.append("no scrollbar-color in the bundle")
    for val in colors:
        for part in re.findall(r"var\(--[a-z]+\)|#[0-9a-fA-F]{3,8}\b|[a-z]+", val):
            hexv = tok.get(part[6:-1], "?") if part.startswith("var(") else part
            if part in ("auto", "var"):
                continue
            if hexv.lower() not in pal:
                bad.append(f"scrollbar-color {val.strip()!r}: {part} is not a palette hex")
    for sel, body in sb:
        for g in greys(sel + "{" + body):
            bad.append(f"grey in scrollbar rule {sel[:60]!r}: {g}")
    if not any("::-webkit-scrollbar-thumb" in s for s, _ in sb):
        bad.append("::-webkit-scrollbar-thumb not styled")
    print(f"scrollbars: {len(sb)} rules, {len(colors)} scrollbar-color, palette {sorted(pal)}")
    for line in bad:
        print("scrollbars: FAIL", line)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
