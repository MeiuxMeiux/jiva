'use strict';
// spawnSync with arg arrays only — never a shell string.
const { spawnSync } = require('child_process');

function run(cmd, args, opts = {}) {
  const r = spawnSync(cmd, args, { encoding: 'utf8', ...opts });
  return {
    ok: !r.error && r.status === 0,
    missing: !!(r.error && r.error.code === 'ENOENT'),
    status: r.error ? 127 : r.status,
    out: `${r.stdout || ''}${r.stderr || ''}`.trim(),
  };
}

// "tmux 3.4" / "jq-1.7" / "3.2a" → [3, 4]; null when no number is found
function version(text) {
  const m = /(\d+)\.(\d+)/.exec(text || '');
  return m ? [Number(m[1]), Number(m[2])] : null;
}

function atLeast(have, want) {
  if (!have) return false;
  return have[0] > want[0] || (have[0] === want[0] && have[1] >= want[1]);
}

module.exports = { run, version, atLeast };
