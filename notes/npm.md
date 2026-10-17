# npm — the jiva-fleet courier (npm/)
- Courier, never the runtime: init (deps + git clone/pull into ${JIVA_HOME:-~/.jiva}), micro, doctor.
- Zero deps; every child process is spawnSync with an arg array (lib/run.js), never a shell string.
- npm/MICRO.md + npm/LICENSE are copied at pack time (prepack → scripts/bundle.js) and gitignored;
  from a checkout, micro falls back to ../docs/MICRO.md, so `node npm/bin/jiva-fleet.js micro` works unpacked.
- npm/.npmignore exists only so npm stops reading npm/.gitignore (it would drop the bundled MICRO.md);
  `files` in package.json is the real allowlist. Verify with `cd npm && npm pack --dry-run`.
- Platform gate covers init/doctor only (win32 refuses; darwin needs --force); micro/help run anywhere.
- Smoke test: `node npm/scripts/smoke.js` (CI job `npm` runs it after `npm pack`). Not published yet.
