"use strict";
// dash-commits — the Commits modal (loaded after dash.js; uses $, num, soul from dash.js and el, icon, txt, ago from
// dash-panels.js). /commits pages of 50 via ?before=<last sha>, loaded as the list's bottom scrolls into view;
// a row is a button that expands its /commit/<sha> diffstat inline. Native modal <dialog> + Tab trap; Esc closes.
// Text only (textContent), never markup.
(() => {
  const PAGE = 50, SHA = /^[0-9a-f]{40}$/, dlg = $("commits"), list = $("commits-list"), sum = $("commits-sum");
  const st = { before: null, done: false, busy: false, gen: 0, n: 0 }, sentinel = el("li", "loading…", "more");
  let opener = null;
  const get = async u => { const r = await fetch(u, { cache: "no-store" }); if (!r.ok) throw new Error(r.status); return r.json(); };

  // soul chip: a fleet soul (wN/boss) gets its pack avatar + slot colour; "desk" (trailer-less) gets a plain D
  function chip(s) {
    const name = txt(s, 8).replace(/[^\w]/g, "") || "?", sl = /^(w\d+|boss)$/.test(name) ? soul(name) : null;
    const span = el("span", null, "soul"), av = el("span", null, "av");
    const initial = () => av.replaceChildren(el("b", (/^(w\d+|boss|desk)$/.test(name) ? name[0] : name.slice(0, 2)).toUpperCase()));
    if (sl) span.style.setProperty("--slot", sl.color);
    if (sl && sl.avatar) {
      const img = el("img"); img.alt = ""; img.addEventListener("error", initial); img.src = sl.avatar; av.appendChild(img);
    } else initial();
    span.append(av, el("span", name, "sn")); return span;
  }

  async function expand(btn, sha) {
    const open = btn.getAttribute("aria-expanded") === "true", box = $("cs-" + sha);
    btn.setAttribute("aria-expanded", String(!open)); box.hidden = open;
    if (open || box.dataset.loaded) return;
    box.replaceChildren(el("li", "loading…", "a"));
    try {
      const c = await get("commit/" + sha), stat = Array.isArray(c.stat) ? c.stat : [];
      const items = stat.map(x => {
        const li = el("li");
        li.append(el("code", num(x.add) === null ? "bin" : "+" + x.add, "add"), el("code", num(x.del) === null ? "" : "−" + x.del, "del"),
          el("span", txt(x.file, 300), "t"));
        return li;
      });
      if (txt(c.body, 200)) items.unshift(el("li", txt(c.body, 200), "body"));
      if (!stat.length) items.push(el("li", "no file changes (merge or empty commit)", "a"));
      box.replaceChildren(...items); box.dataset.loaded = "1";
    } catch (e) { box.replaceChildren(el("li", "diffstat fetch failed — collapse and retry", "a")); }
  }

  function row(x) {
    const li = el("li", null, "crow"), btn = el("button"), box = el("ul", null, "stat"), now = Date.now() / 1000;
    btn.type = "button"; btn.setAttribute("aria-expanded", "false"); btn.setAttribute("aria-controls", "cs-" + x.sha);
    btn.append(el("code", x.sha.slice(0, 7), "sha"), el("span", txt(x.subject, 200) || "(no subject)", "t"), chip(x.soul),
      el("span", num(x.ts) === null ? "–" : ago(Math.floor(now - x.ts)), "a"),
      el("span", (num(x.files) ?? 0) + " file" + (x.files === 1 ? "" : "s"), "a"));
    box.id = "cs-" + x.sha; box.hidden = true;
    btn.addEventListener("click", () => expand(btn, x.sha));
    li.append(btn, box); return li;
  }

  async function more() {
    if (st.busy || st.done) return;
    st.busy = true; const gen = st.gen;
    try {
      const rs = await get("commits?n=" + PAGE + (st.before ? "&before=" + st.before : ""));
      if (gen !== st.gen) return;
      const ok = (Array.isArray(rs) ? rs : []).filter(x => x && SHA.test(x.sha));
      sentinel.before(...ok.map(row)); st.n += ok.length;
      if (ok.length) st.before = ok[ok.length - 1].sha;
      st.done = ok.length < PAGE;
      sentinel.textContent = st.done ? (st.n ? "— start of history —" : "no commits") : "loading…";
      sum.textContent = st.n + (st.done ? " total" : "+ loaded") + ", newest first";
    } catch (e) {
      if (gen === st.gen) { sentinel.textContent = "fetch failed — scroll to retry"; sum.textContent = "fetch failed"; }
    } finally {
      if (gen === st.gen) { st.busy = false; if (!st.done && near()) more(); }   // short page: keep filling
    }
  }
  const near = () => list.scrollHeight - list.scrollTop - list.clientHeight < 240;

  function open() {
    st.gen++; Object.assign(st, { before: null, done: false, busy: false, n: 0 });
    sentinel.textContent = "loading…"; list.replaceChildren(sentinel); sum.textContent = "–";
    opener = document.activeElement; dlg.showModal(); $("commits-close").focus(); more();
  }
  list.addEventListener("scroll", () => { if (near()) more(); }, { passive: true });
  dlg.addEventListener("keydown", e => {   // Tab trap (showModal makes the page inert; this keeps Tab off the browser chrome)
    if (e.key !== "Tab") return;
    const f = [...dlg.querySelectorAll("button")].filter(b => !b.disabled && b.offsetParent !== null);
    if (!f.length) return;
    const first = f[0], lastb = f[f.length - 1];
    if (e.shiftKey && document.activeElement === first) { e.preventDefault(); lastb.focus(); }
    else if (!e.shiftKey && document.activeElement === lastb) { e.preventDefault(); first.focus(); }
  });
  dlg.addEventListener("close", () => { st.gen++; if (opener && opener.focus) opener.focus(); });
  dlg.addEventListener("click", e => { if (e.target === dlg) dlg.close(); });   // backdrop click
  $("commits-open").addEventListener("click", open);
  $("commits-close").addEventListener("click", () => dlg.close());
})();
