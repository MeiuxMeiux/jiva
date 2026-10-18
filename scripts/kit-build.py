#!/usr/bin/env python3
"""kit-build — emit the JIVA Kit: ONE markdown file a stranger pastes into any repo to get a .fleet/.
Layout: kit/GUIDE.md (the desk-agent walkthrough, steps 0-6), then every file in kit/ORDER as
"### .fleet/<path>" + a fenced block (fence longer than any backtick run inside).
Usage: python3 -I scripts/kit-build.py [out]   (no out = stdout). Exit 0 ok, 1 an ORDER entry is missing."""
import pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
KIT = ROOT / "kit"

GUIDE = KIT / "GUIDE.md"  # the walkthrough the desk agent follows (steps 0-6); files come after it


def fence(text):
    """a backtick fence one longer than the longest run inside (min 3)"""
    runs = [len(m) for m in re.findall(r"`+", text)]
    return "`" * max(3, max(runs, default=0) + 1)


def lang(path):
    return {".md": "markdown", ".sh": "bash", ".json": "json", ".just": "just"}.get(path.suffix, "")


def order():
    lines = (KIT / "ORDER").read_text(encoding="utf-8").splitlines()
    return [ln.strip() for ln in lines if ln.strip() and not ln.lstrip().startswith("#")]


def main():
    entries = order()
    missing = [e for e in entries if not (KIT / e).is_file()]
    if missing:
        sys.exit("kit-build: missing from kit/: " + ", ".join(missing))
    parts = [GUIDE.read_text(encoding="utf-8"), "## Files\nEach block is one file; its heading is the path (Step 0 copies them).\n"]
    for e in entries:
        body = (KIT / e).read_text(encoding="utf-8")
        if not body.endswith("\n"):
            body += "\n"
        f = fence(body)
        parts.append(f"### .fleet/{e}\n{f}{lang(KIT / e)}\n{body}{f}\n")
    doc = "\n".join(parts)
    if len(sys.argv) > 1:
        out = pathlib.Path(sys.argv[1])
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(doc, encoding="utf-8")
        print(f"kit-build: {out} ({len(entries)} files, {len(doc) / 1024:.1f} KB)", file=sys.stderr)
    else:
        sys.stdout.write(doc)


if __name__ == "__main__":
    main()
