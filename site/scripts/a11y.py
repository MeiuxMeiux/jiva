#!/usr/bin/env python3
"""accessibility check on build/index.html (stdlib only). Exits 1 on a FAIL.
- <html lang>; exactly one <h1>; heading levels never skip going down (h2 → h4 is a FAIL)
- every <img> has alt; every <svg role=img> (inline, and hero/*.svg) has aria-label or a
  resolvable aria-labelledby; every <a> has text or aria-label
- :focus-visible exists in src/css; motion.css honors prefers-reduced-motion; an animated hero.svg
  sits in a <picture> with a reduced-motion <source> whose file exists
- tokens.css palette == the fixed 5-colour palette below (the design law; change both together)"""
import html.parser, pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT, CSS = ROOT / "build", ROOT / "src" / "css"
PALETTE = "--text:#f0e2e2; --background:#060128; --primary:#ef4fbc; --secondary:#00ffd8; --accent:#21ff00;"
TOKEN = r"--(text|background|primary|secondary|accent):\s*(#[0-9a-fA-F]{6})\b"


class Page(html.parser.HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.lang, self.heads, self.ids, self.svgs, self.imgs = None, [], set(), [], []
        self.links, self.open_a, self.sources = [], None, []

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if "id" in a:
            self.ids.add(a["id"])
        if tag == "html":
            self.lang = a.get("lang")
        elif re.fullmatch(r"h[1-6]", tag):
            self.heads.append((int(tag[1]), self.getpos()[0]))
        elif tag == "img":
            self.imgs.append(a)
        elif tag == "svg" and a.get("role") == "img":
            self.svgs.append(a)
        elif tag == "source":
            self.sources.append(a)
        elif tag == "a":
            self.open_a = {"label": a.get("aria-label") or "", "text": "", "line": self.getpos()[0]}

    def handle_data(self, data):
        if self.open_a is not None:
            self.open_a["text"] += data

    def handle_endtag(self, tag):
        if tag == "a" and self.open_a is not None:
            self.links.append(self.open_a)
            self.open_a = None


def svg_named(a, ids):
    return (a.get("aria-label") or "").strip() or (
        a.get("aria-labelledby") and all(i in ids for i in a["aria-labelledby"].split()))


def main():
    bad = []
    page = Page()
    page.feed((OUT / "index.html").read_text(encoding="utf-8"))
    if not page.lang:
        bad.append("a11y: <html> has no lang")
    h1 = sum(1 for lvl, _ in page.heads if lvl == 1)
    if h1 != 1:
        bad.append(f"a11y: {h1} <h1> elements, want exactly 1")
    for (prev, _), (lvl, line) in zip(page.heads, page.heads[1:]):
        if lvl > prev + 1:
            bad.append(f"a11y: heading skips h{prev} → h{lvl} at line {line}")
    bad += [f"a11y: <img src={i.get('src')}> has no alt" for i in page.imgs if "alt" not in i]
    bad += [f"a11y: inline <svg role=img> unnamed ({s.get('viewbox')})" for s in page.svgs
            if not svg_named(s, page.ids)]
    bad += [f"a11y: link at line {l['line']} has no text" for l in page.links
            if not (l["text"].strip() or l["label"].strip())]
    for f in sorted((ROOT / "src" / "hero").glob("*.svg")):
        p = Page()
        p.feed(f.read_text(encoding="utf-8"))
        if not p.svgs or not all(svg_named(s, p.ids) for s in p.svgs):
            bad.append(f"a11y: {f.name} lacks role=img + a name")
    css = "".join(f.read_text(encoding="utf-8") for f in sorted(CSS.glob("*.css")))
    if ":focus-visible" not in css:
        bad.append("a11y: no :focus-visible style in src/css")
    if "prefers-reduced-motion: reduce" not in (CSS / "motion.css").read_text(encoding="utf-8"):
        bad.append("a11y: motion.css ignores prefers-reduced-motion")
    hero = ROOT / "src" / "hero" / "hero.svg"
    if "<animate" in hero.read_text(encoding="utf-8"):
        rm = [s for s in page.sources if "prefers-reduced-motion: reduce" in s.get("media", "")]
        if not rm or not all((ROOT / "src" / s.get("srcset", "")).exists() for s in rm):
            bad.append("a11y: animated hero.svg has no reduced-motion <source> with a real file")
    want = dict(re.findall(TOKEN, PALETTE))
    have = dict(re.findall(TOKEN, (CSS / "tokens.css").read_text(encoding="utf-8")))
    if not want or want != have:
        bad.append(f"a11y: tokens.css palette {have} != palette {want}")
    print(f"site-check: a11y lang={page.lang} h1={h1} headings={len(page.heads)} imgs={len(page.imgs)} "
          f"svg={len(page.svgs)} links={len(page.links)} focus/motion/palette "
          f"{'ok' if not any(k in b for b in bad for k in ('focus', 'motion', 'palette')) else 'FAIL'}")
    for b in bad:
        print("FAIL", b)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
