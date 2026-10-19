// phone — tier-2 read-only view. Fetches ./snapshot.json every 15s (no-store); repaints age every 1s; "stale Nm" past
// 60s; missing/broken snapshot → "no snapshot" state (no network needed). textContent only; --slot via setProperty.
"use strict";
let snap = null, pack = null;
const $ = id => document.getElementById(id);
const clean = s => String(s == null ? "" : s).replace(/[^\w .:-]/g, "").slice(0, 24);
const num = n => typeof n === "number" && isFinite(n) ? n : null;
const ago = s => s == null ? "–" : s < 60 ? s + "s" : s < 3600 ? Math.floor(s / 60) + "m" : Math.floor(s / 3600) + "h";
const kfmt = n => n == null ? "–" : n >= 1000 ? Math.round(n / 1000) + "k" : String(n);
const pct = n => n == null ? "–" : n + "%";

function li(cls, initial, color, label, meta) {
  const r = document.createElement("li"), dot = document.createElement("span"), l = document.createElement("span"),
    m = document.createElement("span");
  r.className = "row " + cls; dot.className = "soul"; dot.setAttribute("aria-hidden", "true");
  dot.textContent = initial; if (color) dot.style.setProperty("--slot", color);
  l.className = "label"; l.textContent = label; m.className = "meta"; m.textContent = meta;
  r.append(dot, l, m); return r;
}

// party chip: pack slot portrait (avatars/NN.webp) → NN.svg on error → initial; queen (slot 0)/desk = initial only
function chip(x) {
  const n = clean(x.name), k = num(x.slot), p = pack && k > 0 && Array.isArray(pack.slots) ? pack.slots.find(y => y && y.slot === k) : null;
  const r = document.createElement("li"), av = document.createElement("span"), l = document.createElement("b"), m = document.createElement("span");
  const initial = () => { av.textContent = n.slice(0, 1).toUpperCase() || "?"; };
  const srcs = p ? [p.portrait, p.avatar].filter(v => /^avatars\/\d\d\.(webp|svg)$/.test(v || "")) : [];
  r.className = "chip " + clean(x.status); av.className = "av"; av.setAttribute("aria-hidden", "true");
  if (/^#[0-9a-f]{6}$/i.test(x.color || "")) r.style.setProperty("--slot", x.color);
  if (srcs.length) {
    const img = document.createElement("img"); img.alt = "";
    img.addEventListener("error", () => srcs.length ? (img.src = srcs.shift()) : (img.remove(), initial()));
    img.src = srcs.shift(); av.appendChild(img);
  } else initial();
  l.textContent = p ? clean(p.name) + " · " + n : n; m.className = "meta";
  m.textContent = [clean(x.status), kfmt(num(x.tok))].filter(Boolean).join(" · ");
  r.append(av, l, m); return r;
}

function tick() {
  const empty = !snap, age = snap ? Math.max(0, Math.floor(Date.now() / 1000) - (num(snap.ts) || 0)) : null;
  $("empty").hidden = !empty; document.body.classList.toggle("none", empty);
  document.body.classList.toggle("stale", !empty && age > 60);
  $("age").textContent = empty ? "no snapshot" : age > 60 ? "stale " + Math.floor(age / 60) + "m" : "updated " + age + "s ago";
}

function render(s) {
  const ss = Array.isArray(s.sessions) ? s.sessions : [], fl = Array.isArray(s.flags) ? s.flags : [],
    as = Array.isArray(s.asks) ? s.asks : [], q = s.quota || {}, le = s.lease || {};
  $("live").textContent = num(s.live) ?? ss.length; $("flags").textContent = fl.length; $("asks").textContent = as.length;
  $("q5h").textContent = pct(num(q.q5h)); $("q7d").textContent = pct(num(q.q7d)); $("lease").textContent = clean(le.state) || "–";
  $("flags").parentElement.classList.toggle("hot", fl.length > 0); $("asks").parentElement.classList.toggle("warm", as.length > 0);
  $("lease").parentElement.classList.toggle("hot", le.state === "stale");
  const color = c => /^#[0-9a-f]{6}$/i.test(c || "") ? c : null;
  $("party").replaceChildren(...ss.map(chip));
  $("sessions").replaceChildren(...ss.map(x => {
    const n = clean(x.name);
    return li(clean(x.status), /^w\d+$/.test(n) ? n.slice(1) : n.slice(0, 1).toUpperCase() || "?", color(x.color), n,
      [clean(x.status), clean(x.verb), kfmt(num(x.tok))].filter(Boolean).join(" · "));
  }));
  const rows = [...fl.map(f => li("flag", "!", null, clean(f.name), "flag · " + ago(num(f.age)))),
    ...as.map(a => li("ask", "?", null, clean(a.class) + " " + clean(a.id), "ask · " + ago(num(a.age))))];
  $("alerts").replaceChildren(...(rows.length ? rows : [li("calm", "·", null, "all clear", "")]));
}

function load() {
  fetch("snapshot.json", { cache: "no-store" }).then(r => r.ok ? r.json() : null)
    .then(s => { snap = s && typeof s === "object" ? s : null; if (snap) render(snap); tick(); })
    .catch(() => tick());   // offline: keep the last snapshot, the age line turns "stale Nm"
}
fetch("pack.json").then(r => r.ok ? r.json() : null).then(p => { pack = p; if (snap) render(snap); }).catch(() => {});
load(); setInterval(load, 15000); setInterval(tick, 1000);
