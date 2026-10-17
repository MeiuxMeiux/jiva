# dash_hist — /history + /history/summary for core/dash-api.py (loaded by path; python -I drops the script dir).
# Source: $J/history.jsonl (core/history.sh; kinds + fields per notes/history.md). Rows are re-allowlisted per kind:
# unknown kinds and fields are skipped, strings ≤80, numbers stay numbers. /history reads the file backwards in
# blocks until it has a page, never returns more than one page; summary is cached on (mtime, size).
import json, os, re
FIELDS = {"claim": ("n",), "report": ("st",), "ship": ("sha",), "handoff": ("lines",), "ask": ("id", "class"),
          "answer": ("id", "by"), "expire": ("id", "class"), "nudge": ("name", "tok"), "life": ("name", "why", "tok"),
          "heal": ("name",), "park": ("name", "why", "tok"), "trip": ("name", "trip"), "quota": ("st", "q5h", "q7d"),
          "lease": ("st", "age"), "tok": ("tok", "s", "q5h", "q7d")}
NAME, LANE, BUCKETS, MAXS = re.compile(r"[\w.-]{1,32}"), ("life", "ship", "trip", "ask"), 200, 32
class Bad(Exception): pass
def num(v): return v if isinstance(v, (int, float)) and not isinstance(v, bool) else None
def clean(o):  # raw dict → allowlisted row, or None
    k = o.get("kind") if isinstance(o, dict) else None
    if k not in FIELDS or num(o.get("ts")) is None: return None
    r = {"ts": o["ts"], "kind": k, "who": str(o.get("who", ""))[:80]}
    for f in FIELDS[k]:
        v = o.get(f)
        if f == "s" and isinstance(v, dict):
            r["s"] = {n: t for n, t in list(v.items())[:MAXS] if NAME.fullmatch(n) and num(t) is not None}
        elif num(v) is not None or v is None: r[f] = v
        else: r[f] = re.sub(r"[\x00-\x1f\x7f]", " ", str(v))[:80]
    return r
def who(r): return r.get("name") if isinstance(r.get("name"), str) and r["kind"] not in ("ask", "ship") else r["who"]
def rev(p, block=65536):  # lines of p, last first, without reading the whole file at once
    try: f = open(p, "rb")
    except OSError: return
    with f:
        end, tail = f.seek(0, 2), b""
        while end > 0:
            n = min(block, end); end -= n; f.seek(end); buf = f.read(n) + tail
            ls = buf.split(b"\n"); tail = ls.pop(0)
            for l in reversed(ls): yield l
        yield tail
def rows_rev(p):
    for l in rev(p):
        try: r = clean(json.loads(l))
        except (ValueError, UnicodeDecodeError): continue
        if r: yield r
def arg(q, k, d=None): v = q.get(k, [d])[0]; return d if v == "" else v
def page(J, q):  # newest first; next page = ?before=<last ts> (a ts tie at the edge is completed, not split)
    try: n = int(arg(q, "n", "100"))
    except ValueError: raise Bad(400, "n must be an integer")
    if not 1 <= n <= 500: raise Bad(400, "n must be 1..500")
    b = arg(q, "before")
    try: b = float(b) if b is not None else None
    except ValueError: raise Bad(400, "before must be an epoch number")
    if b is not None and not 0 < b < 1e11: raise Bad(400, "before must be an epoch number")
    ks = set(filter(None, (arg(q, "kind") or "").split(",")))
    if ks - FIELDS.keys(): raise Bad(400, "unknown kind")
    ns = set(filter(None, (arg(q, "name") or "").split(",")))
    if any(not NAME.fullmatch(x) for x in ns) or len(ns) > MAXS: raise Bad(400, "name must be [\\w.-]{1,32}")
    out = []
    for r in rows_rev(os.path.join(J, "history.jsonl")):
        if b is not None and r["ts"] >= b: continue
        if ks and r["kind"] not in ks or ns and who(r) not in ns: continue
        if len(out) >= n and r["ts"] != out[-1]["ts"]: break
        if len(out) >= 2 * n: break
        out.append(r)
    return sorted(out, key=lambda r: -r["ts"])
_cache = [None, None]
def summary(J, q=None):  # counts per kind, per-session lives/ships/trips/asks, lanes + tok series in ≤200 buckets
    p = os.path.join(J, "history.jsonl")
    try: st = os.stat(p); key = (st.st_mtime_ns, st.st_size)
    except OSError: key = None
    if key and _cache[0] == key: return _cache[1]
    rs = list(rows_rev(p))[::-1] if key else []
    counts, ses = {}, {}
    for r in rs: counts[r["kind"]] = counts.get(r["kind"], 0) + 1
    t0, t1 = (min(r["ts"] for r in rs), max(r["ts"] for r in rs)) if rs else (0, 0)
    w = max(1, -(-(t1 - t0 + 1) // BUCKETS)); nb = min(BUCKETS, int((t1 - t0) // w) + 1) if rs else 0
    for r in rs:
        if r["kind"] not in LANE: continue
        s = str(who(r))
        if not NAME.fullmatch(s) or (s not in ses and len(ses) >= MAXS): continue
        x = ses.setdefault(s, {"lives": 0, "ships": 0, "trips": 0, "asks": 0, "lane": {}})
        x[r["kind"] + "s" if r["kind"] != "life" else "lives"] += 1
        i = str(int((r["ts"] - t0) // w)); m = x["lane"].setdefault(i, {}); m[r["kind"]] = m.get(r["kind"], 0) + 1
    tk = {}
    for r in rs:
        if r["kind"] == "tok" and num(r.get("tok")) is not None:
            tk[int((r["ts"] - t0) // w)] = [r["ts"], r["tok"], num(r.get("q5h")), num(r.get("q7d"))]   # last per bucket
    out = {"counts": counts, "sessions": ses, "t0": t0, "t1": t1, "width": w, "buckets": nb,
           "tok": [tk[i] for i in sorted(tk)]}
    if key: _cache[:] = [key, out]
    return out
