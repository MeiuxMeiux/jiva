#!/usr/bin/env node
// jiva-fleet: the npx courier for JIVA. It installs and checks; it is never the runtime.
'use strict';
const fs = require('fs');
const path = require('path');
const { run } = require('../lib/run');
const { init, home } = require('../lib/init');
const { micro } = require('../lib/micro');
const { version } = require('../package.json');

const HELP = `jiva-fleet ${version} — courier for JIVA (https://jiva.meiuxmeiux.com)

usage: npx jiva-fleet <command> [--force]
  init [dir]     check deps, clone/update MeiuxMeiux/jiva into dir (default \${JIVA_HOME:-~/.jiva}),
                 print the PATH line to add (your shell rc is never edited)
  micro [file]   write JIVA Micro (one-file fleet) to ./JIVA.md; --force overwrites
  doctor         run <home>/bin/jiva doctor if installed
  help           this text
  --version      print the version

Linux or WSL2 only (macOS: --force, untested).`;

// init/doctor drive bash + tmux; micro/help/--version only write or print, so they run anywhere
function platformOk(force) {
  if (process.platform === 'linux') return true;
  if (process.platform === 'win32') {
    console.error('jiva-fleet: Linux/WSL2 only — run this inside WSL2, not Windows itself');
    return false;
  }
  if (force) {
    console.error(`jiva-fleet: ${process.platform} is untested (Linux/WSL2 only); continuing because of --force`);
    return true;
  }
  console.error(`jiva-fleet: Linux/WSL2 only (${process.platform}: pass --force to try anyway, untested)`);
  return false;
}

function doctor() {
  const jiva = path.join(home(), 'bin', 'jiva');
  if (!fs.existsSync(jiva)) {
    console.error(`jiva-fleet: ${jiva} not found; run \`npx jiva-fleet init\` first`);
    return 1;
  }
  return run(jiva, ['doctor'], { stdio: 'inherit' }).status;
}

function main(argv) {
  const force = argv.includes('--force');
  const [cmd, arg] = argv.filter((a) => a !== '--force');
  switch (cmd) {
    case '--version': case '-v': case 'version':
      console.log(version); return 0;
    case undefined: case 'help': case '--help': case '-h':
      console.log(HELP); return 0;
    case 'micro':
      return micro(arg, force);
    case 'init':
      return platformOk(force) ? init(arg) : 1;
    case 'doctor':
      return platformOk(force) ? doctor() : 1;
    default:
      console.error(`jiva-fleet: unknown command "${cmd}"\n\n${HELP}`); return 2;
  }
}

process.exitCode = main(process.argv.slice(2));
