#!/usr/bin/env python3
"""site assets — loaded by build.py (importlib; -I drops the script dir from sys.path).
packs(): discover every packs/<name>/ (not local) with pack.json + avatars/01..12-s.webp, copy
  thumbs → build/avatars/<name>/NN-s.<sha8>.webp, write avatars/packs.<sha8>.json (manifest the
  rotator fetches) and return it. "default" first, then by dir name. SITE_PACKS=<dir> overrides
  the packs root (scratch tests with a fake second pack; never commit fake packs).
art(): copy src/img/*.webp → build/img/<stem>.<sha8>.webp and return generated CSS that sets the
  --art-* custom properties only for files that exist (absent art = no rule = clean degrade).
LAZY: build paths that load after interaction/scroll; check.py's initial-load budget skips them."""
import hashlib, json, os, pathlib, re, shutil

ROOT = pathlib.Path(__file__).resolve().parent.parent
PACKS = pathlib.Path(os.environ.get("SITE_PACKS") or ROOT.parent / "packs")
SLOTS = range(1, 13)
NAME = re.compile(r"^[a-z0-9][a-z0-9_-]{0,31}$")
COLOR = re.compile(r"^#[0-9a-fA-F]{6}$")
NAVY = (6, 1, 40)
# art file stem → CSS custom property; emblems are emblem-<section id>.webp
ART = {"hero-bg": "--art-hero", "header-banner": "--art-banner", "section-tile": "--art-tile"}
SECTIONS = ("problem", "how", "verbs", "ceiling", "souls", "dashboard", "security", "install", "reference")
EAGER_ART = ("hero-bg", "header-banner")  # above the fold: counted in the initial-load budget


def sha8(f):
    return hashlib.sha256(f.read_bytes()).hexdigest()[:8]


def lum(h):
    c = [int(h[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    c = [x / 12.92 if x <= .03928 else ((x + .055) / 1.055) ** 2.4 for x in c]
    return .2126 * c[0] + .7152 * c[1] + .0722 * c[2]


def readable(h):  # same 3:1 floor roster.sh check uses for slot colors on #060128
    bg = lum("#%02x%02x%02x" % NAVY)
    return bool(COLOR.match(h)) and (lum(h) + .05) / (bg + .05) >= 3


def load(d):
    try:
        meta = json.loads((d / "pack.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    by = {s.get("slot"): s for s in meta.get("slots", []) if isinstance(s, dict)}
    if not all((d / "avatars" / f"{n:02d}-s.webp").is_file() and n in by for n in SLOTS):
        return None
    return meta, by


def packs(out):
    found = []
    for d in sorted(PACKS.iterdir() if PACKS.is_dir() else [], key=lambda p: (p.name != "default", p.name)):
        if d.name == "local" or not d.is_dir() or not NAME.match(d.name) or not (got := load(d)):
            continue
        meta, by = got
        (out / "avatars" / d.name).mkdir(parents=True)
        slots = []
        for n in SLOTS:
            th = d / "avatars" / f"{n:02d}-s.webp"
            dst = out / "avatars" / d.name / f"{n:02d}-s.{sha8(th)}.webp"
            shutil.copy(th, dst)
            s, color = by[n], str(by[n].get("color", ""))
            slots.append({"slot": n, "name": str(s.get("name") or f"w{n}")[:24],
                          "color": color.lower() if readable(color) else None,
                          "src": dst.relative_to(out).as_posix()})
        label = str(meta.get("title") or meta.get("name") or d.name).replace("-", " ")[:32]
        found.append({"id": d.name, "label": label, "slots": slots})
    if not found:
        raise SystemExit(f"site-build: no complete avatar pack under {PACKS}")
    body = json.dumps({"v": 1, "packs": found}, separators=(",", ":")).encode()
    man = out / "avatars" / f"packs.{hashlib.sha256(body).hexdigest()[:8]}.json"
    man.write_bytes(body)
    return found, man.relative_to(out).as_posix()


def art(src, out):
    rules, files = [], sorted((src / "img").glob("*.webp")) if (src / "img").is_dir() else []
    if files:
        (out / "img").mkdir()
    for f in files:
        dst = out / "img" / f"{f.stem}.{sha8(f)}.webp"
        shutil.copy(f, dst)
        url = f'url("../img/{dst.name}")'
        if f.stem in ART:
            sel = ".band.in" if f.stem == "section-tile" else ":root"
            rules.append(f"{sel}{{{ART[f.stem]}:{url}}}")
        elif f.stem.startswith("emblem-") and f.stem[7:] in SECTIONS:
            sid = f.stem[7:]  # box reserved now (no shift), image set on reveal → lazy fetch
            rules.append(f'#{sid} h2::before{{content:""}}#{sid}.in{{--art-emblem:{url}}}')
    return "\n".join(rules) + "\n" if rules else ""


def lazy(rel, first_pack):
    """True for build files that load only after scroll/interaction (separate 3 MB cap)."""
    p = pathlib.PurePosixPath(rel)
    if p.parts[:1] == ("avatars",):
        return len(p.parts) == 2 or p.parts[1] != first_pack  # manifest + other packs
    return p.parts[:1] == ("img",) and not p.name.startswith(EAGER_ART)
