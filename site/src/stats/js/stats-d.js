// /stats charts D: repo cards (07), speed lollipops + first-release timeline (08), waste meters (09).
"use strict";
(function () {
  var S = window.JStats, C = S.charts, f = S.f;
  var pooled = function (k) { return k === "misc" || k === "No repo"; };
  var order = function (R) {
    return Object.keys(R).sort(function (a, b) {
      return (pooled(a) - pooled(b)) || (R[b].requests - R[a].requests);
    });
  };

  function mini(host, share) {
    var s = S.svg(host, 44, 44, "cache hit " + f.pct(share)), r = 17, len = 2 * Math.PI * r;
    S.el("circle", { cx: 22, cy: 22, r: r, class: "ring-rest thin" }, s);
    var a = S.el("circle", { cx: 22, cy: 22, r: r, class: "ring-arc thin", "stroke-dasharray": len.toFixed(1), transform: "rotate(-90 22 22)" }, s);
    a.style.setProperty("--off", (len * (1 - share)).toFixed(1) + "px");
    a.style.setProperty("--len", len.toFixed(1) + "px");
  }

  C.repos = function (d, host) {
    var R = d.by_repo, keys = order(R), top = 0, grid = S.h("ul", "repos", host);
    keys.forEach(function (k) { top = Math.max(top, S.tok(R[k])); });
    keys.forEach(function (k, i) {
      var r = R[k], card = S.h("li", "repo" + (pooled(k) ? " muted" : ""), grid), head = S.h("div", "repo-h", card);
      S.delay(card, i * 60);
      var t = S.h("div", null, head);
      S.h("h3", null, t, k);
      S.h("p", "sub", t, f.int(r.sessions) + " sessions · " + f.int(r.requests) + " requests");
      mini(head, r.cache_hit);
      [[S.tok(r) / top, f.compact(S.tok(r)) + " tokens", "m1"],
        [Math.min(1, r.max_context_p50 / 200000), "median peak context " + f.k(r.max_context_p50) + " of 200k", r.max_context_p50 >= 150000 ? "m0" : "m2"]
      ].forEach(function (m) {
        var line = S.h("span", "hbar", card), i2 = S.h("i", m[2], line);
        i2.style.setProperty("--k", m[0].toFixed(3));
        S.h("em", null, line, m[1]);
      });
      S.h("p", "sub", card, "cache hit " + f.pct(r.cache_hit) + " · idle turns " + f.pct0(r.idle_turn_share));
    });
  };

  function lolli(host, title, rows, key, fmt) {
    var fig = S.h("figure", "lolli", host), W = Math.max(240, Math.floor(host.clientWidth / (host.clientWidth > 860 ? 3 : 1)) - 24);
    var max = Math.max.apply(null, rows.map(function (r) { return r[1][key]; })) || 1, RH = 26, L = 64;
    S.h("figcaption", "stack-t", fig, title);
    var s = S.svg(fig, W, rows.length * RH + 6, title + ": " + rows.map(function (r) { return r[0] + " " + fmt(r[1][key]); }).join(", "));
    rows.forEach(function (r, i) {
      var y = i * RH + 16, v = r[1][key], x = L + v / max * (W - L - 56), g = S.el("g", {}, s);
      S.el("text", { x: 0, y: y + 4, class: "lbl sm" }, g, r[0]);
      S.el("line", { x1: L, x2: x, y1: y, y2: y, class: "stem grow" }, g);
      S.delay(S.el("circle", { cx: x, cy: y, r: 5, class: "m2 ring2 fade" }, g), i * 50);
      S.el("text", { x: x + 10, y: y + 4, class: "val sm" }, g, fmt(v));
    });
  }

  C.speed = function (d, host, W) {
    var rows = Object.keys(d.by_repo).filter(function (k) { return d.by_repo[k].velocity; }).sort()
      .map(function (k) { return [k, d.by_repo[k].velocity]; });
    if (!rows.length) { S.h("p", null, host, "No repo carries velocity numbers in this dataset."); return; }
    var wrap = S.h("div", "lollis", host), n1 = function (v) { return v.toFixed(1); }, n2 = function (v) { return v.toFixed(2); };
    lolli(wrap, "Commits per day", rows, "commits_per_day", n1);
    lolli(wrap, "Commits per active day", rows, "commits_per_active_day", n1);
    lolli(wrap, "Tags per week", rows, "tags_per_week", n2);
    var rel = rows.filter(function (r) { return r[1].days_to_first_release != null; });
    var max = Math.max.apply(null, rel.map(function (r) { return r[1].days_to_first_release; }).concat([1])), RH = 30, L = 64;
    S.h("h3", "stack-t", host, "Days from first commit to first tag");
    var s = S.svg(host, W, rows.length * RH + 8, "Days to first release: " + rows.map(function (r) {
      return r[0] + " " + (r[1].days_to_first_release == null ? "no tagged release yet" : r[1].days_to_first_release + " days");
    }).join(", "));
    rows.forEach(function (r, i) {
      var y = i * RH + 18, v = r[1].days_to_first_release, g = S.el("g", {}, s);
      S.el("text", { x: 0, y: y + 4, class: "lbl sm" }, g, r[0]);
      S.el("circle", { cx: L + 4, cy: y, r: 4, class: "m6" }, g);
      if (v == null) { S.el("text", { x: L + 16, y: y + 4, class: "axis" }, g, "no tagged release yet"); return; }
      var x = L + 4 + v / max * (W - L - 110);
      S.el("line", { x1: L + 4, x2: x, y1: y, y2: y, class: "stem grow" }, g);
      S.delay(S.el("path", { d: "M" + x + " " + (y + 6) + "V" + (y - 10) + "l10 4l-10 4", class: "flag m0 fade" }, g), i * 60);
      S.el("text", { x: x + 16, y: y + 4, class: "val sm" }, g, v + " days");
    });
  };

  C.waste = function (d, host) {
    var w = d.waste, t = d.totals.usd, grid = S.h("ul", "waste", host);
    var cards = [
      [w.high_context.share_over_150k, f.pct(w.high_context.share_over_150k) + " of spend", "happened above 150k tokens of context; " +
        f.int(w.high_context.sessions_over_200k) + " sessions went past 200k.", "Jiva cells write a handoff and stop at the 150k nudge."],
      [w.boot_tax.usd / t, S.usd(w.boot_tax.usd, host) + " boot tax", "the first cache write of every session; " +
        f.int(w.boot_tax.sessions_initial_over_40k) + " sessions booted above 40k.", "Jiva cells boot from a 40-line handoff and a 20-line card."],
      [w.cache_rewarm_after_gap.usd_premium / t, f.int(w.cache_rewarm_after_gap.count) + " cache re-warms", "averaging " +
        f.k(w.cache_rewarm_after_gap.tokens / w.cache_rewarm_after_gap.count) + " tokens each, " + S.usd(w.cache_rewarm_after_gap.usd_premium, host) + " premium.", "Next: end a session instead of letting it wait out the cache."],
      [w.idle_turns.turns / w.idle_turns.of_turns, f.int(w.idle_turns.turns) + " of " + f.int(w.idle_turns.of_turns) + " turns idle",
        "answered with no tool call: " + f.pct(w.idle_turns.usd_share) + " of spend.", "Next: status pings go to files, not prompts."],
      [w.rereads.reread_share, f.pct(w.rereads.reread_share) + " of reads repeated", f.int(w.rereads.rereads) + " re-reads of a file already read in the same session.",
        "Next: handoffs name the files that matter."],
      [w.no_edit_sessions.usd_share, "Coordination, not waste", f.int(w.no_edit_sessions.sessions) + " sessions made no Edit or Write call (" +
        f.pct(w.no_edit_sessions.usd_share) + " of spend). Edits through the shell are not counted.", "Desks, queens and loops mostly read and route.", true]
    ];
    cards.forEach(function (c, i) {
      var li = S.h("li", c[4] ? "neutral" : null, grid);
      S.delay(li, i * 70);
      S.h("h3", null, li, c[1]);
      var m = S.h("span", "meter", li), bar = S.h("i", c[4] ? "m6" : "m0", m);
      bar.style.setProperty("--k", Math.min(1, c[0]).toFixed(3));
      m.setAttribute("aria-hidden", "true");
      S.h("p", null, li, c[2]);
      S.h("p", "changed", li, c[3]);
    });
  };
}());
