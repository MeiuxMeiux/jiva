// /stats charts B: cold start vs handoff dumbbells (03), rotation life cycle + final-context strip (04).
"use strict";
(function () {
  var S = window.JStats, C = S.charts, f = S.f;
  var ROWS = [["initial_context", "context at the first request"], ["initial_cache_write", "cache written at the first request"],
    ["tokens_to_first_tool", "tokens up to the first tool call"], ["tokens_first_3", "tokens in the first 3 requests"]];

  C.cold = function (d, host, W) {
    var F = d.cold_start.fresh, Hd = d.cold_start.handoff, top = 0;
    ROWS.forEach(function (r) { top = Math.max(top, F[r[0]].p90, Hd[r[0]].p90); });
    top *= 1.04;
    var x = function (v) { return 8 + v / top * (W - 16); }, RH = 64, H = ROWS.length * RH + 24;
    var last = ROWS[ROWS.length - 1][0];
    var s = S.svg(host, W, H, "Fresh start versus handoff: " + f.k(F[last].p50) + " versus " + f.k(Hd[last].p50) +
      " tokens in the first 3 requests (medians)", "Dumbbell rows: pink dot fresh median, cyan dot handoff median, faint p10 to p90 whiskers.");
    var rd = S.readout(host);
    ROWS.forEach(function (r, i) {
      var a = F[r[0]], b = Hd[r[0]], y = i * RH, cy = y + 40, diff = b.p50 - a.p50, g = S.el("g", { class: "row" }, s);
      S.el("text", { x: 0, y: y + 16, class: "lbl" }, g, r[1]);
      S.el("text", { x: W, y: y + 16, class: "val end" }, g, (diff < 0 ? "−" : "+") + f.k(Math.abs(diff)) + ", " +
        (diff < 0 ? "−" : "+") + f.pct0(Math.abs(diff) / a.p50));
      S.el("line", { x1: x(a.p10), x2: x(a.p90), y1: cy - 9, y2: cy - 9, class: "whisk w0" }, g);
      S.el("line", { x1: x(b.p10), x2: x(b.p90), y1: cy + 9, y2: cy + 9, class: "whisk w1" }, g);
      S.el("line", { x1: x(a.p50), x2: x(b.p50), y1: cy, y2: cy, class: "bell fade" }, g);
      var fa = S.el("circle", { cx: x(a.p50), cy: cy, r: 7, class: "m0 ring2" }, g);
      var hb = S.el("circle", { cx: x(b.p50), cy: cy, r: 7, class: "m1 ring2 slide" }, g);
      hb.style.setProperty("--dx", (x(a.p50) - x(b.p50)).toFixed(1) + "px");
      S.delay(hb, 200 + i * 120);
      rd(fa, r[1] + ", fresh start: median " + f.k(a.p50) + " (p10 " + f.k(a.p10) + ", p90 " + f.k(a.p90) + ")");
      rd(hb, r[1] + ", from a handoff: median " + f.k(b.p50) + " (p10 " + f.k(b.p10) + ", p90 " + f.k(b.p90) + ")");
    });
    for (var v = 0; v <= top; v += 50000) {
      S.el("line", { x1: x(v), x2: x(v), y1: 24, y2: H - 18, class: "tick" }, s);
      S.el("text", { x: x(v), y: H - 4, class: v ? "axis mid" : "axis" }, s, v ? f.k(v) : "0 tokens");
    }
    var lg = S.h("ul", "legend", host), li = S.h("li", null, lg);
    S.h("i", "sw dotk m0", li);
    S.h("span", null, li, "fresh start: " + f.int(F[last].n) + " sessions, first 3 requests " + S.usd(F.usd_first_3.p50, host) + " median");
    li = S.h("li", null, lg);
    S.h("i", "sw dotk m1", li);
    S.h("span", null, li, "boots from a handoff: " + f.int(Hd[last].n) + " sessions, first 3 requests " + S.usd(Hd.usd_first_3.p50, host) + " median");
  };

  C.rotation = function (d, host, W) {
    var start = d.context_growth[1] ? d.context_growth[1].p50 : 31000, nudge = 150000, cap = 200000;
    var wrap = S.h("div", "life", host);
    if (S.still) {
      [[nudge, "the old body at the nudge"], [start, "a new body, booted from the handoff"]].forEach(function (p, i) {
        var c = S.h("div", "life-cell", wrap), b = S.h("div", "body", c), fill = S.h("i", "fill", b);
        fill.style.setProperty("--k", (p[0] / cap).toFixed(3));
        S.h("p", "ctx", c, f.k(p[0]) + ": " + p[1]);
        if (!i) S.h("p", "arrow", wrap, "handoff →");
      });
    } else {
      var cell = S.h("div", "life-cell", wrap), body = S.h("div", "body", cell), fill = S.h("i", "fill", body);
      var ctx = S.h("p", "ctx", cell), btn = S.h("button", "replay", wrap, "Replay");
      btn.type = "button";
      ctx.setAttribute("aria-live", "off");
      var timers = [];
      var run = function () {
        timers.forEach(window.clearTimeout);
        body.className = "body";
        fill.style.setProperty("--k", (start / cap).toFixed(3));
        ctx.textContent = f.k(start) + " tokens: a new session boots";
        timers = [
          window.setTimeout(function () {
            fill.style.setProperty("--k", (nudge / cap).toFixed(3));
            S.count(ctx, nudge, function (v) { return f.k(Math.max(start, v)) + " tokens of context"; });
          }, 300),
          window.setTimeout(function () { body.className = "body die"; ctx.textContent = f.k(nudge) + ": the nudge. Handoff written, session stops"; }, 1900),
          window.setTimeout(function () {
            fill.style.setProperty("--k", (start / cap).toFixed(3));
            body.className = "body born";
            ctx.textContent = f.k(start) + " tokens: a new body picks up the handoff";
          }, 3100)
        ];
      };
      btn.addEventListener("click", run);
      run();
    }
    var R = d.rotation, chips = S.h("ul", "chips", host);
    [[R.sessions_ending_150_210k, "sessions ended between 150k and 210k"], [R.sessions_over_200k, "sessions went past 200k"],
      [R.sessions_rotated_or_compacted, "sessions were compacted mid-file"]].forEach(function (c) {
      var li = S.h("li", null, chips);
      S.h("b", null, li, f.int(c[0]));
      S.h("span", null, li, c[1]);
    });
    var q = d.sessions.final_context, top = 260000, Hs = 74, L = 4;
    var x = function (v) { return L + Math.min(v, top) / top * (W - L - 70); };
    var s = S.svg(host, W, Hs, "Final context per session: p10 " + f.k(q.p10) + ", median " + f.k(q.p50) + ", p90 " + f.k(q.p90) + ", max " + f.k(q.max));
    S.el("line", { x1: L, x2: x(top), y1: 30, y2: 30, class: "axisline" }, s);
    S.el("rect", { x: x(q.p10), y: 24, width: x(q.p90) - x(q.p10), height: 12, rx: 2, class: "m1 soft" }, s);
    [[nudge, "nudge"], [cap, "ceiling"]].forEach(function (r) {
      S.el("line", { x1: x(r[0]), x2: x(r[0]), y1: 14, y2: 44, class: "rule" }, s);
      S.el("text", { x: x(r[0]), y: 10, class: "rule-t mid" }, s, r[1]);
    });
    [["p10", q.p10], ["median", q.p50], ["p90", q.p90]].forEach(function (p, i) {
      S.el("circle", { cx: x(p[1]), cy: 30, r: 5, class: i === 1 ? "m0 ring2" : "m6 ring2" }, s);
      S.el("text", { x: x(p[1]), y: 60 + (i === 1 ? 12 : 0), class: "axis mid" }, s, p[0] + " " + f.k(p[1]));
    });
    S.el("text", { x: W, y: 34, class: "axis end" }, s, "max " + f.k(q.max) + " →");
  };
}());
