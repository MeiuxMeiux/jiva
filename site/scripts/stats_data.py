"""stats data — loaded by stats_build.py. Number formats (mirror of JStats.f in src/stats/js/stats.js, keep both in
step), the few derived headline values the copy needs, and the <details> tables that carry every number for
screen readers and no-JS readers. Only fields of data.json go in; html.escape on every string that comes out."""
import html, math

MONEY = "API-equivalent, not what we pay"


def grp(n):
    return f"{int(round(n)):,}"


def js_round(x):  # Math.round: half up, so 0.5 → 1 (Python's round() is banker's)
    return math.floor(x + 0.5)


def compact(v):
    if v >= 1e9:
        return f"{v / 1e9:.1f} B"
    if v >= 1e8:
        return f"{js_round(v / 1e6)} M"
    if v >= 1e6:
        return f"{v / 1e6:.1f} M"
    return f"{js_round(v / 1e3)}k" if v >= 1e3 else str(js_round(v))


FMT = {"int": grp, "compact": compact, "k": lambda v: f"{js_round(v / 1000)}k",
       "pct": lambda v: f"{v * 100:.1f}%", "pct0": lambda v: f"{js_round(v * 100)}%",
       "per100": lambda v: str(js_round(v * 100)), "num": str}


def usd(v):
    return "$" + (grp(v) if v >= 100 else f"{v:.2f}")


def tok(r):
    return sum(r.get(k, 0) for k in ("input", "cache_write", "cache_read", "output"))


def cost(d):  # same as JStats.cost: by_model × per_million, cache write at the 5-minute rate, residual = other
    out = dict.fromkeys(("cache_read", "cache_write", "output", "input"), 0.0)
    for m, r in d["by_model"].items():
        p = d["pricing"]["per_million"].get(m)
        if p:
            out["cache_read"] += r["cache_read"] * p["cache_read"] / 1e6
            out["cache_write"] += r["cache_write"] * p["cache_write_5m"] / 1e6
            out["output"] += r["output"] * p["output"] / 1e6
            out["input"] += r["input"] * p["input"] / 1e6
    tiers = d.get("cache_write_tiers", {}).get("overall")  # schema 2: exact 5m/1h split replaces the 5m approximation
    if tiers:
        out["cache_write"] = tiers["usd_5m"] + tiers["usd_1h"]
    out["other"] = max(0.0, d["totals"]["usd"] - sum(out.values()))
    return out


def derived(d):
    t, g, rep = d["totals"], d["context_growth"], d["by_repo"]
    first = g[min(g, key=int)]["p50"]
    at100 = g["100"]["p50"] if "100" in g else g[max(g, key=int)]["p50"]
    vel = {k: v["velocity"] for k, v in rep.items() if v.get("velocity")}
    rel = {k: v for k, v in vel.items() if v["days_to_first_release"] is not None}
    fast = min(rel, key=lambda k: rel[k]["days_to_first_release"]) if rel else "none"
    tags = max(vel, key=lambda k: vel[k]["tags_per_week"]) if vel else "none"
    hours = d["by_hour_utc"]
    best_h = max(sorted(hours, key=int), key=lambda k: tok(hours[k]))
    return {"read_token_share": t["cache_read"] / tok(t), "read_cost_share": cost(d)["cache_read"] / t["usd"],
            "ctx_start": first, "ctx_100": at100, "ctx_per_req": (at100 - first) / 99,
            "first3_saving": 1 - d["cold_start"]["handoff"]["tokens_first_3"]["p50"] / d["cold_start"]["fresh"]["tokens_first_3"]["p50"],
            "busiest_hour": f"{int(best_h):02d}:00", "busiest_day": max(sorted(d["by_day"]), key=lambda k: tok(d["by_day"][k])),
            "subagent_share": d["split"]["subagent"]["usd"] / t["usd"],
            "fastest_release_repo": fast, "fastest_release_days": rel[fast]["days_to_first_release"] if rel else "n/a",
            "cw_note": "Cache writes use the dataset's exact 5-minute and 1-hour split." if d.get("cache_write_tiers") else
            "Cache writes are priced at the 5-minute rate (approx.); the gap to the total shows as \"other\".",
            "top_tags_repo": tags, "top_tags": f"{vel[tags]['tags_per_week']:.2f}" if vel else "n/a"}


def table(caption, head, rows, open_=False):
    e = html.escape
    th = "".join(f'<th scope="col">{e(h)}</th>' for h in head)
    body = "".join("<tr>" + "".join((f'<th scope="row">{e(str(c))}</th>' if i == 0 else f"<td>{e(str(c))}</td>")
                                    for i, c in enumerate(r)) + "</tr>" for r in rows)
    return (f'<details class="nums"{" open" if open_ else ""}><summary>{e(caption)}: the numbers</summary><div class="scroll"><table>'
            f"<caption>{e(caption)}</caption><thead><tr>{th}</tr></thead><tbody>{body}</tbody></table></div></details>")


def pcts(q, keys=("p10", "p50", "p90")):
    return [grp(q[k]) for k in keys]


