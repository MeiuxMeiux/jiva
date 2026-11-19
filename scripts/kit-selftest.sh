#!/usr/bin/env bash
# kit-selftest — the stranger path end to end: build kit.md, extract it with scripts/kit-extract.py (the same
# 5 lines the GUIDE gives a keeper), run the EXTRACTED .hive/test.sh (fake claude, no tokens). Exit 0 = green.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
snip="$(sed -n '/^for p, f, b in re.findall/p' scripts/kit-extract.py | sed 's/^ *//')"
grep -qF "$snip" kit/GUIDE.md || { echo "kit-selftest: GUIDE snippet drifted from scripts/kit-extract.py"; exit 1; }
mkdir -p /tmp/jiva-scratch; d=$(mktemp -d /tmp/jiva-scratch/kit-extract.XXXXXX); trap 'rm -rf "$d"' EXIT
python3 -I scripts/kit-build.py "$d/KIT.md"
n=$(cd "$d" && python3 -I "$OLDPWD/scripts/kit-extract.py" KIT.md | wc -l); echo "kit-selftest: extracted $n files"
(cd "$d" && chmod +x .hive/bin/*.sh && bash .hive/test.sh)
