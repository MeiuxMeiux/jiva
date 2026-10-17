"use strict";
// dash-panels — side panels for dash.js (loaded first; shares its globals: $, num, enumv, side). Text only
// (textContent), never markup; empty panels collapse to the heading.
// /flags /asks /lease from dash.sh
const ago = s => num(s) === null || s < 0 ? "–" : s < 60 ? s + "s" : s < 3600 ? Math.floor(s / 60) + "m" : Math.floor(s / 3600) + "h";
const txt = (v, n) => typeof v === "string" ? v.slice(0, n) : "";
function el(tag, text, cls) {
  const e = document.createElement(tag);
  if (text != null) e.textContent = text;
  if (cls) e.className = cls;
  return e;
}
const SVG = "http://www.w3.org/2000/svg";
function icon(name) {  // <svg class="i"><use href="#i-name"> from the sprite in dash.html; decorative, label sits beside it
  const s = document.createElementNS(SVG, "svg"), u = document.createElementNS(SVG, "use");
  s.setAttribute("class", "i"); s.setAttribute("aria-hidden", "true"); u.setAttribute("href", "#i-" + name);
  s.appendChild(u); return s;
}
function panel(id, items, summary, cls) {
  const sec = $(id), sm = sec.querySelector("h2 small");
  sm.textContent = summary; sm.className = cls || "";
  sec.classList.toggle("empty", items.length === 0);
  sec.querySelector("ul").replaceChildren(...items);
}
function renderSide() {
  const fl = Array.isArray(side.flags) ? side.flags : [], as = Array.isArray(side.asks) ? side.asks : [];
  panel("p-flags", fl.map(x => {
    const li = el("li"), n = txt(x.name, 64);
    li.append(el("b", n), el("span", ago(x.age), "a"), el("span", txt(x.last, 120), "t"), el("code", "rm .jiva/flags/" + n));
    return li;
  }), fl.length ? fl.length + " raised" : "none");
  panel("p-asks", as.map(x => {
    const li = el("li", null, x.protected ? "prot" : ""), c = enumv(x.class) || "decision";
    li.append(el("span", x.protected ? c + " · protected" : c, x.protected ? "badge bad" : "badge"),
      el("span", txt(x.text, 200), "t"), el("span", ago(x.age), "a"), el("code", txt(x.id, 12)));
    return li;
  }), as.length ? as.length + " open" : "none");
  const ls = side.lease && ["fresh", "stale", "none"].includes(side.lease.state) ? side.lease.state : "unknown";
  panel("p-lease", [], ls + (num(side.lease && side.lease.age) === null ? "" : " · " + ago(side.lease.age)),
    "badge " + (ls === "fresh" ? "okb" : ls === "stale" ? "bad" : ""));
}

// "doing" = the session's last board line (/board); "quiet" is a word, not a colour (tok grew >40k since it)
function doing(name) {
  const b = side.board || {}, l = (Array.isArray(b.last) ? b.last : []).find(y => y && y.name === name);
  const q = Array.isArray(b.quiet) && b.quiet.includes(name) ? "quiet · " : "";
  return q + (l ? ago(l.age) + " ago " + enumv(l.verb) + " " + txt(l.text, 160) : "(no report yet)");
}
function renderBoard() {
  const tl = side.board && Array.isArray(side.board.tail) ? side.board.tail.slice().reverse() : [];
  panel("p-board", tl.map(x => {
    const li = el("li"); li.append(el("span", txt(x.ts, 5), "a"), el("b", enumv(x.name)), el("span", enumv(x.verb), "badge"),
      el("span", txt(x.text, 200), "t")); return li;
  }), tl.length ? "last " + tl.length + ", newest first" : "none");
}


// /alerts = notify.log newest first {ts, age, text}; age grows client-side between polls via ts
const ALERT_FRESH = 600, alertList = () => Array.isArray(side.alerts) ? side.alerts.filter(x => x && num(x.ts) !== null) : [];
const alertAge = x => Math.max(0, Math.floor(Date.now() / 1000 - x.ts));
function renderAlerts() {
  const al = alertList();
  panel("p-alerts", al.map(x => {
    const li = el("li"); li.append(el("span", ago(alertAge(x)) + " ago", "a"), el("span", "·", "a"), el("span", txt(x.text, 200), "t"));
    return li;
  }), al.length ? "last " + al.length + ", newest first" : "none");
}
function freshAlert() {  // newest alert text if younger than 10 min, else ""
  const x = alertList()[0];
  return x && alertAge(x) < ALERT_FRESH ? txt(x.text, 80) || "(no text)" : "";
}
// party strip: one chip per live body (state.json sessions[]) — portrait, "Ash · w1", status, tok; boss/desk = initial
function party(ss) {
  $("party").replaceChildren(...ss.map(x => {
    const name = enumv(x.name), sl = soul(name), li = el("li", null, "pchip"), av = el("span", null, "av");
    const st = enumv(x.status), w = x.waiting != null;
    if (sl) li.style.setProperty("--slot", sl.color);
    face(av, sl, name);
    li.append(av, el("b", sl && sl.name && name !== "boss" ? sl.name + " · " + name : name),
      el("span", w ? "waiting" : st || "–", w ? "wait" : st === "busy" ? "busy" : "idle"), el("span", k(x.tok), "tk"));
    return li;
  }));
}
