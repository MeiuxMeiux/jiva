#!/usr/bin/env python3
"""seo check over site/build (run by check.py). Exits 1 on any miss.
- head: one <title>, description 120-160 chars, canonical/og:url == SITE, robots index,follow,
  theme-color #060128, color-scheme, og:* (absolute og:image → build PNG 1200×630, width/height/alt),
  twitter summary_large_image; no JSON-LD (inline <script> is banned, see notes/site.md)
- icons: favicon.ico (ICO) + favicon.svg, apple-touch-icon 180×180 PNG; no manifest (CSP)
- robots.txt allow-all + Sitemap: == SITE/sitemap.xml; sitemap.xml = one <loc> SITE, lastmod not future
- humans.txt; .well-known/security.txt (RFC 9116: Contact, Expires future ≤ 1 year, Canonical)
- leak scan, every text file in build/: no email or user@host, /home|/root paths, the deploy.env host, IPv4 (127.0.0.1 ok)"""
import datetime, html.parser, pathlib, re, sys, xml.etree.ElementTree as ET

OUT = pathlib.Path(__file__).resolve().parent.parent / "build"
SITE = "https://jiva.meiuxmeiux.com/"
NAVY = "#060128"
CONTACT = "jiva@meiuxmeiux.com"  # the one published address (security.txt); exempt from the leak scan
bad = []


