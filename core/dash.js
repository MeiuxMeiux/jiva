"use strict";
const STALE = 30, $ = id => document.getElementById(id);
let last = null, failed = false, pack = null, side = { flags: [], asks: [], lease: null, board: null, alerts: [] }, sideFailed = false;
const num = v => (typeof v === "number" && isFinite(v)) ? v : null;
const k = v => num(v) === null ? "–" : v >= 1e6 ? (v / 1e6).toFixed(2) + "M" : v >= 1e3 ? Math.floor(v / 1e3) + "k" : String(v);
const usd = v => num(v) === null ? "–" : "$" + v.toFixed(2);
const pct = v => num(v) === null ? "–" : Math.round(v) + "%";
const hm = s => { if (num(s) === null || s < 0) return "–"; const m = Math.floor(s / 60); return Math.floor(m / 60) + ":" + String(m % 60).padStart(2, "0"); };
const enumv = v => typeof v === "string" ? v.replace(/[^\w .:-]/g, "").slice(0, 24) : "";

function cell(tr, text, cls) {
  const td = document.createElement("td");
  td.textContent = text;
  if (cls) td.className = cls;
  tr.appendChild(td);
}

// soul: state.json sessions[].soul {name,slot,color} (souls.json binding) first, else wN → pack slot N, boss → slot 0.
// portrait = pack slot `portrait` (avatars/NN.webp); avatar = NN.svg fallback. Boss/desk get no portrait (initial only).
const packslot = n => pack && Array.isArray(pack.slots) ? pack.slots.find(y => y && y.slot === n) : null;
function soul(name) {
  if (!pack) return null;
  const x = last && Array.isArray(last.sessions) ? last.sessions.find(y => y && y.name === name) : null, b = x && x.soul;
  const m = /^w(\d+)$/.exec(name), n = b && num(b.slot) !== null ? b.slot : name === "boss" ? 0 : m ? +m[1] : -1;
  const p = n === 0 ? pack.boss : packslot(n), color = b && /^#[0-9a-f]{6}$/i.test(b.color || "") ? b.color : p && p.color;
  if (!p || !/^#[0-9a-f]{6}$/i.test(color || "")) return null;
  const nm = b && typeof b.name === "string" ? b.name.replace(/[^\w .'-]/g, "").slice(0, 24) : txt(p.name, 24);
  return { color, name: nm, avatar: /^avatars\/\d\d\.svg$/.test(p.avatar || "") ? p.avatar : null,
    portrait: n > 0 && /^avatars\/\d\d\.webp$/.test(p.portrait || "") ? p.portrait : null };
}
// fill an .av box: portrait → svg avatar on error → coloured initial; never a broken image
function face(av, sl, name) {
  const initial = () => { const b = document.createElement("b"); b.textContent = (name[0] || "?").toUpperCase(); av.replaceChildren(b); };
  const srcs = sl ? [sl.portrait, sl.avatar].filter(Boolean) : [];
  if (!srcs.length) return initial();
  const img = document.createElement("img"); img.alt = "";
  img.addEventListener("error", () => srcs.length ? (img.src = srcs.shift()) : initial());
  img.src = srcs.shift(); av.replaceChildren(img);
}
// avatar framed in the slot colour (CSS custom property --slot; no inline style attrs under the CSP)
function namecell(tr, name) {
  const td = document.createElement("td"), sl = soul(name), span = document.createElement("span"), av = document.createElement("span");
  span.className = "soul"; av.className = "av";
  if (sl) span.style.setProperty("--slot", sl.color);
  face(av, sl, name);
  span.append(av, document.createTextNode(name));
  td.appendChild(span); tr.appendChild(td);
}
function statuscell(tr, text, cls) {
  const td = document.createElement("td"), st = document.createElement("span");
  st.className = "st"; st.append(icon(cls === "wait" ? "wait" : cls === "busy" ? "busy" : "idle"), document.createTextNode(text || "–"));
  td.className = cls; td.appendChild(st); tr.appendChild(td);
}

function render(s) {
  const ss = Array.isArray(s.sessions) ? s.sessions : [];
  $("live").textContent = num(s.live) ?? "–";
  $("flags").textContent = num(s.flags) ?? "–"; $("asks").textContent = num(s.asks) ?? "–";
  $("tok").textContent = k(s.tok);
  $("usd").textContent = usd(ss.reduce((a, x) => a + (num(x.usd) ?? 0), 0));
  $("q5h").textContent = pct(s.q5h);
  $("q7d").textContent = pct(s.q7d);
  $("q5h").className = num(s.q5h) >= 80 ? "hi" : "";
  $("q7d").className = num(s.q7d) >= 80 ? "hi" : "";
  $("upmax").textContent = hm(ss.reduce((a, x) => Math.max(a, num(x.up) ?? -1), -1));
  const rows = document.createDocumentFragment();
  for (const x of ss) {
    const tr = document.createElement("tr"), w = x.waiting == null ? "" : enumv(x.waiting) || "yes";
    const st = enumv(x.status);
    namecell(tr, enumv(x.name));
    statuscell(tr, st, w ? "wait" : st === "busy" ? "busy" : "idle");
    cell(tr, w || "–", w ? "wait" : "");
    cell(tr, k(x.tok));
    cell(tr, pct(x.pct), num(x.pct) >= 85 ? "hi" : "");
    cell(tr, usd(x.usd));
    cell(tr, hm(x.up));
    cell(tr, doing(x.name), "doing");
    rows.appendChild(tr);
  }
  $("rows").replaceChildren(rows); party(ss);
}

function paint() {
  const age = last ? Math.floor(Date.now() / 1000 - last.ts) : null;
  const stale = age === null || age > STALE;
  document.body.classList.toggle("stale", stale);
  $("age").textContent = age === null ? "no data" : "updated " + age + "s ago" + (stale ? " — STALE (watchdog down?)" : "");
  const msgs = [];
  if (failed) msgs.push("state.json fetch failed");
  if (last && num(last.flags) > 0) msgs.push(last.flags + " flag" + (last.flags > 1 ? "s" : "") + " raised");
  if (sideFailed) msgs.push("flags/asks/lease/board/alerts fetch failed");
  if (side.lease && side.lease.state === "stale") msgs.push("lease stale — boss hung?");
  const prot = (Array.isArray(side.asks) ? side.asks : []).filter(x => x.protected).length;
  if (prot) msgs.push(prot + " protected ask" + (prot > 1 ? "s" : "") + " — a human must answer");
  const red = msgs.length > 0; $("banner").classList.toggle("amber", !red);   // open asks alone → amber
  const al = freshAlert(); if (al) msgs.push("ALERT " + al);                    // notify.log <10 min → amber
  if (last && num(last.asks) > 0) msgs.push(last.asks + " open ask" + (last.asks > 1 ? "s" : "") + " — jiva inbox");
  $("banner").textContent = msgs.join(" · ");
  $("banner").classList.toggle("on", msgs.length > 0);
}

async function poll() {
  try {
    const r = await fetch("state.json", { cache: "no-store" });
    if (!r.ok) throw new Error(r.status);
    const s = await r.json();
    if (num(s.ts) === null) throw new Error("bad ts");
    last = s; failed = false; render(s);
  } catch (e) { failed = true; }
  paint();
}
async function pollSide() {
  try {
    const get = async u => { const r = await fetch(u, { cache: "no-store" }); if (!r.ok) throw new Error(r.status); return r.json(); };
    const [f, a, l, b, n] = await Promise.all([get("flags"), get("asks"), get("lease"), get("board"), get("alerts")]);
    side = { flags: f, asks: a, lease: l, board: b, alerts: n }; sideFailed = false;
  } catch (e) { sideFailed = true; }
  renderSide(); renderBoard(); renderAlerts(); if (last) render(last); paint();
}
fetch("pack.json").then(r => r.ok ? r.json() : null).then(p => { pack = p; if (last) render(last); }).catch(() => {});
poll(); pollSide();
setInterval(poll, 5000); setInterval(pollSide, 5000);
setInterval(paint, 1000);
