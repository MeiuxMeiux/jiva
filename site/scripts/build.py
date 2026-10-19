#!/usr/bin/env python3
"""site build — site/src → site/build. Expands <!-- @include partials/x.html --> in index.html,
inlines css/site.css @imports into one file, minifies HTML/CSS/JS conservatively (<pre> kept
verbatim), copies fonts + OFL texts + STATIC (robots, sitemap, humans,
icons, og.png, .well-known/ dotdir) + svgs (favicon, og, hero/); assets.py copies + hashes every avatar
pack's thumbs (manifest for the §05 rotator) and src/img art (generated --art-* css), then content-hashes
css/js/woff2 names
(name.<sha256[:8]>.ext), rewrites references and adds SRI (sha384) + crossorigin on the stylesheet
<link> and <script>. Stdlib only. Usage: build.py [src] [out]"""
import base64, hashlib, importlib.util, pathlib, re, shutil, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "src"
OUT = pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 else ROOT / "build"
INCLUDE = re.compile(r"<!--\s*@include\s+([\w./-]+)\s*-->")
STATIC = ["robots.txt", "sitemap.xml", "humans.txt", "favicon.ico", "og.png",
          "apple-touch-icon.png", ".well-known/security.txt"]  # raster.sh → png/ico
_spec = importlib.util.spec_from_file_location("assets", pathlib.Path(__file__).with_name("assets.py"))
assets = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(assets)
IMPORT = re.compile(r'@import\s+url\("([\w.-]+)"\);')


def expand(path, depth=0):
    if depth > 4:
        sys.exit(f"site-build: include depth > 4 at {path}")
    text = path.read_text(encoding="utf-8")
    return INCLUDE.sub(lambda m: expand(SRC / m.group(1), depth + 1), text)


def min_html(html):
    parts = re.split(r"(<pre\b.*?</pre>)", html, flags=re.S)
    out = []
    for i, p in enumerate(parts):
        if i % 2:
            out.append(p)
            continue
        p = re.sub(r"<!--(?!\s*@).*?-->", "", p, flags=re.S)
        p = re.sub(r"\s+", " ", p)
        p = re.sub(r">\s+<", "><", p)
        out.append(p)
    return "".join(out).strip() + "\n"


def min_css(css):
    css = re.sub(r"/\*.*?\*/", "", css, flags=re.S)
    css = re.sub(r"\s+", " ", css)
    css = re.sub(r"\s*([{}:;,>])\s*", r"\1", css)
    css = css.replace(";}", "}")  # only punctuation is touched; spaces inside values survive
    return css.strip() + "\n"


def min_js(js):
    lines = []
    for line in js.splitlines():
        s = line.strip()
        if s and not s.startswith("//"):
            lines.append(s)
    return "\n".join(lines) + "\n"


def css_bundle():
    entry = (SRC / "css" / "site.css").read_text(encoding="utf-8")
    return IMPORT.sub(lambda m: (SRC / "css" / m.group(1)).read_text(encoding="utf-8"), entry)


def hashed(f):
    new = f.with_name(f"{f.stem}.{hashlib.sha256(f.read_bytes()).hexdigest()[:8]}{f.suffix}")
    f.rename(new)
    return new


def sri(f):
    return "sha384-" + base64.b64encode(hashlib.sha384(f.read_bytes()).digest()).decode()


def fingerprint():
    """fonts first (css + html point at them), then css/js; html is rewritten last."""
    page_path, css_path = OUT / "index.html", OUT / "css" / "site.css"
    page, css = page_path.read_text(encoding="utf-8"), css_path.read_text(encoding="utf-8")
    for f in sorted((OUT / "fonts").glob("*.woff2")):
        new = hashed(f)
        css = css.replace(f"../fonts/{f.name}", f"../fonts/{new.name}")
        page = page.replace(f'"fonts/{f.name}"', f'"fonts/{new.name}"')
    css_path.write_text(css, encoding="utf-8")
    for f in [css_path] + sorted((OUT / "js").glob("*.js")):
        new, rel = hashed(f), f"{f.parent.name}/{f.name}"
        nrel = f"{f.parent.name}/{new.name}"
        attr = f'integrity="{sri(new)}" crossorigin="anonymous"'
        page, n = re.subn(rf'<(link rel="stylesheet"|script) (href|src)="{re.escape(rel)}"',
                          rf'<\1 \2="{nrel}" {attr}', page)
        if n != 1:
            sys.exit(f"site-build: expected one reference to {rel} in index.html, found {n}")
    page_path.write_text(page, encoding="utf-8")


def main():
    if OUT.exists():
        shutil.rmtree(OUT)
    (OUT / "css").mkdir(parents=True)
    (OUT / "js").mkdir()
    html = expand(SRC / "index.html")
    if INCLUDE.search(html):
        sys.exit("site-build: unresolved include")
    found, manifest = assets.packs(OUT)  # first pack = first paint; the rest load on demand
    for s in found[0]["slots"]:
        html = html.replace(f'"avatars/{s["slot"]:02d}-s.webp"', f'"{s["src"]}"')
    html = html.replace('data-packs="avatars/packs.json"', f'data-packs="{manifest}"')
    (OUT / "index.html").write_text(min_html(html), encoding="utf-8")
    (OUT / "css" / "site.css").write_text(min_css(css_bundle() + assets.art(SRC, OUT)), encoding="utf-8")
    for js in (SRC / "js").glob("*.js"):
        (OUT / "js" / js.name).write_text(min_js(js.read_text(encoding="utf-8")), encoding="utf-8")
    shutil.copytree(SRC / "fonts", OUT / "fonts", ignore=shutil.ignore_patterns(".gitkeep"))
    shutil.copy(ROOT.parent / "docs/MICRO.md", OUT / "micro.md")  # JIVA Micro: paste-in hive guide, raw at /micro.md
    subprocess.run([sys.executable, "-I", str(ROOT.parent / "scripts/kit-build.py"), str(OUT / "kit.md")], check=True)  # JIVA Kit
    for name in STATIC:  # unhashed on purpose: crawlers and scrapers ask for these exact paths
        (OUT / name).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(SRC / name, OUT / name)
    for svg in SRC.glob("*.svg"):
        shutil.copy(svg, OUT / svg.name)
    (OUT / "hero").mkdir()
    for svg in (SRC / "hero").glob("*.svg"):  # rendered by scripts/hero.py from frames.txt
        shutil.copy(svg, OUT / "hero" / svg.name)
    fingerprint()
    total = sum(f.stat().st_size for f in OUT.rglob("*") if f.is_file())
    print(f"site-build: {OUT} ({total / 1024:.1f} KB)")


if __name__ == "__main__":
    main()
