"use strict";
// dash-history — the History panel (loaded after dash.js; uses $, num, k, soul, last, pack from dash.js and el, icon, txt,
// SVG from dash-panels.js). /history/summary → two sparklines (fleet tok, quota 5h: two charts, never a dual axis) + a
// timeline strip (one lane per session; life/ship/trip/ask = cyan bar/green dot/pink triangle/white diamond, <title>
// tooltips); /history pages of 100 via ?before=<last ts> as the list bottom scrolls into view, filtered by kind +
// session chips (aria-pressed toggles; none pressed = all). Text only (textContent), never markup.
(() => {
  const PAGE = 100, KINDS = ["claim", "report", "ship", "handoff", "ask", "answer", "expire", "nudge", "life", "heal", "park", "trip", "quota", "lease", "tok"];
  const LANE = { life: "cy", ship: "gr", trip: "pk", ask: "tx" }, W = 1000, LW = 120, RH = 24;
  const st = { before: null, done: false, busy: false, gen: 0, kinds: new Set(), names: new Set(), sum: null };
  const list = $("hist-list"), sentinel = el("li", "loading…", "more");
  const get = async u => { const r = await fetch(u, { cache: "no-store" }); if (!r.ok) throw new Error(r.status); return r.json(); };
  const sv = (tag, at, title) => {
    const e = document.createElementNS(SVG, tag);
    for (const a in at) e.setAttribute(a, at[a]);
    if (title) { const t = document.createElementNS(SVG, "title"); t.textContent = title; e.appendChild(t); }
    return e;
  };
  const tstr = (ts, full) => { const d = new Date(ts * 1000), p = n => String(n).padStart(2, "0");
    return (full ? p(d.getMonth() + 1) + "-" + p(d.getDate()) + " " : "") + p(d.getHours()) + ":" + p(d.getMinutes()) + (full ? ":" + p(d.getSeconds()) : ""); };
  const nm = v => typeof v === "string" ? v.replace(/[^\w.-]/g, "").slice(0, 32) : "";
  const who = r => (typeof r.name === "string" && r.kind !== "ask" && r.kind !== "ship" ? nm(r.name) : nm(r.who)) || "?";

  // soul label: soul() from dash.js (state.json sessions[].soul binding, else wN → slot) → "Ash · w1" + portrait (svg fallback)
  function label(name) {
    const sl = /^(w\d+|boss)$/.test(name) || (last && Array.isArray(last.sessions) && last.sessions.some(y => y && y.name === name)) ? soul(name) : null;
    return { sl, text: sl && sl.name && name !== "boss" ? sl.name + " · " + name : name };
  }
  function chip(name) {
    const l = label(name), span = el("span", null, "soul"), av = el("span", null, "av");
    if (l.sl) span.style.setProperty("--slot", l.sl.color);
    face(av, l.sl, name);
    span.append(av, el("span", l.text, "sn")); return span;
  }

  function detail(r) {
    const n = v => num(v) === null ? "–" : String(v), s = v => txt(v, 80);
    switch (r.kind) {
      case "claim": return "claimed " + n(r.n) + " path(s)";       case "report": return s(r.st);
      case "ship": return "shipped " + s(r.sha);                  case "handoff": return n(r.lines) + " lines";
      case "ask": case "expire": return s(r.class) + " · " + s(r.id); case "answer": return s(r.id) + " by " + s(r.by);
      case "nudge": return s(r.name) + " at " + k(r.tok) + " tok";  case "heal": return s(r.name) + " respawned";
      case "life": case "park": return s(r.name) + " · " + s(r.why) + (num(r.tok) === null ? "" : " · " + k(r.tok) + " tok");
      case "trip": return s(r.name) + " · " + s(r.trip);           case "lease": return s(r.st) + (num(r.age) === null ? "" : " · " + r.age + "s");
      case "quota": return s(r.st) + " · 5h " + n(r.q5h) + "% · 7d " + n(r.q7d) + "%";
      case "tok": return "fleet " + k(r.tok) + (num(r.q5h) === null ? "" : " · 5h " + r.q5h + "%");
    }
    return "";
  }
  function row(r) {
    const li = el("li");
    li.append(el("span", tstr(r.ts, true), "a"), el("span", r.kind, "badge k-" + r.kind), chip(who(r)), el("span", detail(r), "t"));
    return li;
  }

  async function more() {
    if (st.busy || st.done) return;
    st.busy = true; const g = st.gen; let ok = false;
    const q = new URLSearchParams({ n: PAGE });
    if (st.before !== null) q.set("before", st.before);
    if (st.kinds.size) q.set("kind", [...st.kinds].join(","));
    if (st.names.size) q.set("name", [...st.names].join(","));
    try {
      const rows = (await get("history?" + q)).filter(r => r && num(r.ts) !== null && KINDS.includes(r.kind));
      if (g !== st.gen) return;
      list.insertBefore(frag(rows), sentinel); ok = true;
      st.done = rows.length < PAGE; if (rows.length) st.before = rows[rows.length - 1].ts;
      sentinel.textContent = st.done ? (list.children.length > 1 ? "start of history" : "no events match") : "loading…";
    } catch (e) { if (g === st.gen) sentinel.textContent = "history fetch failed — scroll to retry"; }
    finally {  // a short page can leave the sentinel in view, where the observer will not fire again
      if (g === st.gen) { st.busy = false; if (ok && !st.done && sentinel.getBoundingClientRect().top < list.getBoundingClientRect().bottom) setTimeout(more); }
    }
  }
  const frag = rows => { const f = document.createDocumentFragment(); rows.forEach(r => f.appendChild(row(r))); return f; };
  function reset() { st.gen++; st.before = null; st.done = false; st.busy = false; list.replaceChildren(sentinel); more(); }
  new IntersectionObserver(es => { if (es.some(e => e.isIntersecting)) more(); }, { root: list }).observe(sentinel);

  function chips(box, items, set, text) {
    box.replaceChildren(...items.map(v => {
      const b = el("button", null, "fchip"); b.type = "button"; b.setAttribute("aria-pressed", String(set.has(v)));
      b.append(text(v)); b.addEventListener("click", () => { set.has(v) ? set.delete(v) : set.add(v); b.setAttribute("aria-pressed", String(set.has(v))); reset(); });
      return b;
    }));
  }
  function spark(svg, pts, max, fmt, what) {
    const H = 48, n = pts.length, x = i => n < 2 ? W / 2 : i * W / (n - 1), y = v => H - 3 - (H - 6) * Math.min(1, v / (max || 1));
    svg.setAttribute("viewBox", "0 0 " + W + " " + H); svg.setAttribute("preserveAspectRatio", "none");
    const ok = pts.map((p, i) => [i, p[1]]).filter(p => num(p[1]) !== null);
    const kids = [sv("line", { x1: 0, x2: W, y1: H - 3, y2: H - 3, class: "base" })];
    if (ok.length) kids.push(sv("polyline", { points: ok.map(p => x(p[0]) + "," + y(p[1])).join(" "), class: "sl" }));
    pts.forEach((p, i) => num(p[1]) !== null && kids.push(sv("rect", { x: x(i) - W / Math.max(n, 2) / 2, y: 0, width: W / Math.max(n, 2), height: H, class: "hit" },
      tstr(p[0], true) + " · " + what + " " + fmt(p[1]))));
    svg.replaceChildren(...kids);
    svg.setAttribute("aria-label", what + ": " + (ok.length ? "latest " + fmt(ok[ok.length - 1][1]) + ", " + ok.length + " points" : "no data"));
  }
  function timeline(s) {
    const svg = $("hist-tl"), names = Object.keys(s.sessions).sort((a, b) => (a === "boss" ? -1 : b === "boss" ? 1 : a.localeCompare(b, "en", { numeric: true })));
    const H = names.length * RH + 22, bw = (W - LW) / Math.max(1, s.buckets), kids = [];
    svg.setAttribute("viewBox", "0 0 " + W + " " + H);
    names.forEach((n, i) => {
      const y = i * RH + RH / 2, x = s.sessions[n], l = label(n), lane = x.lane && typeof x.lane === "object" ? x.lane : {};
      kids.push(sv("line", { x1: LW, x2: W, y1: y, y2: y, class: "lane" }), Object.assign(sv("text", { x: 0, y: y + 4, class: "ll" }), { textContent: txt(l.text, 20) }));
      for (const b in lane) for (const kd in LANE) {
        const c = num(lane[b][kd]); if (!c) continue;
        const cx = LW + (+b + .5) * bw, t = tstr(s.t0 + b * s.width, true) + " · " + n + " · " + c + " " + kd + (c > 1 ? "s" : "");
        const at = kd === "life" ? ["rect", { x: cx - 1.5, y: y - 9, width: 3, height: 18 }] : kd === "ship" ? ["circle", { cx, cy: y, r: 4.5 }]
          : kd === "trip" ? ["path", { d: "M" + cx + " " + (y - 6) + "l5.5 9h-11z" }] : ["path", { d: "M" + cx + " " + (y - 5) + "l4.5 5-4.5 5-4.5-5z" }];
        kids.push(sv(at[0], Object.assign(at[1], { class: "m " + LANE[kd] }), t));
      }
    });
    const ax = H - 6;
    if (s.buckets) kids.push(Object.assign(sv("text", { x: LW, y: ax, class: "ax" }), { textContent: tstr(s.t0, true) }),
      Object.assign(sv("text", { x: W, y: ax, class: "ax end" }), { textContent: tstr(s.t1, true) }));
    svg.replaceChildren(...kids);
    svg.setAttribute("aria-label", "timeline of lives, ships, trips and asks for " + names.length + " sessions");
  }
  async function summary() {
    try {
      const s = await get("history/summary");
      if (!s || typeof s.sessions !== "object" || !Array.isArray(s.tok)) throw new Error("shape");
      const tot = Object.values(s.counts || {}).reduce((a, v) => a + (num(v) ?? 0), 0), first = !st.sum;
      const grew = st.sum && tot !== st.sumTot; st.sum = s; st.sumTot = tot;
      $("hist-sum").textContent = tot + " events · " + Object.keys(s.sessions).length + " sessions";
      spark($("hist-tok"), s.tok.map(p => [p[0], p[1]]), Math.max(...s.tok.map(p => num(p[1]) ?? 0)), k, "fleet tokens");
      spark($("hist-q"), s.tok.map(p => [p[0], p[2]]), 100, v => v + "%", "quota 5h");
      timeline(s);
      if (first) chips($("hist-kinds"), KINDS, st.kinds, v => v);
      chips($("hist-names"), Object.keys(s.sessions).sort(), st.names, chip);
      if (first || grew && list.scrollTop === 0) reset();
    } catch (e) { $("hist-sum").textContent = "history fetch failed"; }
  }
  summary(); setInterval(summary, 30000);
})();
