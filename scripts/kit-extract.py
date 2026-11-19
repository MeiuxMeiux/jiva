#!/usr/bin/env python3
"""kit-extract — the keeper fallback for Step 0: write every "### .hive/<path>" block of a kit markdown to disk.
Same 5 lines as the snippet in kit/GUIDE.md (just kit-selftest checks they match).
Usage: python3 -I scripts/kit-extract.py KIT.md   (run from the repo root; prints each path written)."""
import re, sys, pathlib
t = open(sys.argv[1], encoding='utf-8').read()
for p, f, b in re.findall(r'^### (\.hive/\S+)\n(`{3,})\w*\n(.*?)\n\2\n', t, re.S | re.M):
    pathlib.Path(p).parent.mkdir(parents=True, exist_ok=True); pathlib.Path(p).write_text(b + '\n', encoding='utf-8'); print(p)
