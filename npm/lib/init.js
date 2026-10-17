'use strict';
// `init [dir]`: check deps, clone or fast-forward the checkout, print the one PATH line.
const fs = require('fs');
const os = require('os');
const path = require('path');
const { run } = require('./run');
const { checkDeps } = require('./deps');

const REPO = 'https://github.com/MeiuxMeiux/jiva';

function home(dir) {
  const raw = dir || process.env.JIVA_HOME || path.join(os.homedir(), '.jiva');
  return path.resolve(raw.replace(/^~(?=$|\/)/, os.homedir()));
}

function sync(dest) {
  if (fs.existsSync(path.join(dest, '.git'))) {
    console.log(`updating ${dest} (git pull --ff-only)`);
    return run('git', ['-C', dest, 'pull', '--ff-only'], { stdio: 'inherit' }).ok;
  }
  if (fs.existsSync(dest) && fs.readdirSync(dest).length > 0) {
    console.error(`jiva-fleet: ${dest} exists, is not empty and is not a git checkout; pick another dir`);
    return false;
  }
  console.log(`cloning ${REPO} → ${dest}`);
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  return run('git', ['clone', REPO, dest], { stdio: 'inherit' }).ok;
}

function init(dir) {
  const dest = home(dir);
  console.log('checking dependencies:');
  const { missing, optional } = checkDeps();
  if (optional.length) console.log(`optional, not found: ${optional.join(' ')}`);
  if (missing.length) {
    console.error(`missing (required): ${missing.join(' ')}`);
    console.error('install those, then run `npx jiva-fleet init` again (prerequisites: docs/QUICKSTART.md §0)');
    return 1;
  }
  if (!sync(dest)) return 1;
  const bin = path.join(dest, 'bin');
  console.log('\nadd this line to your shell rc (jiva-fleet never edits it for you):');
  console.log(`  export PATH="${bin}:$PATH"`);
  console.log('then: jiva help');
  return 0;
}

module.exports = { init, home };
