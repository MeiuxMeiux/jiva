#!/usr/bin/env python3
"""link check over site/build: every href/src (html) and url() (css) must be a #anchor that exists
in the page, data:, or a file inside build/ (own-origin absolute urls count as local). lychee --offline if on PATH, else this stdlib pass.
Also verifies each integrity="sha384-…" against the file it names. Exits 1 on any miss."""
import base64, hashlib, html.parser, pathlib, re, shutil, subprocess, sys

OUT = pathlib.Path(__file__).resolve().parent.parent / "build"
OWN = "https://jiva.meiuxmeiux.com/"
bad = []


class Refs(html.parser.HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.refs, self.ids, self.sri = [], set(), []

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if a.get("id"):
            self.ids.add(a["id"])
        for k in ("href", "src"):
            if a.get(k) is not None:
                self.refs.append(a[k])
                if a.get("integrity"):
                    self.sri.append((a[k], a["integrity"]))


def local(base, ref, origin):
    target = (base / ref.split("#")[0].split("?")[0]).resolve()
    if OUT.resolve() not in target.parents or not target.is_file():
        bad.append(f"links: {origin} → {ref} does not resolve inside build/")


def main():
    lychee = shutil.which("lychee")
    if lychee:
        r = subprocess.run([lychee, "--offline", "--no-progress", "--include-fragments", str(OUT)],
                           capture_output=True, text=True)
        print("site-check: lychee --offline", "ok" if r.returncode == 0 else "FAILED")
        if r.returncode:
            bad.append("lychee:\n" + r.stdout + r.stderr)
    n = 0
    for page in sorted(OUT.rglob("*.html")):
        p = Refs()
        p.feed(page.read_text(encoding="utf-8"))
        for ref in p.refs:
            n += 1
            if ref.startswith("#"):
                if ref[1:] and ref[1:] not in p.ids:
                    bad.append(f"links: {page.name} → {ref} has no matching id")
            elif ref.startswith("data:"):
                continue
            elif ref.startswith(OWN):  # canonical: absolute self url → build/ path ("" = index.html)
                local(OUT, ref[len(OWN):] or "index.html", page.name)
            elif re.match(r"[a-z][a-z0-9+.-]*:", ref, re.I):
                bad.append(f"links: {page.name} → {ref} is not local")
            else:
                local(page.parent, ref, page.name)
        for ref, want in p.sri:
            f = page.parent / ref
            got = "sha384-" + base64.b64encode(hashlib.sha384(f.read_bytes()).digest()).decode() \
                if f.is_file() else "missing"
            print(f"site-check: sri {ref} {'ok' if got == want else 'MISMATCH'}")
            if got != want:
                bad.append(f"sri: {ref} integrity does not match file")
    for css in sorted(OUT.rglob("*.css")):
        for ref in re.findall(r'url\("?([^")]+)"?\)', css.read_text(encoding="utf-8")):
            n += 1
            if not ref.startswith("data:"):
                local(css.parent, ref, css.name)
    print(f"site-check: links checked {n} (stdlib)")
    for line in bad:
        print("FAIL", line)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
