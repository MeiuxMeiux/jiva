'use strict';
// Dependency check for `init`: one line per tool, then exactly what is missing.
const { run, version, atLeast } = require('./run');

// [name, probe args, minimum version or null, required?]
const TOOLS = [
  ['bash', ['-c', 'echo "${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}"'], [4, 0], true],
  ['git', ['--version'], null, true],
  ['tmux', ['-V'], [3, 2], true],
  ['jq', ['--version'], [1, 6], true],
  ['flock', ['--version'], null, true],
  ['just', ['--version'], null, true],
  ['python3', ['--version'], null, true],
  ['claude', ['--version'], null, true],
  ['gh', ['--version'], null, false],
  ['shellcheck', ['--version'], null, false],
  ['gitleaks', ['version'], null, false],
];

function checkOne([name, args, min, required]) {
  const r = run(name, args, { timeout: 15000 });
  const v = r.missing ? null : version(r.out);
  let problem = null;
  if (r.missing) problem = 'not found';
  else if (min && !atLeast(v, min)) problem = `need ≥${min.join('.')}, found ${v ? v.join('.') : 'unknown'}`;
  return { name, required, problem, v };
}

function checkDeps(log = console.log) {
  const results = TOOLS.map(checkOne);
  for (const r of results) {
    const tag = r.problem ? (r.required ? 'MISSING' : 'optional') : 'ok';
    log(`  ${tag.padEnd(8)} ${r.name}${r.problem ? ` (${r.problem})` : r.v ? ` ${r.v.join('.')}` : ''}`);
  }
  const missing = results.filter((r) => r.problem && r.required).map((r) => r.name);
  const optional = results.filter((r) => r.problem && !r.required).map((r) => r.name);
  return { missing, optional };
}

module.exports = { checkDeps, TOOLS };
