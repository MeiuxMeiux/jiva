// /stats charts C: the hive at work (05: hour ring, calendar, boxes, tokens/$ toggle), who spends (06: stacked bars).
"use strict";
(function () {
  var S = window.JStats, C = S.charts, f = S.f;

  C.fleet = function (d, host, W) {
    var bar = S.h("div", "toggle", host), parts = S.h("div", "fleet", host), mode = "tok";
    bar.setAttribute("role", "group");
    bar.setAttribute("aria-label", "Measure");
    var btns = [["tok", "tokens"], ["usd", "API-equivalent $"]].map(function (b) {
      var e = S.h("button", null, bar, b[1]);
      e.type = "button";
      e.setAttribute("aria-pressed", String(b[0] === mode));
      e.addEventListener("click", function () {
        mode = b[0];
        btns.forEach(function (o) { o.setAttribute("aria-pressed", String(o === e)); });
        paint(false);
      });
      return e;
    });
    var val = function (r) { return mode === "tok" ? S.tok(r) : r.usd; };
    var show = function (v) { return mode === "tok" ? f.compact(v) + " tokens" : S.usd(v, host); };
    function paint(first) {
      parts.textContent = "";
      hours(d.by_hour_utc, parts, Math.min(W, 340), val, show);
      days(d, parts, val, show);
      boxes(d.by_box, parts, val, show);
      if (!first) host.classList.add("go");
    }
    paint(true);
  };

  function wedge(cx, cy, r0, r1, a0, a1) {
    var p = function (r, a) { return (cx + r * Math.cos(a)).toFixed(1) + " " + (cy + r * Math.sin(a)).toFixed(1); };
    return "M" + p(r0, a0) + "L" + p(r1, a0) + "A" + r1 + " " + r1 + " 0 0 1 " + p(r1, a1) + "L" + p(r0, a1) + "A" + r0 + " " + r0 + " 0 0 0 " + p(r0, a0) + "Z";
  }

  function hours(H, host, size, val, show) {
    var keys = Object.keys(H).map(Number).sort(function (a, b) { return a - b; }), max = 0, best = keys[0];
    keys.forEach(function (k) { if (val(H[k]) > max) { max = val(H[k]); best = k; } });
    var fig = S.h("figure", "hours", host), c = size / 2, r0 = 50, r1 = c - 24;
    var s = S.svg(fig, size, size, "Activity by hour of day, UTC; busiest hour " + best + ":00 UTC", "Ring of 24 wedges; wedge length is proportional to the selected measure.");
    var rd = S.readout(fig);
    keys.forEach(function (k, i) {
      var a0 = (k / 24) * 2 * Math.PI - Math.PI / 2 + 0.02, a1 = ((k + 1) / 24) * 2 * Math.PI - Math.PI / 2 - 0.02;
      var g = S.el("path", { d: wedge(c, c, r0, r0 + (r1 - r0) * val(H[k]) / max, a0, a1), class: "wedge " + (k === best ? "m0" : "m1") }, s);
      g.style.setProperty("--o", c + "px " + c + "px");
      S.delay(g, i * 20);
      rd(g, String(k).padStart(2, "0") + ":00 UTC: " + show(val(H[k])) + ", " + f.int(H[k].requests) + " requests");
    });
    [0, 6, 12, 18].forEach(function (k) {
      var a = (k / 24) * 2 * Math.PI - Math.PI / 2;
      S.el("text", { x: c + (r1 + 13) * Math.cos(a), y: c + (r1 + 13) * Math.sin(a) + 4, class: "axis mid" }, s, String(k));
    });
    S.el("text", { x: c, y: c - 2, class: "ring-mid" }, s, String(best).padStart(2, "0") + ":00");
    S.el("text", { x: c, y: c + 16, class: "axis mid" }, s, "peak UTC");
    S.h("figcaption", null, fig, "Hours are UTC. Wedge length: the measure picked above.");
  }

  function days(d, host, val, show) {
    var D = d.by_day, keys = Object.keys(D).sort(), max = 0;
    keys.forEach(function (k) { max = Math.max(max, val(D[k])); });
    var fig = S.h("figure", "cal", host), grid = S.h("div", "cal-grid", fig);
    var lead = (new Date(keys[0] + "T00:00:00Z").getUTCDay() + 6) % 7;  // Monday first
    for (var i = 0; i < lead; i++) S.h("span", "pad", grid);
    var rd = S.readout(fig);
    keys.forEach(function (k, i) {
      var r = D[k], c = S.h("span", "day" + (val(r) ? "" : " quiet"), grid), k01 = max ? val(r) / max : 0;
      S.h("b", null, c, String(r.sessions_started));
      S.h("i", null, c).style.setProperty("--k", k01.toFixed(3));
      S.delay(c, i * 15);
      rd(c, k + ": " + show(val(r)) + ", " + f.int(r.sessions_started) + " sessions started");
    });
    S.h("figcaption", null, fig, "One square per UTC day, Monday first. Number: sessions started. Bar: the measure.");
  }

  function boxes(B, host, val, show) {
    var keys = Object.keys(B).sort(), maxV = 0, maxS = 0, fig = S.h("figure", "boxes", host);
    keys.forEach(function (k) { maxV = Math.max(maxV, val(B[k])); maxS = Math.max(maxS, B[k].sessions); });
    keys.forEach(function (k, i) {
      var row = S.h("div", "box-row", fig);
      S.h("b", null, row, k);
      [[B[k].sessions / maxS, f.int(B[k].sessions) + " sessions", "m2"], [val(B[k]) / maxV, show(val(B[k])), "m1"]].forEach(function (m) {
        var line = S.h("span", "hbar", row), i2 = S.h("i", m[2], line);
        i2.style.setProperty("--k", m[0].toFixed(3));
        S.delay(i2, i * 80);
        S.h("em", null, line, m[1]);
      });
    });
  }

  var ROLE_GLOSS = { worker: "ships one task card", queen: "splits work into cards", loop: "short timed checks", desk: "the one you talk to",
    boss: "runs a project's queue", other: "plain sessions, no role", subagent: "spawned by another session" };

  function stack(host, title, rows, total, note) {
    var fig = S.h("figure", "stack", host);
    S.h("figcaption", "stack-t", fig, title);
    var bar = S.h("div", "sbar", fig), list = S.h("ul", "legend", fig);
    rows.forEach(function (r, i) {
      var share = r[1] / total, seg = S.h("span", "fade m" + (i % 7), bar);
      seg.style.setProperty("--w", (share * 100).toFixed(2) + "%");
      S.delay(seg, i * 60);
      seg.title = r[0] + ": " + f.pct(share);
      if (share >= 0.08) S.h("b", i % 7 > 2 ? "lt" : null, seg, f.pct0(share));
      var li = S.h("li", null, list);
      S.h("i", "sw m" + (i % 7), li);
      S.h("span", null, li, r[0] + " " + f.pct(share) + (note && note[r[0]] ? ": " + note[r[0]] : ""));
    });
  }

  C.roles = function (d, host) {
    var total = d.totals.usd, by = function (o) {
      return Object.keys(o).map(function (k) { return [k, o[k].usd]; }).sort(function (a, b) { return b[1] - a[1]; });
    };
    S.h("p", "stack-total", host, "Share of " + S.usd(total, host) + " API-equivalent spend.");
    stack(host, "By role", by(d.by_role), total, ROLE_GLOSS);
    var sub = by(d.by_subagent_type).map(function (r) { return ["subagent: " + r[0], r[1]]; });
    stack(host, "Main sessions and subagents by type", [["main sessions", d.split.main.usd]].concat(sub), total);
    stack(host, "By model", by(d.by_model).map(function (r) { return [S.model(r[0]), r[1]]; }), total);
  };
}());