def tables(d):
    t, k = d["totals"], FMT["k"]
    c, pct = cost(d), FMT["pct"]
    cls = [("cache read", "cache_read"), ("cache write", "cache_write"), ("output", "output"), ("fresh input", "input")]
    cs, w = d["cold_start"], d["waste"]
    by = lambda o: [[n, grp(r["requests"]), compact(tok(r)), usd(r["usd"]), pct(r["usd"] / t["usd"])] for n, r in o.items()]
    lead = ["requests", "tokens", f"USD ({MONEY})", "share of USD"]
    yield "hero", table("Totals", ["measure", "value"], [
        ["main sessions", grp(d["scope"]["main_sessions"])], ["subagent sessions", grp(d["scope"]["subagent_sessions"])],
        ["requests", grp(t["requests"])], ["cache read tokens", grp(t["cache_read"])], ["cache hit", pct(t["cache_hit"])],
        ["window", f'{d["window"]["first_day"]} to {d["window"]["last_day"]} ({d["window"]["days"]} days)']])
    yield "tokens", table("Tokens and API-equivalent cost by class", ["class", "tokens", "share of tokens", f"USD ({MONEY})", "share of USD"],
                          [[n, grp(t[f]), pct(t[f] / tok(t)), usd(c[f]), pct(c[f] / t["usd"])] for n, f in cls]
                          + [["other (1h cache writes, fast mode)", "", "", usd(c["other"]), pct(c["other"] / t["usd"])]])
    g = d["context_growth"]
    yield "aging", table("Context by request number", ["request", "sessions", "p10", "p25", "median", "p75", "p90"],
                         [[s, grp(g[s]["n"])] + [k(g[s][q]) for q in ("p10", "p25", "p50", "p75", "p90")] for s in sorted(g, key=int)])
    yield "handoff", table("Cold start vs handoff (tokens)", ["measure", "fresh p10", "fresh median", "fresh p90", "handoff p10", "handoff median", "handoff p90"],
                           [[m.replace("_", " "), *pcts(cs["fresh"][m]), *pcts(cs["handoff"][m])] for m in cs["fresh"] if m != "usd_first_3"]
                           + [[f"USD first 3 requests ({MONEY})", *(usd(cs[s]["usd_first_3"][q]) for s in ("fresh", "handoff") for q in ("p10", "p50", "p90"))]])
    r, fc = d["rotation"], d["sessions"]["final_context"]
    yield "rotation", table("Rotation", ["measure", "value"], [[a.replace("_", " "), grp(v)] for a, v in r.items() if isinstance(v, int)]
                            + [[f"final context {q}", grp(fc[q])] for q in ("p10", "p50", "p90", "max")])
    hours = [[f"{int(h):02d}:00 UTC", grp(v["requests"]), compact(tok(v)), usd(v["usd"])] for h, v in sorted(d["by_hour_utc"].items(), key=lambda x: int(x[0]))]
    days = [[day, grp(v["sessions_started"]), grp(v["requests"]), compact(tok(v)), usd(v["usd"])] for day, v in sorted(d["by_day"].items())]
    boxes = [[b, grp(v["sessions"]), grp(v["requests"]), compact(tok(v)), usd(v["usd"])] for b, v in sorted(d["by_box"].items())]
    yield "hive", (table("By hour", ["hour", "requests", "tokens", f"USD ({MONEY})"], hours)
                   + table("By day", ["day", "sessions started", "requests", "tokens", f"USD ({MONEY})"], days)
                   + table("By machine", ["machine", "sessions", "requests", "tokens", f"USD ({MONEY})"], boxes))
    yield "spend", (table("By role", ["role"] + lead, by(d["by_role"]))
                    + table("Subagents by type", ["type"] + lead, by(d["by_subagent_type"]))
                    + table("By model", ["model"] + lead, by(d["by_model"])))
    rep = sorted(d["by_repo"].items(), key=lambda x: (x[0] in ("misc", "No repo"), -x[1]["requests"]))
    yield "repos", table("Repos", ["repo", "sessions", "requests", "tokens", "cache hit", "median peak context", "idle turns"],
                         [[n, grp(v["sessions"]), grp(v["requests"]), compact(tok(v)), pct(v["cache_hit"]), k(v["max_context_p50"]),
                           FMT["pct0"](v["idle_turn_share"])] for n, v in rep])
    vel = [(n, v["velocity"]) for n, v in sorted(d["by_repo"].items()) if v.get("velocity")]
    yield "speed", table("Velocity", ["repo", "commits", "commits per day", "per active day", "tags", "tags per week", "days to first tag"],
                         [[n, grp(v["commits"]), f'{v["commits_per_day"]:.2f}', f'{v["commits_per_active_day"]:.1f}', grp(v["tags"]),
                           f'{v["tags_per_week"]:.2f}', "no tagged release yet" if v["days_to_first_release"] is None else v["days_to_first_release"]] for n, v in vel])
    yield "waste", table("Waste", ["finding", "value"], [
        ["spend above 150k context", pct(w["high_context"]["share_over_150k"])], ["sessions over 200k", grp(w["high_context"]["sessions_over_200k"])],
        [f"boot tax ({MONEY})", usd(w["boot_tax"]["usd"])], ["sessions booting above 40k", grp(w["boot_tax"]["sessions_initial_over_40k"])],
        ["cache re-warms", grp(w["cache_rewarm_after_gap"]["count"])], [f"re-warm premium ({MONEY})", usd(w["cache_rewarm_after_gap"]["usd_premium"])],
        ["idle turns", f'{grp(w["idle_turns"]["turns"])} of {grp(w["idle_turns"]["of_turns"])}'], ["idle share of spend", pct(w["idle_turns"]["usd_share"])],
        ["re-read share", pct(w["rereads"]["reread_share"])], ["no-edit sessions", grp(w["no_edit_sessions"]["sessions"])]])
    pm = d["pricing"]["per_million"]
    cols = ["input", "output", "cache_write_5m", "cache_write_1h", "cache_read"]
    yield "prices", table(f"USD per million tokens ({MONEY})", ["model", *[c.replace("_", " ") for c in cols]],
                          [[m, *(f"{pm[m][c]:g}" for c in cols)] for m in pm], open_=True)
