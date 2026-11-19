#!/usr/bin/env python3
"""stats scrub — the site-side lock on public stats data (the dataset maker has its own; two locks, two keys).
Run by check.py. Exits 1 on a leak; prints JSON paths, never the offending value.
1. schema: known top-level keys and schema string
2. default deny: every key and every string value of src/stats/data.json must match the allowlist below
3. pattern deny over data.json: paths, @, IPv4, UUID, long hex/base64, sk-, AKIA, gh?_, PRIVATE KEY
4. rendered page: every text node and attribute of build/stats/index.html plus the stats js files: the deny
   patterns, "Repo " followed by anything but a letter label, and an optional private deny list of real names
   (--deny FILE or $JIVA_STATS_DENY: one term per line, never committed; the refresh recipe passes it)
5. --self-test: plants a repo name, host, path, email, IP and key as key and as value; each must be caught,
   and the clean file must pass. Always run before the real scrub."""
import copy, html.parser, json, os, pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
DATA, PAGE = ROOT / "src" / "stats" / "data.json", ROOT / "build" / "stats" / "index.html"
SCHEMAS = {"jiva-token-stats/1", "jiva-token-stats/2"}
TOP = {"schema", "generated_hour", "window", "pricing", "scope", "totals", "split", "sessions", "cold_start", "context_growth",
       "rotation", "by_day", "by_hour_utc", "by_model", "by_role", "by_subagent_type", "by_box", "by_repo", "waste",
       "by_role_model", "tool_calls_per_request", "cache_write_tiers"}
LABEL = re.compile(r"Repo [A-Z]{1,2}|misc|No repo|Box \d|claude-(opus|sonnet|haiku|fable)-\d{1,2}(-\d{1,2})?|\d{1,4}|n\d|n\d_plus"
                   r"|\d{4}-\d\d-\d\d|\d{4}-\d\d-\d\dT\d\d:00Z|jiva-token-stats/\d")
WORDS = set("""worker queen loop desk boss other subagent main all overall Explore Plan fork general-purpose web-fetch
workflow-subagent custom statusline-setup claude-code-guide active_days boot_tax boxes by_box by_day by_hour_utc by_model by_repo
by_role by_role_model by_subagent_type cache_hit cache_read cache_rewarm_after_gap cache_write cache_write_1h cache_write_5m
cache_write_tiers cold_start cold_start_tokens_p50 commits commits_per_active_day commits_per_day context_growth count days
days_to_first_release final_context final_context_hist_20k first_day fresh generated_hour handoff high_context hist
idle_turn_share idle_turns initial_cache_write initial_context initial_context_p50 input last_day main_sessions max
max_context max_context_hist_20k max_context_p50 mean mean_when_any n next_cache_write_tokens no_edit_sessions note of_turns
output p10 p25 p50 p75 p90 per_million pricing prompts_per_session reads repos_labelled requests requests_over_150k
requests_over_200k requests_per_session requests_per_session_p50 requests_with_tools reread_share rereads rotation
rotations_150_210k schema scope sessions sessions_ending_150_210k sessions_initial_over_40k sessions_over_200k
sessions_rotated_or_compacted sessions_started share_1h share_of_role_usd_over_150k share_over_150k source span_days split
subagent_sessions tags tags_per_week tokens tokens_first_3 tokens_to_first_tool tool_calls tool_calls_per_request totals
turns usd usd_1h usd_5m usd_est usd_first_3 usd_over_150k usd_over_200k usd_premium usd_share velocity waste window
write_1h write_5m""".split())
SOURCE = "Anthropic API list prices (platform.claude.com/docs/en/about-claude/pricing), as of 2026-11-03"
NOTES = {SOURCE,
         "API-equivalent dollars, not what is actually paid: these sessions run on a flat subscription plan",
         "Cache write of the first request of every main session",
         "Human or injected prompt answered with zero tool calls (acks, polls, status pings)",
         "Main sessions by final (or max) context, bucket = lower bound in thousands of tokens, 300 = 300k or more",
         "Read of a file already read in the same session; cost estimated from the next request cache write",
         "Request after a gap of more than 5 minutes that rewrote more cache than it read",
         "Three boxes; work-desk boxes and work-related project dirs excluded; repos with fewer than 5 sessions pooled as misc",
         "tool_use blocks per API request; parallel calls in one message count once per block"}
DENY = [(r"(?<![\w.+-])[\w.+-]+@[\w-]+(\.[\w-]+)+", "email or user@host"), (r"(?<![\d.])(\d{1,3}\.){3}\d{1,3}(?![\d.])", "IPv4"),
        (r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}", "UUID"), (r"\b[0-9a-f]{24,}\b", "long hex"),
        (r"[A-Za-z0-9+/_-]{40,}={0,2}", "base64-like"), (r"\bsk-[A-Za-z0-9_-]{6,}", "sk- key"), (r"AKIA[0-9A-Z]{12,}", "AWS key"),
        (r"\bgh[pousr]_[A-Za-z0-9]{8,}", "GitHub token"), (r"PRIVATE KEY", "private key"),
        (r"(^|[\s\"'(=])(/(home|root|srv|var|etc|mnt|opt|usr|tmp)/|~/|[A-Za-z]:\\)", "absolute path")]
