#!/usr/bin/env python3
"""kit-build — emit the JIVA Kit: ONE markdown file a stranger pastes into any repo to get a .fleet/.
Layout: intro, install steps, run order (docs/MICRO.md phases condensed), then every file in kit/ORDER
as "### .fleet/<path>" + a fenced block (fence longer than any backtick run inside).
Usage: python3 -I scripts/kit-build.py [out]   (no out = stdout)
Exit 0 ok, 1 an ORDER entry is missing or MICRO.md phases drifted from RUN below."""
import pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
KIT = ROOT / "kit"

INTRO = """# JIVA Kit: a Claude Code fleet as plain files

The files below install a small fleet into any git repo as `.fleet/`: role sheets, templates, `just`
recipes and bash scripts on a PRIVATE tmux server (`tmux -L fleet`). No JIVA checkout needed.
Paste this file into a repo as `KIT.md`, open Claude Code there, and say:
**"Read KIT.md. Install the kit, then walk the run order, stopping after each phase."**
The why behind each step: JIVA Micro (micro.md). Full runner: https://github.com/MeiuxMeiux/jiva

Needs: Linux or WSL2, bash ≥4, git, tmux ≥3.2, jq, just, flock (util-linux), Claude Code.
"""

INSTALL = """## Install
1. Copy each block below to the path in its heading (`.fleet/<path>`; `fleet.just` → `.fleet/fleet.just`).
2. Add `import? '.fleet/fleet.just'` to the repo's `justfile` (create the justfile if there is none).
3. `chmod +x .fleet/bin/*.sh`
4. `echo '.fleet/state/' >> .gitignore` (runtime state: claims, seat json, alerts, gate results).
5. Merge `.fleet/templates/CLAUDE.md` into the root `CLAUDE.md` (keep it ≤40 lines) and the keys of
   `.fleet/settings.json` (statusLine, permissions.allow) into `.claude/settings.json`.
6. `just --list` shows the fleet recipes. Recipes are the API: seats call them, not raw tmux or git.
"""

RUN = [  # one line per docs/MICRO.md "## Phase N" heading, in order
    "tools, `nproc`/`free -m` (≈1 GB + 1 core per seat), quota; under 3 seats → solo.",
    "CLAUDE.md as a ≤40-line router, detail in notes/, `/context` before and after.",
    "`.fleet/templates/rules.md` → `.fleet/rules.md`, linked from CLAUDE.md.",
    "cards from `.fleet/templates/card.md`, handoffs from `.fleet/templates/handoff.md`.",
    "`just up` (private tmux + watcher), `just add w1 .fleet/cards/w1.md`, `just ls`, `just peek w1`.",
    "`just digest` on a 10-min tick, `just ls` (tokens, quota) before adding seats, restart at 150k, `just down` to stop.",
]


def fence(text):
    """a backtick fence one longer than the longest run inside (min 3)"""
    runs = [len(m) for m in re.findall(r"`+", text)]
    return "`" * max(3, max(runs, default=0) + 1)


def lang(path):
    return {".md": "markdown", ".sh": "bash", ".json": "json", ".just": "just"}.get(path.suffix, "")


def order():
    lines = (KIT / "ORDER").read_text(encoding="utf-8").splitlines()
    return [ln.strip() for ln in lines if ln.strip() and not ln.lstrip().startswith("#")]


def run_order():
    phases = re.findall(r"^## (Phase \d+: .+)$", (ROOT / "docs/MICRO.md").read_text(encoding="utf-8"), re.M)
    if len(phases) != len(RUN):
        sys.exit(f"kit-build: docs/MICRO.md has {len(phases)} phases, RUN has {len(RUN)}: update RUN")
    titles = [p.split(": ", 1)[1].split(" (")[0].capitalize() for p in phases]
    rows = [f"{i}. **{t}**: {line}" for i, (t, line) in enumerate(zip(titles, RUN))]
    return "## Run order (JIVA Micro phases 0-5)\n" + "\n".join(rows) + "\n"


def main():
    entries = order()
    missing = [e for e in entries if not (KIT / e).is_file()]
    if missing:
        sys.exit("kit-build: missing from kit/: " + ", ".join(missing))
    parts = [INTRO, INSTALL, run_order(), "## Files\n"]
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