class Head(html.parser.HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.meta, self.links, self.titles, self.ldjson, self._t, self.body = {}, [], [], 0, False, False

    def handle_starttag(self, tag, attrs):
        a, self.body = dict(attrs), self.body or tag == "body"
        if self.body and tag != "script":  # head only: inline <svg><title>s in body don't count
            return
        if tag == "meta" and (a.get("name") or a.get("property")):
            self.meta.setdefault(a.get("name") or a.get("property"), []).append(a.get("content", ""))
        elif tag == "link":
            self.links.append(a)
        elif tag == "title":
            self._t = True
            self.titles.append("")
        elif tag == "script" and a.get("type") == "application/ld+json":
            self.ldjson += 1

    def handle_endtag(self, tag):
        self._t = self._t and tag != "title"

    def handle_data(self, data):
        if self._t and self.titles: self.titles[-1] += data


def need(ok, msg):
    bad.extend([] if ok else [msg])


def png_size(f):
    b = f.read_bytes()[:24] if f.is_file() else b""
    return (int.from_bytes(b[16:20], "big"), int.from_bytes(b[20:24], "big")) \
        if b[:8] == b"\x89PNG\r\n\x1a\n" else None


def one(p, key):
    v = p.meta.get(key, [])
    need(len(v) == 1 and v[0].strip(), f"head: want exactly one non-empty {key}, got {v}")
    return v[0] if v else ""


def head():
    p = Head()
    p.feed((OUT / "index.html").read_text(encoding="utf-8"))
    need(len(p.titles) == 1 and 10 <= len(p.titles[0].strip()) <= 70, f"head: one <title> 10-70 chars, got {p.titles}")
    d = one(p, "description")
    need(120 <= len(d) <= 160, f"head: description is {len(d)} chars (want 120-160)")
    need(one(p, "robots") == "index,follow", "head: robots != index,follow")
    need(one(p, "theme-color").lower() == NAVY, f"head: theme-color != {NAVY}")
    one(p, "color-scheme")
    canon = [l.get("href") for l in p.links if l.get("rel") == "canonical"]
    need(canon == [SITE], f"head: canonical {canon} != [{SITE}]")
    need(one(p, "og:type") == "website", "head: og:type != website")
    for k in ("og:site_name", "og:title", "og:description", "og:image:alt", "twitter:title",
              "twitter:description", "twitter:image:alt"):
        one(p, k)
    need(one(p, "og:url") == SITE, "head: og:url != SITE")
    need(one(p, "twitter:card") == "summary_large_image", "head: twitter:card != summary_large_image")
    for k in ("og:image", "twitter:image"):
        img = one(p, k)
        need(img.startswith(SITE) and img.endswith(".png"), f"head: {k} {img} not an absolute {SITE}*.png")
        size = png_size(OUT / img[len(SITE):]) if img.startswith(SITE) else None
        need(size == (1200, 630), f"head: {k} file is {size}, want PNG 1200×630")
    need((one(p, "og:image:width"), one(p, "og:image:height")) == ("1200", "630"), "head: og:image:width/height != 1200/630")
    need(p.ldjson == 0, "head: JSON-LD present (inline <script> is banned by check.py)")
    return p


def icons(p):
    rels = {(l.get("rel"), l.get("href")) for l in p.links}
    for want in (("icon", "favicon.ico"), ("icon", "favicon.svg"), ("apple-touch-icon", "apple-touch-icon.png")):
        need(want in rels, f"icons: missing <link rel={want[0]} href={want[1]}>")
    ico = OUT / "favicon.ico"
    need(ico.is_file() and ico.read_bytes()[:4] == b"\0\0\1\0", "icons: favicon.ico missing or not an ICO")
    need(png_size(OUT / "apple-touch-icon.png") == (180, 180), "icons: apple-touch-icon.png not PNG 180×180")
    need(("manifest", "site.webmanifest") not in rels, "icons: no manifest (CSP default-src 'none' blocks it)")


def crawl():
    robots = (OUT / "robots.txt").read_text(encoding="utf-8").split()
    need(robots == ["User-agent:", "*", "Allow:", "/", "Sitemap:", SITE + "sitemap.xml"],
         f"robots.txt: want allow-all + Sitemap: {SITE}sitemap.xml, got {robots}")
    ns = {"s": "http://www.sitemaps.org/schemas/sitemap/0.9"}
    root = ET.parse(OUT / "sitemap.xml").getroot()  # nosec B314: our own committed sitemap.xml, not untrusted input
    locs = [e.text for e in root.findall("s:url/s:loc", ns)]
    mods = [e.text for e in root.findall("s:url/s:lastmod", ns)]
    need(locs == [SITE], f"sitemap.xml: locs {locs} != [{SITE}]")
    need(len(mods) == 1 and datetime.date.fromisoformat(mods[0]) <= datetime.date.today(), f"sitemap: lastmod {mods}")
    need("/* TEAM */" in (OUT / "humans.txt").read_text(encoding="utf-8"), "humans.txt: missing /* TEAM */")
    pairs = [l.split(": ", 1) for l in (OUT / ".well-known" / "security.txt").read_text(encoding="utf-8").splitlines() if ": " in l]
    sec, contacts = dict(pairs), [v for k, v in pairs if k == "Contact"]
    need(contacts[:1] == ["mailto:" + CONTACT], f"security.txt: first Contact must be mailto:{CONTACT}")
    need(all(c.startswith(("https://", "mailto:")) for c in contacts), "security.txt: Contact must be https: or mailto:")
    need(sec.get("Canonical") == SITE + ".well-known/security.txt", "security.txt: Canonical mismatch")
    need(sec.get("Preferred-Languages") == "en", "security.txt: Preferred-Languages != en")
    exp = datetime.datetime.fromisoformat(sec.get("Expires", "1970-01-01T00:00:00Z").replace("Z", "+00:00"))
    left = (exp - datetime.datetime.now(datetime.timezone.utc)).days
    need(0 < left <= 366, f"security.txt: Expires in {left} days (want 1-366, RFC 9116)")


_env = pathlib.Path(__file__).resolve().parents[2] / "deploy.env"  # gitignored; its host is private and must never reach the build
_host = re.search(r"JIVA_DEPLOY_HOST=(?:[^@\s]*@)?([\w.-]+)", _env.read_text()) if _env.is_file() else None
LEAKS = [(r"(?<![\w.+-])(?!" + re.escape(CONTACT) + r"\b)[\w.+-]+@[\w-]+(\.[\w-]+)*", "email or user@host"), (r"/home/|/root/", "absolute home path"),
         (re.escape(_host.group(1)) if _host else r"(?!)", "deploy hostname"), (r"(?<![\w.])(?!127\.0\.0\.1\b)(\d{1,3}\.){3}\d{1,3}(?![\w.])", "non-loopback IPv4")]


def leaks():
    for f in sorted(OUT.rglob("*")):
        if f.is_file() and f.suffix in {".html", ".css", ".js", ".svg", ".txt", ".xml", ".webmanifest"}:
            text = f.read_text(encoding="utf-8")
            for rx, what in LEAKS:
                m = re.search(rx, text, re.I)
                need(not m, f"leak: {f.relative_to(OUT)} has {what}: {m.group(0) if m else ''}")


if __name__ == "__main__":
    icons(head())
    crawl()
    leaks()
    for line in bad:
        print("FAIL", line)
    print("site-check: seo head/og/twitter, icons, robots+sitemap, humans, security.txt, leaks",
          "FAIL" if bad else "ok")
    sys.exit(1 if bad else 0)
