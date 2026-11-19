#!/usr/bin/env python3
"""stats page check — run by check.py after the build. Exits 1 on any FAIL.
- build/stats/index.html well-formed; CSP meta identical to the index page's; no inline script/style (check.py
  scans src); one <h1>, no skipped heading levels, every link has text, every <svg role=img> named
- head: one <title> 10-70 chars, description 120-160, canonical + og:url == SITE/stats/; money: every <section> showing
  "$" or marked data-money carries the exact "API-equivalent, not what we pay" sentence (stats.js refuses otherwise)
- cross-reference strip (src/stats/crosslinks.txt): https only, expected public domains, no duplicate, and no
  name on the HOLD list (sha256[:16] of lowercase words, so unreleased names never appear in this public repo;
  release = add the line to crosslinks.txt and drop the hash here in the same commit)
- weight: own files (html, css, js, hashed data) <= 120 KB; js_tests: node stats_test.cjs (formats == python's)"""
import hashlib, html.parser, importlib.util, json, pathlib, re, shutil, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT, SRC = ROOT / "build", ROOT / "src"
SITE = "https://jiva.meiuxmeiux.com/stats/"
MONEY = "API-equivalent, not what we pay"
DOMAINS = {"jiva.meiuxmeiux.com", "meiuxmeiux.com", "vizeiux.meiuxmeiux.com"}
HOLD = set("""79866542834f9e05 eecada4a78587067 dbc20dcb565e93ac 2b219c9dc0a7a2a9 7d54967d1806e859 094eedfffab843b4 7d2f74700927c77a
7e34781376f38d1f 8b63510ba2c2ce7f 35b859822e8fd229 e33507067d769b37 22082517effcaaaa 6e2e6e988e756da9 7a2d9f78b5e3ff91
ab02fd5c91c87259 e3677635d58ff95e df5e69a6000eaee6 90e21a17edc8066b""".split())
BUDGET = 120 * 1024
bad = []


def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / f"{name}.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class Bands(html.parser.HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.bands, self.depth, self.head, self._title = [], 0, {"title": "", "meta": {}, "canon": []}, False

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == "section":
            self.depth += 1
            if self.depth == 1:
                self.bands.append({"id": a.get("id"), "money": "data-money" in a, "text": ""})
        elif tag == "title" and not self.bands:
            self._title = True
        elif tag == "meta" and (a.get("name") or a.get("property")):
            self.head["meta"].setdefault(a.get("name") or a.get("property"), []).append(a.get("content", ""))
        elif tag == "link" and a.get("rel") == "canonical":
            self.head["canon"].append(a.get("href"))

    def handle_endtag(self, tag):
        self.depth -= tag == "section"
        self._title = self._title and tag != "title"

    def handle_data(self, data):
        if self._title:
            self.head["title"] += data
        if self.depth and self.bands:
            self.bands[-1]["text"] += data


def page_checks(page):
    check = load("check")
    check.wellformed(page)
    bad.extend(check.bad)
    text = page.read_text(encoding="utf-8")
    csp = lambda t: re.search(r'http-equiv="Content-Security-Policy" content="([^"]+)"', t)
    mine, index = csp(text), csp((OUT / "index.html").read_text(encoding="utf-8"))
    if not mine or not index or mine.group(1) != index.group(1):
        bad.append("stats: CSP meta differs from the index page")
    a11y = load("a11y")
    p = a11y.Page()
    p.feed(text)
    if sum(1 for lvl, _ in p.heads if lvl == 1) != 1:
        bad.append("stats a11y: want exactly one <h1>")
    bad.extend(f"stats a11y: heading skips h{a} → h{b} at line {line}" for (a, _), (b, line) in zip(p.heads, p.heads[1:]) if b > a + 1)
    bad.extend(f"stats a11y: link at line {l['line']} has no text" for l in p.links if not (l["text"].strip() or l["label"].strip()))
    bad.extend("stats a11y: unnamed <svg role=img>" for s in p.svgs if not a11y.svg_named(s, p.ids))
    b = Bands()
    b.feed(text)
    h = b.head
    if not 10 <= len(h["title"].strip()) <= 70:
        bad.append(f"stats head: <title> is {len(h['title'].strip())} chars (want 10-70)")
    desc = h["meta"].get("description", [""])
    if len(desc) != 1 or not 120 <= len(desc[0]) <= 160:
        bad.append(f"stats head: want one description of 120-160 chars, got {[len(d) for d in desc]}")
    if h["canon"] != [SITE] or h["meta"].get("og:url") != [SITE]:
        bad.append(f"stats head: canonical/og:url must be {SITE}")
    for band in b.bands:
        if ("$" in band["text"] or band["money"]) and MONEY not in band["text"]:
            bad.append(f"stats money: band #{band['id']} shows dollars without the '{MONEY}' sentence")
    print(f"site-check: stats page bands={len(b.bands)} money-bands={sum(x['money'] for x in b.bands)} headings={len(p.heads)} links={len(p.links)}")


