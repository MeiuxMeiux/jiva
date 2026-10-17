#!/usr/bin/env python3
"""site check — run after build.py. Exits 1 on any red line.
- html-validate on build/index.html if installed, else stdlib well-formedness (balanced tags)
- no http(s):// in src html/css/js/svg except the SVG xmlns + own origin (canonical/og); no style=, no on*= handlers,
  no <script> with a body, no <style> blocks
- CSP meta in src/index.html == the CSP in deploy/apache-jiva.conf (canonical vhost)
- deploy/apache-jiva.conf asserts HSTS/nosniff/referrer/permissions/COOP (robots/sitemap: seo.py)
- every file under site/ (except fonts, build/) ≤150 lines; initial load < 400 KB (build minus
  assets.lazy(): other avatar packs, manifest, tile/emblem art); whole build < 3 MB
- then runs links.py (links + SRI), contrast.py, drift.py (page vs CLI), a11y.py, scrollbars.py, seo.py"""
import html.parser, importlib.util, json, pathlib, re, shutil, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CONF = ROOT / "deploy" / "apache-jiva.conf"
SRC, OUT = ROOT / "src", ROOT / "build"
BUDGET, TOTAL_CAP = 400 * 1024, 3 * 1024 * 1024
VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr"}
ALLOWED_URLS = {"http://www.w3.org/2000/svg",
                "https://github.com/MeiuxMeiux/jiva"}  # clone command text in install.html, never loaded
OWN = "https://jiva.meiuxmeiux.com/"  # self, not third-party: canonical, og:url, og:image
bad = []


class Balance(html.parser.HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.stack = []

    def handle_starttag(self, tag, attrs):
        if tag not in VOID:
            self.stack.append((tag, self.getpos()))

    def handle_startendtag(self, tag, attrs):
        pass

    def handle_endtag(self, tag):
        if tag in VOID:
            return
        if not self.stack or self.stack[-1][0] != tag:
            want = self.stack[-1] if self.stack else None
            bad.append(f"html: </{tag}> at line {self.getpos()[0]} closes {want}")
            return
        self.stack.pop()


def wellformed(path):
    p = Balance()
    p.feed(path.read_text(encoding="utf-8"))
    p.close()
    for tag, pos in p.stack:
        bad.append(f"html: <{tag}> at line {pos[0]} never closed")


def validate():
    page = OUT / "index.html"
    if not page.exists():
        bad.append("build/index.html missing (run site-build)")
        return
    hv = shutil.which("html-validate")
    if hv:
        r = subprocess.run([hv, str(page)], capture_output=True, text=True)
        if r.returncode:
            bad.append("html-validate:\n" + r.stdout + r.stderr)
    else:
        print("site-check: html-validate not installed, using stdlib well-formedness")
        wellformed(page)


def scan_src():
    for f in sorted(SRC.rglob("*")):
        if f.suffix not in {".html", ".css", ".js", ".svg"}:
            continue
        rel, text = f.relative_to(ROOT), f.read_text(encoding="utf-8")
        for url in re.findall(r"https?://[^\s\"')<>]+", text):
            if url not in ALLOWED_URLS and not url.startswith(OWN):
                bad.append(f"{rel}: third-party url {url}")
        if f.suffix in {".html", ".svg"}:
            if re.search(r"\sstyle\s*=", text, re.I):
                bad.append(f"{rel}: inline style= attribute")
            if re.search(r"\son[a-z]+\s*=", text, re.I):
                bad.append(f"{rel}: inline on*= handler")
            for m in re.finditer(r"<script\b([^>]*)>(.*?)</script>", text, re.S | re.I):
                if m.group(2).strip() or "src=" not in m.group(1):
                    bad.append(f"{rel}: inline <script> body")
            if re.search(r"<style\b", text, re.I):
                bad.append(f"{rel}: inline <style> block")
            if re.search(r"javascript:", text, re.I):
                bad.append(f"{rel}: javascript: url")


def csp_match():
    meta = re.search(r'http-equiv="Content-Security-Policy" content="([^"]+)"',
                     (SRC / "index.html").read_text(encoding="utf-8"))
    conf = re.search(r'^\s*Header always set Content-Security-Policy "([^"]+)"', CONF.read_text(encoding="utf-8"), re.M)
    if not meta or not conf or meta.group(1) != conf.group(1):
        bad.append("csp: meta tag and deploy/apache-jiva.conf differ (or one is missing)")
    elif "unsafe-inline" in meta.group(1):
        bad.append("csp: unsafe-inline is not allowed")


HEADERS = [("Strict-Transport-Security", r"max-age=300"), ("X-Content-Type-Options", r"nosniff"),
           ("Referrer-Policy", r"no-referrer"), ("Cross-Origin-Opener-Policy", r"same-origin"),
           ("Permissions-Policy", r"[a-z-]+=\(\)(, [a-z-]+=\(\))*")]


def headers():
    conf = CONF.read_text(encoding="utf-8")
    for name, want in HEADERS:
        m = re.search(rf'^\s*Header always set {name} "({want})"$', conf, re.M)
        print(f"site-check: header {name} {'ok' if m else 'FAIL'}")
        if not m:
            bad.append(f"apache-jiva.conf: missing or wrong {name} (want {want})")


def budgets():
    for f in ROOT.rglob("*"):
        if f.is_file() and "build" not in f.relative_to(ROOT).parts[:1] and "fonts" not in f.parts \
                and f.suffix in {".html", ".css", ".js", ".py", ".just", ".conf", ".md"}:
            n = len(f.read_text(encoding="utf-8").splitlines())
            if n > 150:
                bad.append(f"{f.relative_to(ROOT)}: {n} lines > 150")
    spec = importlib.util.spec_from_file_location("assets", ROOT / "scripts" / "assets.py")
    assets = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(assets)
    man = next((OUT / "avatars").glob("packs.*.json"), None)
    first = json.loads(man.read_text(encoding="utf-8"))["packs"][0]["id"] if man else ""
    files = [(f.relative_to(OUT).as_posix(), f.stat().st_size) for f in OUT.rglob("*") if f.is_file()]
    total = sum(n for _, n in files)
    initial = sum(n for rel, n in files if not assets.lazy(rel, first))
    print(f"site-check: initial load {initial / 1024:.1f} KB (budget {BUDGET // 1024} KB), "
          f"whole build {total / 1024:.1f} KB (cap {TOTAL_CAP // 1024} KB)")
    if initial >= BUDGET:
        bad.append(f"weight: initial load {initial} bytes >= {BUDGET}")
    if total >= TOTAL_CAP:
        bad.append(f"weight: whole build {total} bytes >= {TOTAL_CAP}")

if __name__ == "__main__":
    validate()
    scan_src()
    csp_match()
    headers()
    budgets()
    sys.stdout.flush()
    for sib in ("links.py", "contrast.py", "drift.py", "a11y.py", "scrollbars.py", "seo.py"):
        if subprocess.run([sys.executable, "-I", str(ROOT / "scripts" / sib)]).returncode:
            bad.append(f"{sib} failed (see FAIL lines above)")
    for line in bad:
        print("FAIL", line)
    print("site-check:", "red" if bad else "green")
    sys.exit(1 if bad else 0)
