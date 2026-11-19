"""stats page build — called by build.py after the index is fingerprinted. src/stats/index.html → build/stats/index.html:
expands includes (build.py's expand), fills every data-stat span and <!-- @table x --> from src/stats/data.json (so the
page reads correctly with JS off), renders <!-- @crosslinks --> from src/stats/crosslinks.txt, minifies, then hashes
stats css/js/data and points the page at the index's hashed shared css/js/fonts with SRI (sha384) on every <link>/<script>.
data.json is also published unhashed at /stats/data.json as the citable raw file."""
import hashlib, html, json, pathlib, re, shutil, sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import stats_data  # noqa: E402  (sibling module; -I drops the script dir from sys.path)

STAT = re.compile(r'(<(\w+)\b[^>]*?\bdata-stat="([\w.]+)"(?:\s+data-f="(\w+)")?[^>]*>)(.*?)(</\2>)', re.S)
TABLE = re.compile(r"<!--\s*@table\s+(\w+)\s*-->")


def value(d, extra, path):
    cur = {"derived": extra, **d}
    for k in path.split("."):
        if not isinstance(cur, dict) or k not in cur:
            sys.exit(f"stats-build: data-stat {path} not in data.json")
        cur = cur[k]
    return cur


def crosslinks(src):
    cards = []
    for line in (src / "stats" / "crosslinks.txt").read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        name, url, blurb = (p.strip() for p in line.split("|", 2))
        e = html.escape
        cards.append(f'<li><a href="{e(url)}"><b>{e(name)}</b><span>{e(blurb)}</span><i aria-hidden="true">↗</i></a></li>')
    return '<ul class="xlinks side">' + "".join(cards) + "</ul>"


def fill(page, d, src):
    extra = stats_data.derived(d)

    def one(m):
        v, fmt = value(d, extra, m.group(3)), m.group(4) or "num"
        return m.group(1) + html.escape(stats_data.FMT[fmt](v)) + m.group(6)

    page = STAT.sub(one, page)
    tabs = dict(stats_data.tables(d))
    page = TABLE.sub(lambda m: tabs[m.group(1)], page)
    page = page.replace("<!-- @crosslinks -->", crosslinks(src))
    if TABLE.search(page) or "@crosslinks" in page:
        sys.exit("stats-build: unresolved @table/@crosslinks")
    return page


def build(SRC, OUT, expand, min_html, min_css, min_js, hashed, sri):
    src, out = SRC / "stats", OUT / "stats"
    data = json.loads((src / "data.json").read_text(encoding="utf-8"))
    (out / "js").mkdir(parents=True)
    page = fill(expand(src / "index.html"), data, SRC)
    if "@include" in page:
        sys.exit("stats-build: unresolved include")
    page = min_html(page)
    attr = lambda f: f'integrity="{sri(f)}" crossorigin="anonymous"'
    css = out / "stats.css"
    css.write_text(min_css("".join(f.read_text(encoding="utf-8") for f in sorted((src / "css").glob("*.css")))), encoding="utf-8")
    css = hashed(css)
    page = page.replace('<link rel="stylesheet" href="stats/stats.css">', f'<link rel="stylesheet" href="{css.name}" {attr(css)}>')
    shared = {"css/site.css": next((OUT / "css").glob("site.*.css")), "js/site.js": next((OUT / "js").glob("site.*.js"))}
    for rel, f in shared.items():
        page = page.replace(f'href="{rel}">', f'href="../{rel.split("/")[0]}/{f.name}" {attr(f)}>')
        page = page.replace(f'src="{rel}" defer>', f'src="../{rel.split("/")[0]}/{f.name}" {attr(f)} defer>')
    for f in sorted((OUT / "fonts").glob("*.woff2")):
        stem = f.name.split(".")[0]
        page = page.replace(f'href="fonts/{stem}.woff2"', f'href="../fonts/{f.name}"')
    tags = []
    for js in sorted((src / "js").glob("*.js"), key=lambda p: (p.name != "stats.js", p.name)):  # core first
        f = out / "js" / js.name
        f.write_text(min_js(js.read_text(encoding="utf-8")), encoding="utf-8")
        f = hashed(f)
        tags.append(f'<script src="js/{f.name}" {attr(f)} defer></script>')
    page = page.replace("<!-- @scripts -->", "".join(tags))
    shutil.copy(src / "data.json", out / "data.json")
    raw = out / "data.raw.json"  # minified for the page; the pretty copy stays at /stats/data.json
    raw.write_text(json.dumps(data, separators=(",", ":"), ensure_ascii=False), encoding="utf-8")
    raw = raw.rename(out / f"data.{hashlib.sha256(raw.read_bytes()).hexdigest()[:8]}.json")
    page = page.replace('data-src="data.json"', f'data-src="{raw.name}"')
    for left in ("stats/stats.css", 'href="css/', 'src="js/site', 'href="fonts/', "@scripts"):
        if left in page:
            sys.exit(f"stats-build: unrewritten reference {left}")
    (out / "index.html").write_text(page, encoding="utf-8")
    kb = sum(p.stat().st_size for p in out.rglob("*") if p.is_file() and p.name != "data.json") / 1024
    print(f"site-build: stats page {out}/index.html ({kb:.1f} KB own files incl. hashed data)")
