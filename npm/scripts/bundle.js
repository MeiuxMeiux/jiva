#!/usr/bin/env node
// prepack: copy the repo-root sources the package ships (docs/MICRO.md, LICENSE) next to package.json.
'use strict';
const fs = require('fs');
const path = require('path');

const pkg = path.resolve(__dirname, '..');
const root = path.resolve(pkg, '..');
for (const [from, to] of [['docs/MICRO.md', 'MICRO.md'], ['LICENSE', 'LICENSE']]) {
  const src = path.join(root, from);
  if (!fs.existsSync(src)) {
    console.error(`bundle: missing ${src} (run npm pack from a JIVA checkout)`);
    process.exit(1);
  }
  fs.copyFileSync(src, path.join(pkg, to));
}
