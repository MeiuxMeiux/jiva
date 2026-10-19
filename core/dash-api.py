# dash-api — the dash's read-only JSON API (run by core/dash.sh: python3 -I dash-api.py <port>; env DJ DWWW DPROT DTTL
# DQUIET DTARGET). Every endpoint is computed per GET; static files come from DWWW (symlinks only, see dash.sh).
# /commits?before=<sha>&n=50 (n 1..100) and /commit/<sha>: git of DTARGET, sha must be [0-9a-f]{7,40} else 400,
# unknown → 404; diffstat only (numstat), never diff bodies; never more than one page of history per response.
# /history?before=<ts>&n=100&kind=a,b&name=w1 (n 1..500) + /history/summary: .jiva/history.jsonl via core/dash_hist.py.
# GET/HEAD only. Host header must be 127.0.0.1|localhost|[::1]:<port> or one of DHOSTS (space-separated host[:port],
# e.g. a tailscale name) else 421 — a DNS-rebinding page can't read the API. No CORS; nosniff + no-referrer + DENY.
import http.server, importlib.util, json, os, re, subprocess, sys, time, urllib.parse
J, WWW, PROT, TTL = os.environ["DJ"], os.environ["DWWW"], os.environ["DPROT"].split(), int(os.environ["DTTL"])
QUIET, T = int(os.environ.get("DQUIET", "40000")), os.environ.get("DTARGET", ".")
PORT = int(sys.argv[1])
HOSTS = {f"{h}:{PORT}" for h in ("127.0.0.1", "localhost", "[::1]")} | set(os.environ.get("DHOSTS", "").lower().split())
SHA = re.compile(r"[0-9a-f]{7,40}")
class Bad(Exception): pass  # args: (http code, message)
_s = importlib.util.spec_from_file_location("dash_hist", os.path.join(os.path.dirname(os.path.realpath(__file__)), "dash_hist.py"))
HIST = importlib.util.module_from_spec(_s); _s.loader.exec_module(HIST)   # /history + /history/summary (see its header)
def lines(p):
    try:
        with open(p, errors="replace") as f: return [l.rstrip("\n")[:200] for l in f if l.strip()]
    except OSError: return []
def flags(now):
    d = os.path.join(J, "flags"); ps = [os.path.join(d, n) for n in sorted(os.listdir(d))] if os.path.isdir(d) else []
    return [{"name": os.path.basename(p), "age": int(now - os.path.getmtime(p)), "first": (lines(p) or [""])[0],
             "last": (lines(p) or [""])[-1]} for p in ps if os.path.isfile(p)]
def ask(a, now):
    c = str(a.get("class") or "decision")
    return {"id": str(a.get("id", "")), "class": c, "text": str(a.get("q", ""))[:200],
            "age": int(now - (a.get("ts") or now)), "protected": c in PROT}
def asks(now):
    rows = []
    for l in lines(os.path.join(J, "asks", "open.jsonl")):
        try: rows.append(ask(json.loads(l), now))
        except (ValueError, TypeError, AttributeError): pass
    return rows
def lease(now):
    ls = lines(os.path.join(J, "lease", "queen"))
    try: age = int(now - int(ls[0].split()[0]))
    except (IndexError, ValueError): return {"state": "none", "age": None}
    return {"state": "stale" if age > 3 * TTL else "fresh", "age": age}
def bline(l, sod):  # "HH:MM name  verb text" → dict; age from time-of-day (comb has no date; wraps at midnight)
    p = l.split("\t", 1)[0].split(None, 3); hm = p[0].split(":") if p else []
    try: age = (sod - int(hm[0]) * 3600 - int(hm[1]) * 60) % 86400
    except (IndexError, ValueError): return None
    return {"name": p[1][:32] if len(p) > 1 else "", "ts": p[0][:5], "age": age,
            "verb": (p[2] if len(p) > 2 else "").rstrip(":")[:24], "text": p[3] if len(p) > 3 else ""}
def comb(now):  # last line per session + last 20 overall; quiet = state tok grew >QUIET past the burn marker
    t = time.localtime(now); sod = t.tm_hour * 3600 + t.tm_min * 60 + t.tm_sec
    rows = [r for r in (bline(l, sod) for l in lines(os.path.join(J, "comb.log"))) if r]
    last = {r["name"]: r for r in rows}
    try: ss = json.load(open(os.path.join(J, "state.json"))).get("sessions") or []
    except (OSError, ValueError, AttributeError): ss = []
    quiet = []
    for x in ss:
        try: lt = int(lines(os.path.join(J, "nudged", str(x.get("name")) + ".last"))[0].split()[1])
        except (IndexError, ValueError, AttributeError): continue
        if isinstance(x.get("tok"), int) and x["tok"] - lt > QUIET: quiet.append(str(x["name"]))
    return {"last": list(last.values()), "tail": rows[-20:], "quiet": quiet}
