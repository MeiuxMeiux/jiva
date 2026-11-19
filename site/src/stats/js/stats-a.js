// /stats charts A: hero count-up + cache ring (00), token river + cost share (01), context growth fan (02).
"use strict";
(function () {
  var S = window.JStats, C = S.charts, f = S.f;

  C.ring = function (d, host) {
    var hit = d.totals.cache_hit, size = 240, r = 100, len = 2 * Math.PI * r;
    host.closest(".band").querySelectorAll(".tiles [data-stat]").forEach(function (span) {
      var v = S.get(d, span.getAttribute("data-stat")), fmt = f[span.getAttribute("data-f")] || f.num;
      if (typeof v === "number") S.count(span, v, fmt);
    });
    var s = S.svg(host, size, size, "Cache hit: " + f.pct(hit) + " of input tokens were read from cache",
      "Donut: " + f.pct(hit) + " cache reads, " + f.pct(1 - hit) + " fresh input and cache writes.");
    s.classList.add("ring");
    S.el("circle", { cx: 120, cy: 120, r: r, class: "ring-rest" }, s);
    var arc = S.el("circle", { cx: 120, cy: 120, r: r, class: "ring-arc", "stroke-dasharray": len.toFixed(1),
      transform: "rotate(-90 120 120)" }, s);
    arc.style.setProperty("--off", (len * (1 - hit)).toFixed(1) + "px");
    arc.style.setProperty("--len", len.toFixed(1) + "px");
    S.el("text", { x: 120, y: 120, class: "ring-big" }, s, f.pct(hit));
    S.el("text", { x: 120, y: 146, class: "ring-small" }, s, "cache hit");
  };

  var CLASSES = [["cache_read", "cache read", "m1"], ["cache_write", "cache write", "m0"],
    ["output", "output", "m2"], ["input", "fresh input", "m6"]];

  C.river = function (d, host, W) {
    var t = d.totals, top = Math.pow(10, Math.ceil(Math.log(t.cache_read) / Math.LN10)), lo = 1e5;
    var x = function (v) { return Math.max(2, (Math.log(Math.max(v, lo) / lo) / Math.log(top / lo)) * W); };
    var H = CLASSES.length * 56 + 40, all = S.tok(t);
    var s = S.svg(host, W, H, "Token classes on a log scale: cache read " + f.compact(t.cache_read) + ", cache write " +
      f.compact(t.cache_write) + ", output " + f.compact(t.output) + ", fresh input " + f.compact(t.input));
    var rd = S.readout(host);
    CLASSES.forEach(function (c, i) {
      var y = i * 56, g = S.el("g", { class: "row" }, s);
      S.el("text", { x: 0, y: y + 16, class: "lbl" }, g, c[1]);
      S.el("text", { x: W, y: y + 16, class: "val end" }, g, f.compact(t[c[0]]) + " · " + f.pct(t[c[0]] / all));
      S.el("rect", { x: 0, y: y + 24, width: W, height: 14, class: "track" }, g);
      S.delay(S.el("rect", { x: 0, y: y + 24, width: x(t[c[0]]).toFixed(1), height: 14, rx: 2, class: "grow " + c[2] }, g), i * 80);
      rd(g, c[1] + ": " + f.int(t[c[0]]) + " tokens, " + f.pct(t[c[0]] / all) + " of all tokens");
    });
    var ay = CLASSES.length * 56 + 12;
    [1e6, 1e8, 1e10].forEach(function (v) {
      if (v >= top) return;
      S.el("line", { x1: x(v), x2: x(v), y1: 20, y2: ay - 6, class: "tick" }, s);
      S.el("text", { x: x(v), y: ay + 10, class: "axis mid" }, s, v >= 1e9 ? v / 1e9 + "B" : v / 1e6 + "M");
    });
    S.el("text", { x: 0, y: ay + 26, class: "axis" }, s, "log scale: each tick is 100× the one before");
  };

  S.cost = function (d) {  // API-equivalent cost by token class: by_model × pricing.per_million (cache write at 5m rate)
    var out = { cache_read: 0, cache_write: 0, output: 0, input: 0 }, P = d.pricing.per_million;
    Object.keys(d.by_model).forEach(function (m) {
      var r = d.by_model[m], p = P[m];
      if (!p) return;
      out.cache_read += r.cache_read * p.cache_read / 1e6;
      out.cache_write += r.cache_write * p.cache_write_5m / 1e6;
      out.output += r.output * p.output / 1e6;
      out.input += r.input * p.input / 1e6;
    });
    var tiers = d.cache_write_tiers && d.cache_write_tiers.overall;  // schema 2: exact 5m/1h split
    if (tiers) out.cache_write = tiers.usd_5m + tiers.usd_1h;
    out.exact = !!tiers;
    var sum = out.cache_read + out.cache_write + out.output + out.input;
    out.other = Math.max(0, d.totals.usd - sum);
    return out;
  };

  C.cost = function (d, host, W) {
    var c = S.cost(d), total = d.totals.usd, rows = CLASSES.concat([["other", "other (fast mode, rounding)", "m3"]]);
    var s = S.svg(host, W, 40, "API-equivalent cost by token class, " + S.usd(total, host) + " in all");
    var x = 0, rd = S.readout(host), list = S.h("ul", "legend", host);
    rows.forEach(function (r, i) {
      var share = c[r[0]] / total, w = share * W;
      if (w <= 0) return;
      var g = S.el("g", {}, s);
      S.delay(S.el("rect", { x: x.toFixed(1), y: 4, width: Math.max(1, w - 2).toFixed(1), height: 32, class: "fade " + r[2] }, g), i * 80);
      if (w > 64) S.el("text", { x: (x + 8).toFixed(1), y: 25, class: "seg" }, g, f.pct0(share));
      var text = r[1] + (r[0] === "cache_write" && !c.exact ? " (approx.)" : "") + ": " + S.usd(c[r[0]], host) + ", " + f.pct(share) + " of cost";
      rd(g, text);
      var li = S.h("li", null, list);
      S.h("i", "sw " + r[2], li);
      S.h("span", null, li, text);
      x += w;
    });
  };

  C.fan = function (d, host, W) {
    var G = d.context_growth, steps = Object.keys(G).map(Number).sort(function (a, b) { return a - b; });
    var H = Math.max(260, Math.min(380, Math.round(W * 0.56))), L = 46, R = 10, T = 14, B = 80;
    var ymax = Math.ceil(Math.max.apply(null, steps.map(function (k) { return G[k].p90; })) / 1e5) * 1e5;
    var last = steps[steps.length - 1], pw = W - L - R, ph = H - T - B;
    var x = function (k) { return L + (Math.sqrt(k) - 1) / (Math.sqrt(last) - 1) * pw; };
    var y = function (v) { return T + (1 - v / ymax) * ph; };
    var line = function (key) { return steps.map(function (k, i) { return (i ? "L" : "M") + x(k).toFixed(1) + " " + y(G[k][key]).toFixed(1); }).join(""); };
    var band = function (a, b) { return line(b) + steps.slice().reverse().map(function (k) { return "L" + x(k).toFixed(1) + " " + y(G[k][a]).toFixed(1); }).join("") + "Z"; };
    var s = S.svg(host, W, H, "Context per request: median " + f.k(G[steps[0]].p50) + " at request " + steps[0] +
      ", " + f.k(G[100] ? G[100].p50 : G[last].p50) + " at request " + (G[100] ? 100 : last),
      "Fan chart of p10 to p90 context size by request index, square-root x scale.");
    for (var v = 0; v <= ymax; v += 1e5) {
      S.el("line", { x1: L, x2: W - R, y1: y(v), y2: y(v), class: "grid" }, s);
      S.el("text", { x: L - 6, y: y(v) + 4, class: "axis end" }, s, v ? f.k(v) : "0");
    }
    var bands = S.el("g", { class: "wipe" }, s);
    S.el("path", { d: band("p10", "p90"), class: "fan-o" }, bands);
    S.el("path", { d: band("p25", "p75"), class: "fan-i" }, bands);
    [[150000, "nudge 150k", L + 6, "rule-t", 14], [200000, "ceiling 200k", L + 6, "rule-t", -5]].forEach(function (r) {
      S.el("line", { x1: L, x2: W - R, y1: y(r[0]), y2: y(r[0]), class: "rule" }, s);
      S.el("text", { x: r[2], y: y(r[0]) + r[4], class: r[3] }, s, r[1]);
    });
    S.el("path", { d: line("p50"), class: "med draw", pathLength: 1 }, s);
    var rd = S.readout(host), n0 = G[steps[0]].n, by = H - 38;
    var shown = W < 520 ? [1, 10, 50, 100, last] : [1, 5, 10, 20, 50, 100, 150, 200, last];
    steps.forEach(function (k) {
      var g = S.el("g", { class: "pt" }, s), p = G[k];
      S.el("circle", { cx: x(k), cy: y(p.p50), r: 12, class: "hit" }, g);
      S.el("circle", { cx: x(k), cy: y(p.p50), r: 4, class: "dot" }, g);
      rd(g, "request " + k + ": " + f.int(p.n) + " sessions got this far; p10 " + f.k(p.p10) + ", median " + f.k(p.p50) + ", p90 " + f.k(p.p90));
      if (shown.indexOf(k) >= 0) S.el("text", { x: x(k), y: H - B + 18, class: "axis mid" }, s, String(k));
      var bh = Math.max(1, 18 * p.n / n0);
      S.el("rect", { x: x(k) - 3, y: by + 18 - bh, width: 6, height: bh, class: "surv" }, s);
    });
    S.el("text", { x: L, y: H - B + 34, class: "axis" }, s, "request number (square-root scale)");
    S.el("text", { x: L, y: H - 3, class: "axis" }, s, "bars: sessions still running, " + f.int(n0) + " → " + f.int(G[last].n));
  };
}());
