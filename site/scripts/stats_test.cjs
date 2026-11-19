// stats.js unit checks, node only (no browser): run by stats_check.py when node is on PATH.
// 1. JStats.f formats equal stats_data.FMT's for the same values (argv[2] = JSON {fmt: [[value, python_text], ...]})
// 2. dollars refuse to print outside a band carrying the API-equivalent label
// 3. a corrupted or unknown-schema data file shows the "data unavailable" notice, with no thrown error
"use strict";
const fs = require("fs"), path = require("path"), vm = require("vm");
const SRC = fs.readFileSync(path.join(__dirname, "..", "src", "stats", "js", "stats.js"), "utf8");
const expect = JSON.parse(process.argv[2] || "{}");
let fails = 0;
const fail = (m) => { fails++; console.log("FAIL stats js: " + m); };

function load(fetchImpl) {
  const notice = { hidden: true, textContent: "" }, classes = new Set();
  const main = { getAttribute: () => "data.x.json", classList: { add: (c) => classes.add(c) }, querySelector: () => notice };
  const document = {
    readyState: "complete", addEventListener() {},
    querySelector: (q) => (q === "main[data-src]" ? main : null), querySelectorAll: () => []
  };
  const ctx = { document, fetch: fetchImpl, Promise, setTimeout, clearTimeout, console };
  ctx.window = ctx;
  vm.createContext(ctx);
  vm.runInContext(SRC, ctx);
  return { S: ctx.JStats, notice, classes };
}

const { S } = load(() => new Promise(() => {}));
for (const [fmt, pairs] of Object.entries(expect)) {
  for (const [v, want] of pairs) {
    const got = S.f[fmt](v);
    if (got !== want) fail(`f.${fmt}(${v}) = ${got}, python says ${want}`);
  }
}
const band = { closest: () => ({ textContent: "x " + S.LABEL + " y" }) }, bare = { closest: () => null };
if (S.usd(5702.76, band) !== "$5,703" || S.usd(0.17, band) !== "$0.17") fail("usd formatting");
try { S.usd(1, bare); fail("usd printed a dollar without the label"); } catch (e) { /* expected */ }

const cases = [
  ["unknown schema", () => Promise.resolve({ ok: true, json: () => Promise.resolve({ schema: "other/9" }) })],
  ["corrupted json", () => Promise.resolve({ ok: true, json: () => Promise.reject(new SyntaxError("bad")) })],
  ["http 404", () => Promise.resolve({ ok: false, status: 404 })]
];
Promise.all(cases.map(([name, impl]) => {
  const t = load(impl);
  return new Promise((done) => setTimeout(() => {
    if (t.notice.hidden || !t.classes.has("nodata")) fail(`${name}: no "data unavailable" notice`);
    done();
  }, 30));
})).then(() => {
  const n = Object.values(expect).reduce((a, p) => a + p.length, 0);
  console.log(`site-check: stats js ${fails ? "FAIL" : "ok"} (${n} format pairs vs python, money guard, 3 bad-data cases)`);
  process.exit(fails ? 1 : 0);
});
