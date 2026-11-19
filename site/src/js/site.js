// page motion. Section reveal: IntersectionObserver adds .in to each .band once (titles rise; the
// band's tile + emblem art is keyed on .in, so it loads lazily). .js on <html> gates the hidden state,
// so a page without js shows every title. Hero parallax: --py (px) via CSSOM, skipped on reduced motion.
"use strict";
(function () {
  var root = document.documentElement;
  var still = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  if ("IntersectionObserver" in window) {
    root.classList.add("js");
    var io = new IntersectionObserver(function (es) {
      es.forEach(function (e) {
        if (!e.isIntersecting) return;
        e.target.classList.add("in");
        io.unobserve(e.target);
      });
    }, { rootMargin: "0px 0px -12% 0px" });
    Array.prototype.forEach.call(document.querySelectorAll("main > .band"), function (b) { io.observe(b); });
  }
  // JIVA Micro + Kit: each .micro-copy fetches its data-src once on intent, copies on click
  if (navigator.clipboard && window.fetch) Array.prototype.forEach.call(document.querySelectorAll(".micro-copy"), function (copy) {
    var label = copy.textContent, text = null, get = function () {
      return text || (text = fetch(copy.dataset.src).then(function (r) { return r.ok ? r.text() : Promise.reject(r.status); }));
    };
    copy.hidden = false;
    copy.addEventListener("pointerenter", get);
    copy.addEventListener("focus", get);
    copy.addEventListener("click", function () {
      get().then(function (t) { return navigator.clipboard.writeText(t); })
        .then(function () { copy.textContent = "Copied"; }, function () { copy.textContent = "Copy failed: use the link"; text = null; })
        .then(function () { window.setTimeout(function () { copy.textContent = label; }, 2500); });
    });
  });
  var hero = document.querySelector(".hero");
  if (!hero || still) return;
  var queued = false;
  function drift() {
    queued = false;
    var y = Math.min(window.scrollY, hero.offsetHeight);
    hero.style.setProperty("--py", Math.min(120, y * 0.28).toFixed(1));
  }
  window.addEventListener("scroll", function () {
    if (!queued) { queued = true; window.requestAnimationFrame(drift); }
  }, { passive: true });
  drift();
}());
