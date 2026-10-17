#!/usr/bin/env bash
# verify-tls <url> — called by verify.sh. Non-loopback https only (127.0.0.1/localhost/http → "skip"):
# (1) testssl.sh when on PATH: --quiet, prints only the "Overall Grade" line; (2) Mozilla HTTP Observatory v2
# (POST /api/v2/scan?host= returns the cached/fresh grade; it never touches the site beyond its own GETs).
# Grade A* → ok, any other grade → FAIL (exit 1); tool absent / network error / no grade → skip, never FAIL.
set -uo pipefail
url=${1:?usage: verify-tls.sh <url>}; url=${url%/}
ok()   { printf '  ok    %s\n' "$*"; }
skip() { printf '  skip  %s\n' "$*"; }
bad()  { printf '  FAIL  %s\n' "$*"; fail=1; }
fail=0
echo "tls + observatory"
host=""; [[ $url =~ ^https://([^/:]+) ]] && host=${BASH_REMATCH[1]}
if [[ -z $host || $host =~ ^(127\.0\.0\.1|localhost)$ ]]; then
  skip "testssl (loopback or plain http)"; skip "observatory (loopback or plain http)"; exit 0
fi
grade() { [[ $2 == A* ]] && ok "$1 grade $2" || bad "$1 grade $2 (want A)"; }

t=$(command -v testssl.sh || command -v testssl || true)
if [[ -z $t ]]; then skip "testssl (testssl.sh not on PATH)"
else
  g=$("$t" --quiet --color 0 --warnings off "$host" 2>/dev/null | grep -m1 'Overall Grade' | awk '{print $NF}')
  [[ -n $g ]] && grade testssl "$g" || skip "testssl (no grade line)"
fi

r=$(curl -sS --max-time 60 -X POST "https://observatory-api.mdn.mozilla.net/api/v2/scan?host=$host" 2>/dev/null || true)
g=$(jq -r 'select(.grade != null) | "\(.grade) (score \(.score))"' <<<"$r" 2>/dev/null)
[[ -n $g ]] && grade observatory "$g" || skip "observatory (no grade: $(jq -r '.error // "unreachable"' <<<"$r" 2>/dev/null | head -c 60))"
exit $fail
