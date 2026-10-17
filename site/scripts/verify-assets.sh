#!/usr/bin/env bash
# verify-assets <url> <index.html> — called by verify.sh. HEADs every same-origin asset the page references
# (href, src, srcset, og:image content) and FAILs when Content-Type is empty or not the extension's family.
# Why: Apache without `AddType image/webp` sent .webp with no type, and nosniff then makes browsers drop it.
# One line per extension (count + type seen), not per file. curl only, read-only; exits 1 on any FAIL.
set -uo pipefail
url=${1:?usage: verify-assets.sh <url> <index.html>}; url=${url%/}; page=${2:?index.html path}
ok()   { printf '  ok    %s\n' "$*"; }
bad()  { printf '  FAIL  %s\n' "$*"; fail=1; }
fail=0
want() {  # extension → regex the Content-Type (sans params) must match; unknown → any non-empty
  case $1 in
    css) echo '^text/css$' ;;            js) echo '^(text|application)/(x-)?javascript$' ;;
    woff2) echo '^font/woff2$' ;;        svg) echo '^image/svg\+xml$' ;;
    webp) echo '^image/webp$' ;;         png) echo '^image/png$' ;;
    ico) echo '^image/(x-icon|vnd\.microsoft\.icon)$' ;;  txt) echo '^text/plain$' ;;
    xml) echo '^(application|text)/xml$' ;;  webmanifest) echo '^application/(manifest\+)?json$' ;;
    *) echo '.' ;;
  esac
}

echo "content-types"
origin=$(grep -oE '^https?://[^/]+' <<<"$url")
refs=$( {
  grep -oE '(href|src)="[^"#]+"' "$page" | sed -E 's/^[a-z]+="//; s/"$//'
  grep -oE 'srcset="[^"]+"' "$page" | sed -E 's/^srcset="//; s/"$//' | tr ',' '\n' | awk '{print $1}'
  grep -oE '<meta property="og:image" content="[^"]+"' "$page" | sed -E 's/.*content="//; s/"$//'
  printf '%s\n' robots.txt sitemap.xml humans.txt .well-known/security.txt  # crawler paths, unlinked
} | sed -E "s#^$origin##; s#^https://jiva\.meiuxmeiux\.com/##" | grep -vE '^[a-z]+:' | grep -E '\.[A-Za-z0-9]+$' | grep -vE '\.html?$' | sort -u)
[[ -n $refs ]] || { bad "no asset refs found in the page"; exit 1; }

declare -A n bads types
for ref in $refs; do
  ext=${ref##*.}; ext=${ext,,}
  ct=$(curl -sS --path-as-is --max-time 15 -I -o /dev/null -w '%{content_type}' "$url/${ref#/}" 2>/dev/null || true)
  ct=${ct%%;*}; ct=${ct,,}; ct=${ct//[[:space:]]/}
  n[$ext]=$(( ${n[$ext]:-0} + 1 ))
  [[ " ${types[$ext]:-} " == *" ${ct:-<empty>} "* ]] || types[$ext]="${types[$ext]:-} ${ct:-<empty>}"
  [[ -n $ct && $ct =~ $(want "$ext") ]] || bads[$ext]="${bads[$ext]:-} $ref"
done

for ext in $(printf '%s\n' "${!n[@]}" | sort); do
  seen=${types[$ext]# }
  if [[ -z ${bads[$ext]:-} ]]; then
    ok ".$ext ×${n[$ext]} → $seen"
  else
    set -- ${bads[$ext]}
    bad ".$ext ×${n[$ext]} → $seen (want $(want "$ext"); $# bad, e.g. $1)"
  fi
done
exit $fail