def crosslinks():
    seen, n = set(), 0
    for i, line in enumerate((SRC / "stats" / "crosslinks.txt").read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip() or line.startswith("#"):
            continue
        parts = [p.strip() for p in line.split("|")]
        if len(parts) != 3 or not all(parts):
            bad.append(f"crosslinks.txt:{i}: want name|https url|one line")
            continue
        (name, url, _), n = parts, n + 1
        m = re.fullmatch(r"https://([a-z0-9.-]+)(/[\w./-]*)?", url)
        if not m or m.group(1) not in DOMAINS:
            bad.append(f"crosslinks.txt:{i}: url must be https on {sorted(DOMAINS)}")
        words = [name.lower()] + re.findall(r"[a-z0-9]+", name.lower())
        if any(hashlib.sha256(w.encode()).hexdigest()[:16] in HOLD for w in words):
            bad.append(f"crosslinks.txt:{i}: '{name}' is on the hold list (not released); remove the line or release it")
        if url in seen:
            bad.append(f"crosslinks.txt:{i}: duplicate url")
        seen.add(url)
    print(f"site-check: stats crosslinks {n} entries, hold list {len(HOLD)} hashes")


def weight():
    own = [f for f in (OUT / "stats").rglob("*") if f.is_file() and f.name != "data.json"]
    size = sum(f.stat().st_size for f in own)
    shared = sum(f.stat().st_size for d in ("css", "js", "fonts") for f in (OUT / d).iterdir()
                 if f.is_file() and (f.suffix == ".woff2" or f.name.startswith("site.")))
    print(f"site-check: stats page own files {size / 1024:.1f} KB (budget {BUDGET // 1024} KB) + shared css/js/fonts {shared / 1024:.1f} KB")
    if size > BUDGET:
        bad.append(f"stats weight: own files {size} bytes > {BUDGET}")


def js_tests():  # stats_test.cjs: JStats.f must print exactly what stats_data.FMT prints, plus money + bad-data guards
    node = shutil.which("node")
    if not node:
        print("site-check: WARN node not on PATH, stats js unit checks skipped")
        return
    fmt = load("stats_data").FMT
    vals = [0, 7, 999, 1499.5, 31301, 159880, 2.5e6, 67216871, 245e6, 12542820779, 0.9809, 0.0034, 0.3442, 0.995, 0.125]
    pairs = {k: [[v, fmt[k](v)] for v in vals] for k in ("int", "compact", "k", "pct", "pct0", "per100")}
    r = subprocess.run([node, str(ROOT / "scripts" / "stats_test.cjs"), json.dumps(pairs)], capture_output=True, text=True)
    print(r.stdout.strip() or r.stderr.strip())
    if r.returncode:
        bad.append("stats_test.cjs failed")


if __name__ == "__main__":
    page = OUT / "stats" / "index.html"
    page_checks(page) if page.is_file() else bad.append("build/stats/index.html missing (run site-build)")
    crosslinks()
    weight()
    js_tests()
    for line in bad:
        print("FAIL", line)
    sys.exit(1 if bad else 0)
