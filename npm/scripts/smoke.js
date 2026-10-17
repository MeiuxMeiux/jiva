#!/usr/bin/env node
// smoke: help, --version, micro (write, refuse, --force) in a temp dir. CI runs it after `npm pack`.
'use strict';
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const cli = path.resolve(__dirname, '..', 'bin', 'jiva-fleet.js');
const pkg = require('../package.json');
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'jiva-fleet-smoke-'));
const sh = (...args) => spawnSync(process.execPath, [cli, ...args], { cwd: dir, encoding: 'utf8' });

try {
  assert.strictEqual(sh('--version').stdout.trim(), pkg.version);
  assert.match(sh('help').stdout, /micro \[file\]/);
  assert.strictEqual(sh('nope').status, 2);
  assert.strictEqual(sh('micro').status, 0);
  const body = fs.readFileSync(path.join(dir, 'JIVA.md'), 'utf8');
  assert.match(body, /^# JIVA Micro/);
  assert.strictEqual(sh('micro').status, 1, 'refuses to overwrite');
  assert.strictEqual(sh('micro', '--force').status, 0);
  assert.strictEqual(sh('micro', 'other.md').status, 0);
  console.log('smoke ok');
} finally {
  fs.rmSync(dir, { recursive: true, force: true });
}
