#!/usr/bin/env bash
# deploy the static site to your Apache host. KEEPER-RUN ONLY — agents never deploy (docs/DEPLOY.md).
#   (none)    site-check → rsync to releases/<sha>-<ts> → atomic symlink swap → keep last 5 → verify
#   rollback  point `current` at the previous release
#   verify    curl header asserts against the live site
set -euo pipefail
ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"; cd "$ROOT"
# host lives in gitignored deploy.env (JIVA_DEPLOY_HOST=user@host), never in git
[[ -r deploy.env ]] && . ./deploy.env
HOST="${JIVA_DEPLOY_HOST:?set JIVA_DEPLOY_HOST=user@host in deploy.env (gitignored)}"
DOM="${JIVA_DEPLOY_DOMAIN:-jiva.meiuxmeiux.com}"; BASE="/var/www/$DOM"
[[ $DOM =~ ^[a-z0-9.-]+$ ]] || { echo "deploy: bad JIVA_DEPLOY_DOMAIN" >&2; exit 2; }
[[ -n ${JIVA_ROLE:-} ]] && { echo "deploy: agents don't deploy; ask the desk" >&2; exit 1; }

deploy() {
  just site-check
  local rel; rel="$BASE/releases/$(git rev-parse --short HEAD)-$(date +%s)"
  ssh "$HOST" "mkdir -p '$rel'"
  rsync -a --delete site/build/ "$HOST:$rel/"
  ssh "$HOST" bash -s -- "$BASE" "$rel" <<'EOF'
set -euo pipefail; BASE=$1; rel=$2
chmod -R a+rX "$rel"
ln -sfn "$rel" "$BASE/current.tmp" && mv -T "$BASE/current.tmp" "$BASE/current"
cd "$BASE/releases" && ls -1dt -- */ | tail -n +6 | xargs -r rm -rf --
echo "live: $rel"
EOF
  verify
}

rollback() {
  ssh "$HOST" bash -s -- "$BASE" <<'EOF'
set -euo pipefail; BASE=$1; cur=$(readlink -f "$BASE/current")
prev=$(ls -1dt "$BASE"/releases/*/ | sed 's#/$##' | grep -vx "$cur" | head -1)
[[ -n $prev ]] || { echo "rollback: no previous release"; exit 1; }
ln -sfn "$prev" "$BASE/current.tmp" && mv -T "$BASE/current.tmp" "$BASE/current"; echo "now: $prev"
EOF
}

verify() {
  local h k; h="$(curl -sSI --max-time 15 "https://$DOM/")"
  head -1 <<<"$h"
  for k in content-security-policy strict-transport-security x-content-type-options referrer-policy x-frame-options; do
    if grep -qi "^$k:" <<<"$h"; then echo "ok   $k"; else echo "FAIL $k"; return 1; fi
  done
}

case "${1:-deploy}" in deploy|rollback|verify) "${1:-deploy}" ;; *) sed -n '2,5p' "$0"; exit 1 ;; esac