def alerts(now):  # notify.log (core/notify.sh): "<epoch> <text>"; malformed lines skipped
    rows = []
    for l in lines(os.path.join(J, "notify.log")):
        p = l.split(None, 1)
        try: ts = int(p[0])
        except (IndexError, ValueError): continue
        rows.append({"ts": ts, "age": int(now - ts), "text": p[1] if len(p) > 1 else ""})
    return rows[-20:][::-1]
def git(*a):
    r = subprocess.run(["git", "-C", T, *a], capture_output=True, text=True, errors="replace", timeout=5)
    if r.returncode: raise Bad(404, "unknown commit")
    return r.stdout
def sha(v):
    if not SHA.fullmatch(v or ""): raise Bad(400, "sha must be [0-9a-f]{7,40}")
    return v
def soul(trailer):  # "jiva: wN|queen|desk" trailer; trailer-less (desk/keeper) commits → "desk"
    t = trailer.split(",")[0].strip()
    return t if re.fullmatch(r"w\d{1,2}|queen|desk", t) else "desk"
def commits(now, q):  # newest first; next page = ?before=<last sha>
    try: n = int(q.get("n", ["50"])[0])
    except ValueError: raise Bad(400, "n must be an integer")
    if not 1 <= n <= 100: raise Bad(400, "n must be 1..100")
    b = q.get("before", [None])[0]
    rev = [sha(b), "--skip=1"] if b is not None else ["HEAD"]
    if b is None and subprocess.run(["git", "-C", T, "rev-parse", "-q", "--verify", "HEAD"], capture_output=True).returncode: return []
    out = git("log", "-n", str(n), "--format=%x1e%H%x1f%s%x1f%an%x1f%ct%x1f%(trailers:key=jiva,valueonly,separator=%x2c)",
              "--shortstat", *rev, "--")
    rows = []
    for rec in out.split("\x1e")[1:]:
        head, _, rest = rec.partition("\n"); f = head.split("\x1f")
        if len(f) < 5: continue
        m = re.search(r"(\d+) files? changed", rest)
        rows.append({"sha": f[0], "subject": f[1][:200], "soul": soul(f[4]), "ts": int(f[3]), "files": int(m[1]) if m else 0})
    return rows
TRAILER = re.compile(r"(jiva|co-authored-by|signed-off-by):", re.I)
def commit(now, h):  # {sha, subject, body (first non-trailer line), stat: [{file, add, del}]}; binary → null counts
    head, _, rest = git("show", "--numstat", "--format=%H%x1f%s%x1f%b%x1e", sha(h), "--").partition("\x1e")
    f = head.split("\x1f", 2)
    body = next((l.strip() for l in f[2].splitlines() if l.strip() and not TRAILER.match(l.strip())), "") if len(f) > 2 else ""
    stat = []
    for l in rest.splitlines():
        p = l.split("\t", 2)
        if len(p) == 3: stat.append({"file": p[2][:300], "add": int(p[0]) if p[0].isdigit() else None, "del": int(p[1]) if p[1].isdigit() else None})
    return {"sha": f[0], "subject": f[1][:200] if len(f) > 1 else "", "body": body[:200], "stat": stat[:300]}
API = {"/flags": flags, "/asks": asks, "/lease": lease, "/comb": comb, "/alerts": alerts}
class H(http.server.SimpleHTTPRequestHandler):
    def __init__(s, *a, **k): super().__init__(*a, directory=WWW, **k)
    def log_message(s, *a): pass
    def end_headers(s):
        for k, v in (("X-Content-Type-Options", "nosniff"), ("Referrer-Policy", "no-referrer"), ("X-Frame-Options", "DENY")):
            s.send_header(k, v)
        super().end_headers()
    def host_ok(s):
        if (s.headers.get("Host") or "").lower() in HOSTS: return True
        s.send(421, {"error": "bad host"}); return False
    def do_HEAD(s):
        if s.host_ok(): super().do_HEAD()
    def send(s, code, obj):
        b = json.dumps(obj).encode()
        s.send_response(code); s.send_header("Content-Type", "application/json"); s.send_header("Cache-Control", "no-store")
        s.send_header("Content-Length", str(len(b))); s.end_headers(); s.wfile.write(b)
    def do_GET(s):
        if not s.host_ok(): return
        u = urllib.parse.urlsplit(s.path); now = time.time()
        try:
            if u.path == "/history": return s.send(200, HIST.page(J, urllib.parse.parse_qs(u.query)))
            if u.path == "/history/summary": return s.send(200, HIST.summary(J))
            if u.path == "/commits": return s.send(200, commits(now, urllib.parse.parse_qs(u.query)))
            if u.path.startswith("/commit/"): return s.send(200, commit(now, u.path[8:]))
            if u.path in API: return s.send(200, API[u.path](now))
        except (Bad, HIST.Bad) as e: return s.send(e.args[0], {"error": e.args[1]})
        except subprocess.TimeoutExpired: return s.send(504, {"error": "git timed out"})
        return super().do_GET()
http.server.ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
