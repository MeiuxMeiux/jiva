#!/usr/bin/env python3
"""docs-drift check — the page may only name commands that exist.
- every `jiva <sub>` inside <code>/<pre> in src html (and hero frames.txt) must be a subcommand that
  `$JIVA_HOME/bin/jiva help` prints (FAIL); CLI subcommands the page never names are a WARN
- every `just <recipe>` (globs like j-* allowed) must be in `just --list` (FAIL); unnamed recipes WARN
- the six session verbs claim/report/ask/ship/handoff/inbox must each appear in the verbs list
Usage: drift.py [src-dir]   (default site/src; pass a scratch copy to prove a FAIL)"""
import fnmatch, html, os, pathlib, re, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
HOME = pathlib.Path(os.environ.get("JIVA_HOME") or ROOT.parent)
SRC = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "src"
SIX = ["claim", "report", "ask", "ship", "handoff", "inbox"]
WORD = r"(?<![\w/@.-]){}\s+([a-z][a-z0-9*-]*)"


def code_text(text):
    """text of every <code> and <pre> element, tags stripped, entities decoded"""
    out = re.findall(r"<(?:code|pre)\b[^>]*>(.*?)</(?:code|pre)>", text, re.S)
    return [html.unescape(re.sub(r"<[^>]+>", "", s)) for s in out]


def mentions():
    jv, js, verbs = {}, {}, ""
    for f in sorted(SRC.rglob("*.html")):
        text = f.read_text(encoding="utf-8")
        m = re.search(r'<ol class="verbs">(.*?)</ol>', text, re.S)
        verbs += m.group(1) if m else ""
        for chunk in code_text(text):
            for sub in re.findall(WORD.format("jiva"), chunk):
                jv.setdefault(sub, f.name)
            for rec in re.findall(WORD.format("just"), chunk):
                js.setdefault(rec, f.name)
    frames = SRC / "hero" / "frames.txt"
    if frames.exists():
        for line in frames.read_text(encoding="utf-8").splitlines():
            if not line.startswith("#"):
                for sub in re.findall(WORD.format("jiva"), line):
                    jv.setdefault(sub, frames.name)
    for sub in re.findall(r"<li><code>([a-z]+)", verbs):   # the verbs list names bare subcommands
        jv.setdefault(sub, "verbs.html")
    return jv, js, verbs


def cli_subs():
    out = subprocess.run([str(HOME / "bin" / "jiva"), "help"], capture_output=True, text=True,
                         cwd=HOME).stdout
    subs = set()
    for line in out.splitlines():
        m = re.match(r"  ([a-z][a-z|-]*)\b", line)
        if m:
            subs.update(m.group(1).split("|"))
    return subs


def recipes():
    out = subprocess.run(["just", "--list"], capture_output=True, text=True, cwd=HOME).stdout
    return {line.split()[0] for line in out.splitlines()[1:] if line.strip()}


def main():
    bad, warn = [], []
    jv, js, verbs = mentions()
    subs, recs = cli_subs(), recipes()
    if not subs or not recs:
        print("FAIL drift: could not read `jiva help` or `just --list`")
        return 1
    for sub, where in sorted(jv.items()):
        if sub not in subs:
            bad.append(f"drift: {where} names `jiva {sub}`, which `jiva help` doesn't list")
    for rec, where in sorted(js.items()):
        if not fnmatch.filter(recs, rec):
            bad.append(f"drift: {where} names `just {rec}`, which `just --list` doesn't list")
    named = set(jv)
    warn += [f"jiva {s}" for s in sorted(subs - named - {"help"})]
    used = {r for pat in js for r in fnmatch.filter(recs, pat)}
    warn += [f"just {r}" for r in sorted(recs - used - {"default"})]
    for v in SIX:
        if not re.search(rf"<code>{v}\b", verbs):
            bad.append(f"drift: verb `{v}` missing from the verbs list")
    print(f"site-check: drift jiva {len(jv)} named / {len(subs)} in help, just {len(js)} named / "
          f"{len(recs)} recipes, six verbs {'ok' if not any('verb `' in b for b in bad) else 'FAIL'}")
    if warn:
        print("WARN drift: never named on the page:", ", ".join(warn))
    for b in bad:
        print("FAIL", b)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
