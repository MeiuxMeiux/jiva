#!/usr/bin/env bash
# verify <url> — site-verify, curl only: every header in site/deploy/apache-jiva.conf,
# 200 on /, 4xx on /../ (Apache says 400 or 404, serve.py 404), first-load weight < 400 KB, hashed assets resolve and
# match their name hash + SRI, every asset's Content-Type (verify-assets.sh). On 127.0.0.1/localhost a missing header is checked against its meta
# twin (CSP, Referrer-Policy) or reported "skip (meta-only)". Read-only GET/HEAD; exits 1 on any FAIL.
# Then verify-tls.sh: testssl.sh grade (if on PATH) + Mozilla Observatory, non-loopback https only.
set -uo pipefail
url=${1:?usage: verify.sh <url>}; url=${url%/}
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CONF="$HERE/../deploy/apache-jiva.conf"
local=0; [[ $url =~ ^https?://(127\.0\.0\.1|localhost)(:[0-9]+)?$ ]] && local=1
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0
ok()   { printf '  ok    %s\n' "$*"; }
skip() { printf '  skip  %s\n' "$*"; }
bad()  { printf '  FAIL  %s\n' "$*"; fail=1; }
get()  { curl -sS --path-as-is --max-time 15 -o "$2" -w '%{http_code}' "$url$1" 2>/dev/null || true; }

echo "verify: $url $( ((local)) && echo '(local: meta-only headers allowed)')"
touch "$tmp/h"
code=$(curl -sS --max-time 15 -I -o "$tmp/h" -w '%{http_code}' "$url/" 2>/dev/null || true)
[[ $code == 200 ]] && ok "HEAD / → 200" || bad "HEAD / → $code (want 200)"
code=$(get / "$tmp/index.html")
[[ $code == 200 ]] && ok "GET / → 200" || { bad "GET / → $code (want 200)"; echo "verify: FAILED (unreachable)"; exit 1; }
tr -d '\r' < "$tmp/h" > "$tmp/hdr"

meta() {  # meta twin of a header in the fetched page: http-equiv=CSP or name=referrer
  case ${1,,} in
    content-security-policy) grep -o '<meta http-equiv="Content-Security-Policy" content="[^"]*"' "$tmp/index.html" ;;
    referrer-policy)         grep -o '<meta name="referrer" content="[^"]*"' "$tmp/index.html" ;;
    *) return 1 ;;
  esac | sed 's/.*content="//; s/"$//; s/&#39;/'"'"'/g'
}

echo "headers (site/deploy/apache-jiva.conf)"
while IFS= read -r line; do
  [[ $line =~ ^[[:space:]]*Header[[:space:]]+always[[:space:]]+set[[:space:]]+([A-Za-z-]+)[[:space:]]+\"([^\"]*)\" ]] || continue
  name=${BASH_REMATCH[1]} want=${BASH_REMATCH[2]}
  got=$(grep -i "^$name:" "$tmp/hdr" | head -1 | sed 's/^[^:]*:[[:space:]]*//')
  if [[ -n $got ]]; then
    [[ $got == "$want" ]] && ok "$name" || bad "$name: got '$got' want '$want'"
  elif ((local)) && m=$(meta "$name") && [[ -n $m ]]; then
    [[ $m == "$want" ]] && ok "$name (meta)" || bad "$name (meta): got '$m' want '$want'"
    [[ $name == Content-Security-Policy ]] && skip "frame-ancestors (meta-only: browsers ignore it in meta)"
  elif ((local)); then
    skip "$name (meta-only: no header from the dev server)"
  else
    bad "$name: missing"
  fi
done < "$CONF"

echo "paths"
code=$(get /../ "$tmp/trav")
[[ $code == 40[04] ]] && ok "GET /../ → $code" || bad "GET /../ → $code (want 404, or Apache's 400)"
code=$(get /jiva-verify-missing "$tmp/miss")
[[ $code == 404 ]] && ok "GET /jiva-verify-missing → 404" || bad "GET /jiva-verify-missing → $code (want 404)"

echo "assets"
weight=$(stat -c %s "$tmp/index.html")
refs=$(grep -oE '(href|src)="[^"#:]+"' "$tmp/index.html" | sed -E 's/^[a-z]+="//; s/"$//' | sort -u)
for ref in $refs; do
  f="$tmp/a.$RANDOM"
  code=$(get "/${ref#/}" "$f")
  [[ $code == 200 ]] || { bad "$ref → $code"; continue; }
  weight=$((weight + $(stat -c %s "$f")))
  if [[ $ref =~ \.([0-9a-f]{8})\.[a-z0-9]+$ ]]; then
    h=$(sha256sum "$f" | cut -c1-8)
    [[ $h == "${BASH_REMATCH[1]}" ]] && ok "$ref (hash)" || bad "$ref: bytes hash $h ≠ name"
  fi
  sri=$(grep -oE "(href|src)=\"$ref\"[^>]*integrity=\"sha384-[^\"]+\"" "$tmp/index.html" | grep -oE 'sha384-[^"]+')
  if [[ -n $sri ]]; then
    have="sha384-$(openssl dgst -sha384 -binary "$f" | base64 -w0)"
    [[ $have == "$sri" ]] && ok "$ref (SRI)" || bad "$ref: SRI mismatch"
  fi
done
kb=$((weight / 1024))
((weight < 400 * 1024)) && ok "first-load weight ${kb} KB < 400 KB" || bad "first-load weight ${kb} KB ≥ 400 KB"

"$HERE/verify-assets.sh" "$url" "$tmp/index.html" || fail=1   # every asset: Content-Type set + right family
"$HERE/verify-tls.sh" "$url" || fail=1   # testssl grade + Mozilla Observatory; both skip on loopback
((fail)) && echo "verify: FAILED" || echo "verify: pass"
exit $fail
