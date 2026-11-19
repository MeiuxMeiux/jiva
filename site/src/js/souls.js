// §05 avatar-pack rotator. Manifest (build.py → assets.py): {"v":1,"packs":[{id,label,slots:[{slot,name,color,src}×12]}]}.
// Fetched when the section nears view; next pack preloaded. Auto-advance every SHOW ms, slot-by-slot morph
// (rotor.css). Any input freezes the countdown bar in place (dimmed); it continues once
// the pointer is outside and IDLE ms pass quietly. Reduced motion: no autoplay, instant.
// CSP: no inline style; custom properties go through CSSOM setProperty (allowed by style-src 'self').
"use strict";
(function () {
  var wrap = document.querySelector(".rotor-wrap");
  if (!wrap || !window.fetch || !window.IntersectionObserver) return;
  var SHOW = 6000, IDLE = 3000, STEP = 70;
  var bar = wrap.querySelector(".rotor"), grid = wrap.querySelector(".souls");
  var figs = Array.prototype.slice.call(grid.querySelectorAll(".soul"));
  var live = bar.querySelector(".rotor-name"), nameEl = live.querySelector("b");
  var countEl = live.querySelector(".rotor-count"), dotsEl = bar.querySelector(".rotor-dots");
  var play = bar.querySelector(".rotor-play"), fill = bar.querySelector(".rotor-bar i");
  var still = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  var packs = [], cur = 0, timer = 0, auto = !still, seen = false, asked = false, token = 0, lastPoke = 0, loads = {};
  var left = SHOW, t0 = 0, held = false, inside = false, quiet = 0;

  function load(i) {
    return loads[i] || (loads[i] = Promise.all(packs[i].slots.map(function (s) {
      var im = new Image();
      im.src = s.src;
      return im.decode ? im.decode().catch(function () {}) : Promise.resolve();
    })));
  }

  function label() {
    nameEl.textContent = packs[cur].label;
    countEl.textContent = (cur + 1) + " / " + packs.length;
    Array.prototype.forEach.call(dotsEl.children, function (d, k) {
      d.setAttribute("aria-current", k === cur ? "true" : "false");
    });
    wrap.dataset.pack = packs[cur].id;
  }

  function morph(fig, s, k) {
    var pic = fig.querySelector(".pic"), on = pic.querySelector("img.on");
    var nu = pic.querySelector("img:not(.on)");
    if (!nu) { nu = pic.appendChild(document.createElement("img")); nu.width = nu.height = 128; nu.decoding = "async"; }
    fig.style.setProperty("--i", String(k));
    nu.src = s.src; nu.alt = s.name; nu.removeAttribute("aria-hidden");
    on.alt = ""; on.setAttribute("aria-hidden", "true");
    nu.classList.add("snap"); nu.classList.remove("was");  // jump to the closed-iris start state, then animate in
    void nu.offsetWidth;
    nu.classList.remove("snap"); on.classList.remove("on"); on.classList.add("was"); nu.classList.add("on");
    if (s.color) fig.style.setProperty("--c", s.color);
    else fig.style.removeProperty("--c");
    var cap = fig.querySelector("figcaption b");
    window.setTimeout(function () { cap.textContent = s.name; }, still ? 0 : k * STEP + 300);
  }

  function go(i, user) {
    var n = packs.length;
    i = ((i % n) + n) % n;
    if (i === cur) return;
    cur = i;
    live.setAttribute("aria-live", user ? "polite" : "off");  // don't narrate every auto step
    label();
    restart();
    var mine = ++token;
    load(i).then(function () {
      if (mine !== token) return;  // superseded by a later step
      figs.forEach(function (fig, k) { morph(fig, packs[i].slots[k], k); });
      load((i + 1) % n);  // preload the next one
    });
  }

  function stop() {  // bank the countdown's unspent time
    if (timer) left = Math.max(0, left - (Date.now() - t0));
    window.clearTimeout(timer); timer = 0;
  }

  function run() {  // start, or continue a frozen countdown from where it stopped
    stop(); held = false;
    var on = auto && seen && packs.length > 1 && !document.hidden;
    wrap.dataset.state = !auto ? "off" : on ? "auto" : "wait";
    if (!on) return;
    t0 = Date.now(); bar.classList.add("run");
    timer = window.setTimeout(function () { timer = 0; go(cur + 1, false); }, left);
  }

  function restart() {  // fresh countdown; stays frozen at zero while held
    stop(); left = SHOW; bar.classList.remove("run");
    if (!auto) return;
    void fill.offsetWidth;  // rewind the CSS animation
    fill.style.setProperty("--t", SHOW + "ms");
    bar.classList.add("run");
    if (!held) run();
  }

  function poke(e) {  // any input freezes the bar in place; quiet + pointer outside resumes it
    if (!auto) return;
    if (e && e.type === "pointermove" && Date.now() - lastPoke < 300) return;
    lastPoke = Date.now();
    stop(); held = true; wrap.dataset.state = "held";
    window.clearTimeout(quiet);
    if (!inside) quiet = window.setTimeout(run, IDLE);
  }

  function init(m) {
    packs = (m && m.packs) || [];
    if (packs.length < 2) return;  // one pack: static grid, controls stay hidden
    packs.forEach(function (p, k) {
      var d = document.createElement("button");
      d.type = "button"; d.className = "rotor-dot";
      d.setAttribute("aria-label", "Show pack " + p.label);
      d.addEventListener("click", function () { go(k, true); });
      dotsEl.appendChild(d);
    });
    bar.hidden = false; grid.tabIndex = 0;
    grid.setAttribute("role", "group");
    grid.setAttribute("aria-label", "Party portraits. Left and right arrow keys switch avatar pack.");
    play.setAttribute("aria-pressed", String(auto));
    label(); load(1);
    ["pointerdown", "pointermove", "pointerover", "focusin", "keydown", "wheel", "touchstart"].forEach(function (t) {
      wrap.addEventListener(t, poke, { passive: true });
    });
    wrap.addEventListener("pointerenter", function () { inside = true; poke(); });
    wrap.addEventListener("pointerleave", function () { inside = false; poke(); });
    Array.prototype.forEach.call(bar.querySelectorAll(".rotor-btn"), function (b) {
      b.addEventListener("click", function () { go(cur + Number(b.dataset.step), true); });
    });
    play.addEventListener("click", function () {
      auto = !auto;
      play.setAttribute("aria-pressed", String(auto));
      held = false; restart();
      if (!auto) wrap.dataset.state = "off";
    });
    wrap.addEventListener("keydown", function (e) {
      var k = { ArrowLeft: cur - 1, ArrowRight: cur + 1, Home: 0, End: packs.length - 1 }[e.key];
      if (k === undefined || e.target.tagName === "INPUT") return;
      e.preventDefault();
      go(k, true);
    });
    document.addEventListener("visibilitychange", function () { if (!held) run(); });
    restart();
  }

  new IntersectionObserver(function (es) {
    seen = es[es.length - 1].isIntersecting;
    if (seen && !asked) {
      asked = true;
      fetch(wrap.dataset.packs, { credentials: "same-origin" })
        .then(function (r) { return r.ok ? r.json() : null; }).then(init).catch(function () {});
    } else if (packs.length > 1 && !held) {
      run();
    }
  }, { rootMargin: "200px 0px" }).observe(wrap);
}());
