// /stats core: fetch the page's own data.json (same origin, content-hashed), guard the schema, format numbers,
// build SVG, and render each [data-chart] once when it scrolls in (then .go starts its CSS motion).
// Charts live in stats-a..d.js as JStats.charts[name] = function (data, host, width).
// Money: JStats.usd() refuses to format a dollar unless the band carries the "API-equivalent" label.
"use strict";
(function () {
  var S = window.JStats = { charts: {}, schemas: ["jiva-token-stats/1", "jiva-token-stats/2"] };
  var NS = "http://www.w3.org/2000/svg";
  S.still = !!(window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches);
  S.LABEL = "API-equivalent, not what we pay";

  function grp(n) { return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ","); }
  S.f = {
    int: function (v) { return grp(Math.round(v)); },
    compact: function (v) {
      if (v >= 1e9) return (v / 1e9).toFixed(1) + " B";
      if (v >= 1e8) return Math.round(v / 1e6) + " M";
      if (v >= 1e6) return (v / 1e6).toFixed(1) + " M";
      if (v >= 1e3) return Math.round(v / 1e3) + "k";
      return String(Math.round(v));
    },
    k: function (v) { return Math.round(v / 1000) + "k"; },
    pct: function (v) { return (v * 100).toFixed(1) + "%"; },
    pct0: function (v) { return Math.round(v * 100) + "%"; },
    per100: function (v) { return String(Math.round(v * 100)); },
    num: function (v) { return String(v); }
  };
  S.usd = function (v, from) {
    var band = from && from.closest ? from.closest("[data-money]") : null;
    if (!band || band.textContent.indexOf(S.LABEL) < 0) throw new Error("dollar without its API-equivalent label");
    return "$" + (v >= 100 ? grp(Math.round(v)) : v.toFixed(2));
  };
  S.get = function (d, path) {
    return path.split(".").reduce(function (o, k) { return o == null ? o : o[k]; }, d);
  };
  S.model = function (id) {  // claude-opus-5-5 → Opus 5.5
    var m = /^claude-([a-z]+)-(\d+)(?:-(\d+))?$/.exec(id);
    return m ? m[1].charAt(0).toUpperCase() + m[1].slice(1) + " " + m[2] + (m[3] ? "." + m[3] : "") : id;
  };
  S.tok = function (r) { return (r.input || 0) + (r.cache_write || 0) + (r.cache_read || 0) + (r.output || 0); };

  S.el = function (tag, attrs, parent, text) {
    var e = document.createElementNS(NS, tag);
    Object.keys(attrs || {}).forEach(function (k) { e.setAttribute(k, attrs[k]); });
    if (text != null) e.textContent = text;
    if (parent) parent.appendChild(e);
    return e;
  };
  S.h = function (tag, cls, parent, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;
    if (parent) parent.appendChild(e);
    return e;
  };
  S.svg = function (host, w, h, label, desc) {
    var s = S.el("svg", { viewBox: "0 0 " + w + " " + h, width: w, height: h, role: "img", "aria-label": label,
      preserveAspectRatio: "xMinYMin meet" }, host);
    S.el("title", {}, s, label);
    S.el("desc", {}, s, desc || label);
    return s;
  };
  S.delay = function (e, ms) { e.style.setProperty("--d", ms + "ms"); return e; };  // CSSOM: CSP-safe
  // readout row under a chart: pointer, focus and touch all write the same line (no floating tooltip)
  S.readout = function (host) {
    var p = S.h("p", "readout", host);
    p.setAttribute("aria-live", "polite");
    p.textContent = "Point at or tab to a mark to read its values.";
    return function (mark, text) {
      mark.setAttribute("tabindex", "0");
      mark.setAttribute("aria-label", text);
      var show = function () { p.textContent = text; };
      mark.addEventListener("pointerenter", show);
      mark.addEventListener("focus", show);
      mark.addEventListener("click", show);
    };
  };
  S.count = function (span, to, fmt) {
    if (S.still || !window.requestAnimationFrame) { span.textContent = fmt(to); return; }
    var t0 = null, dur = 900;
    function step(t) {
      t0 = t0 || t;
      var k = Math.min(1, (t - t0) / dur), e = 1 - Math.pow(1 - k, 3);
      span.textContent = fmt(k < 1 ? to * e : to);
      if (k < 1) window.requestAnimationFrame(step);
    }
    window.requestAnimationFrame(step);
  };

  function draw(host, data, animate) {
    var fn = S.charts[host.getAttribute("data-chart")];
    if (!fn) return;
    host.textContent = "";
    host.classList.remove("go");
    try { fn(data, host, Math.max(280, Math.floor(host.clientWidth))); } catch (err) {
      host.textContent = "This chart could not be drawn; the table below has the numbers.";
      return;
    }
    host.dataset.w = String(host.clientWidth);
    if (!animate || S.still) host.classList.add("go");
    else window.requestAnimationFrame(function () { window.requestAnimationFrame(function () { host.classList.add("go"); }); });
  }

  function notice(main, text) {
    main.classList.add("nodata");
    var n = main.querySelector(".stats-notice");
    if (n) { n.hidden = false; n.textContent = text; }
  }

  S.start = function () {
    var main = document.querySelector("main[data-src]");
    if (!main || !window.fetch) return;
    fetch(main.getAttribute("data-src"), { credentials: "same-origin" })
      .then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
      .then(function (data) {
        if (!data || S.schemas.indexOf(data.schema) < 0) throw new Error("schema");
        S.data = data;
        var hosts = Array.prototype.slice.call(document.querySelectorAll("[data-chart]"));
        if (!("IntersectionObserver" in window)) { hosts.forEach(function (h) { draw(h, data, false); }); return; }
        var io = new IntersectionObserver(function (es) {
          es.forEach(function (e) {
            if (!e.isIntersecting) return;
            io.unobserve(e.target);
            draw(e.target, data, true);
          });
        }, { rootMargin: "0px 0px -8% 0px" });
        hosts.forEach(function (h) { io.observe(h); });
        var queued = null;
        window.addEventListener("resize", function () {
          window.clearTimeout(queued);
          queued = window.setTimeout(function () {
            hosts.forEach(function (h) {
              if (h.dataset.w && Math.abs(h.clientWidth - Number(h.dataset.w)) > 24) draw(h, data, false);
            });
          }, 200);
        });
      })
      .catch(function () { notice(main, "The data for this page is unavailable right now. The tables below still hold every number."); });
  };
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", S.start);
  else window.setTimeout(S.start, 0);
}());
