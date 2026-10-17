'use strict';
// `micro [file]`: write the bundled JIVA Micro (docs/MICRO.md at pack time) to ./JIVA.md.
const fs = require('fs');
const path = require('path');

// packed: <pkg>/MICRO.md (prepack copies it); from a checkout: <repo>/docs/MICRO.md
const SOURCES = [
  path.join(__dirname, '..', 'MICRO.md'),
  path.join(__dirname, '..', '..', 'docs', 'MICRO.md'),
];

function micro(file, force) {
  const src = SOURCES.find((p) => fs.existsSync(p));
  if (!src) {
    console.error('jiva-fleet: bundled MICRO.md is missing from this package');
    return 1;
  }
  const dest = path.resolve(file || 'JIVA.md');
  if (fs.existsSync(dest) && !force) {
    console.error(`jiva-fleet: ${dest} exists; pass --force to overwrite`);
    return 1;
  }
  fs.copyFileSync(src, dest);
  console.log(`wrote ${dest}`);
  console.log('open Claude Code here and say: "Read JIVA.md. Do Phase 0 and show me the report."');
  return 0;
}

module.exports = { micro };
