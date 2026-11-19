#!/usr/bin/env python3
"""readme-drift — README.md + docs/QUICKSTART.md may only name commands that exist.
(a) every `jiva <sub>` / `just <recipe>` in code spans/fences must be in `jiva help` / `just --list`
(b) every subcommand `jiva help` prints must appear in README's verbs table (verbs:begin..end)
(c) README blurb (blurb:begin..end) == the site hero's <p class="lede"> paragraphs, whitespace-normalized
Usage: readme-drift.py [repo-dir]  (default: this checkout; pass a scratch copy to prove a FAIL)
       readme-drift.py --table     print the verbs table generated from `jiva help` + `just --list`
Exit 0 ok, 1 drift, 2 could not read the CLI or a file."""
import fnmatch, html, os, pathlib, re, subprocess, sys

HOME = pathlib.Path(os.environ.get("JIVA_HOME") or pathlib.Path(__file__).resolve().parent.parent)
WORD = r"(?<![\w/@.-]){}[ \t]+([a-z][a-z0-9*-]*)"
DOCS = ["README.md", "docs/QUICKSTART.md"]


def run(*cmd):
    return subprocess.run(cmd, capture_output=True, text=True, cwd=HOME).stdout


def cli_help():
    """[(sub, args, description)] from `jiva help`; a|b|c lines expand to one row each"""
    rows = []
    for line in run(str(HOME / "bin" / "jiva"), "help").splitlines():
        m = re.match(r"  ([a-z][a-z|-]*)((?:\s+[<\[]\S*)*)\s*(.*)$", line)
        if m:
            for sub in m.group(1).split("|"):
                rows.append((sub, " ".join(m.group(2).split()), m.group(3).strip()))
    return rows


def recipes():
    out = {}
    for line in run("just", "--list").splitlines()[1:]:
        if line.strip():
            name, _, desc = line.partition("#")
            out[name.split()[0]] = desc.strip()
    return out


def table(rows, recs):
    lines = ["| verb | what it does |", "|---|---|"]
    for sub, args, desc in rows:
        if desc.startswith("session verbs") or not desc:   # shared line: use the j-<verb> recipe text
            desc = recs.get(f"j-{sub}", desc).split(": ", 1)[-1]
        cmd = f"jiva {sub} {args}".strip().replace("|", "\\|")
        desc = desc.replace("|", "/").replace("<", "&lt;").replace(">", "&gt;")
        lines.append(f"| `{cmd}` | {desc} |")
    return "\n".join(lines)


def code_text(md):
    fences = [re.sub(r"(^|\s)#.*", "", f, flags=re.M)   # drop shell comments: prose, not commands
              for f in re.findall(r"^```[^\n]*\n(.*?)^```", md, re.S | re.M)]
    spans = re.findall(r"`([^`\n]+)`", re.sub(r"^```.*?^```", "", md, flags=re.S | re.M))
    return fences + spans


def between(md, tag):
    m = re.search(rf"<!-- {tag}:begin -->(.*?)<!-- {tag}:end -->", md, re.S)
    return m.group(1) if m else None


def norm(s):
    return " ".join(html.unescape(re.sub(r"<[^>]+>|[*_]", "", s)).split())


def site_blurb(root):
    hero = (root / "site/src/partials/hero.html").read_text(encoding="utf-8")
    return [norm(p) for p in re.findall(r'<p class="lede">(.*?)</p>', hero, re.S)]


def main(root):
    rows, recs = cli_help(), recipes()
    if not rows or not recs:
        print("FAIL readme-drift: could not read `jiva help` or `just --list`")
        return 2
    subs, bad = {r[0] for r in rows}, []
    try:
        docs = {d: (root / d).read_text(encoding="utf-8") for d in DOCS}
        blurb = site_blurb(root)
    except OSError as e:
        print(f"FAIL readme-drift: {e}")
        return 2
    for name, md in docs.items():                                          # (a)
        for chunk in code_text(md):
            bad += [f"{name} names `jiva {s}`, not in `jiva help`"
                    for s in re.findall(WORD.format("jiva"), chunk) if s not in subs]
            bad += [f"{name} names `just {r}`, not in `just --list`"
                    for r in re.findall(WORD.format("just"), chunk) if not fnmatch.filter(recs, r)]
    tbl = between(docs["README.md"], "verbs")                               # (b)
    if tbl is None:
        bad.append("README.md has no <!-- verbs:begin/end --> table")
    else:
        bad += [f"README verbs table lacks `jiva {s}`" for s in sorted(subs)
                if not re.search(rf"`jiva {re.escape(s)}\b", tbl)]
        if tbl.strip() != table(rows, recs):
            print("WARN readme-drift: verbs table differs from `scripts/readme-drift.py --table`")
    got = between(docs["README.md"], "blurb")                               # (c)
    paras = [norm(p) for p in re.split(r"\n\s*\n", got or "") if p.strip()]
    if not blurb or paras != blurb:
        bad.append("README blurb != site hero lede (site/src/partials/hero.html)")
    for b in sorted(set(bad)):
        print("FAIL readme-drift:", b)
    print(f"readme-drift: {len(subs)} verbs, {len(recs)} recipes, {len(blurb)} blurb paras, "
          f"{'FAIL' if bad else 'ok'}")
    return 1 if bad else 0


if __name__ == "__main__":
    if sys.argv[1:] == ["--table"]:
        print(table(cli_help(), recipes()))
        sys.exit(0)
    sys.exit(main(pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else HOME))