DATA_PATH = re.compile(r"[/\\~]")


def scan_data(d):
    bad = []
    if not isinstance(d, dict) or d.get("schema") not in SCHEMAS:
        return ["$.schema: unknown schema"]
    bad += [f"$.{k}: unknown top-level key" for k in d if k not in TOP]

    def walk(o, path):
        if isinstance(o, dict):
            for k, v in o.items():
                if not isinstance(k, str) or not (LABEL.fullmatch(k) or k in WORDS):
                    bad.append(f"{path}: key not on the allowlist")
                walk(v, f"{path}.{k}" if (LABEL.fullmatch(str(k)) or str(k) in WORDS) else f"{path}.<key>")
        elif isinstance(o, list):
            for i, v in enumerate(o):
                walk(v, f"{path}[{i}]")
        elif isinstance(o, str):
            if not (LABEL.fullmatch(o) or o in WORDS or o in NOTES):
                bad.append(f"{path}: string value not on the allowlist")
            if o != SOURCE and DATA_PATH.search(o) and not LABEL.fullmatch(o):
                bad.append(f"{path}: path-like string")
        elif not (o is None or isinstance(o, (int, float))):
            bad.append(f"{path}: unexpected type")
    walk(d, "$")
    text = json.dumps(d)
    bad += [f"data.json: matches deny pattern ({what})" for rx, what in DENY if re.search(rx, text)]
    return bad


class Text(html.parser.HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.parts = []

    def handle_starttag(self, tag, attrs):
        self.parts += [v for k, v in attrs if v and k != "integrity"]  # sri hashes are base64 by design

    def handle_data(self, data):
        self.parts.append(data)


def scan_page(terms):
    if not PAGE.is_file():
        return ["build/stats/index.html missing (run site-build)"]
    p = Text()
    p.feed(PAGE.read_text(encoding="utf-8"))
    sources = [("stats/index.html", "\n".join(p.parts))]
    sources += [(f"stats/js/{f.name}", f.read_text(encoding="utf-8")) for f in sorted((PAGE.parent / "js").glob("*.js"))]
    bad = []
    for name, text in sources:
        bad += [f"{name}: matches deny pattern ({what})" for rx, what in DENY if re.search(rx, text)]
        if re.search(r"\bRepo (?![A-Z]{1,2}\b)", text):
            bad.append(f"{name}: 'Repo' followed by something other than a letter label")
        low = text.lower()
        bad += [f"{name}: contains a private deny term (#{i + 1})" for i, t in enumerate(terms) if t in low]
    return bad


def self_test(clean):
    if scan_data(clean):
        return ["self-test: the clean data.json does not pass: " + "; ".join(scan_data(clean)[:3])]
    plants = ["acme-shop-backend", "box7.example-host.net", "/home/someone/project", "dev@example.org", "10.20.30.40",
              # key-shaped plants are joined at run time so no whole secret-shaped literal sits in the repo
              "".join(["sk-", "ant-api03-", "PLANTED" * 3]), "".join(["AK", "IA", "PLANTEDPLANTED12"]),
              "".join(["gh", "p_", "PLANTEDplanted123456"])]
    missed = []
    for leak in plants:
        as_value, as_key = copy.deepcopy(clean), copy.deepcopy(clean)
        as_value["by_repo"]["Repo A"]["note"] = leak
        as_key["by_repo"][leak] = as_key["by_repo"].pop("Repo A")
        missed += [f"self-test: planted {kind} #{plants.index(leak) + 1} not caught" for kind, doc in
                   (("value", as_value), ("key", as_key)) if not scan_data(doc)]
    print(f"site-check: stats scrub self-test {len(plants) * 2 - len(missed)}/{len(plants) * 2} plants caught, clean file passes")
    return missed


def main():
    args, deny = sys.argv[1:], os.environ.get("JIVA_STATS_DENY", "")
    if "--deny" in args:
        deny = args[args.index("--deny") + 1]
    terms = [t.strip().lower() for t in pathlib.Path(deny).read_text(encoding="utf-8").splitlines()
             if len(t.strip()) >= 4 and not t.startswith("#")] if deny else []
    data = json.loads(DATA.read_text(encoding="utf-8"))
    bad = self_test(data)
    if "--self-test" not in args:
        bad += scan_data(data) + scan_page(terms)
        print(f"site-check: stats scrub data+page {'FAIL' if bad else 'ok'} (private deny terms: {len(terms) or 'none passed'})")
    for b in bad:
        print("FAIL", b)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
