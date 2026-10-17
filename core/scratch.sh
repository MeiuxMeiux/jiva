#!/usr/bin/env bash
# jiva scratch <name> [rm] — fixed scratch dir /tmp/jiva-scratch/<name> so agents never rm a computed path.
#   no rm: mkdir -p, print the path.   rm: delete only that subpath after a realpath check it sits under the root.
set -euo pipefail
ROOT=/tmp/jiva-scratch
n="${1:-}"
[[ $n =~ ^[A-Za-z0-9._-]+$ && $n != . && $n != .. ]] || { echo "scratch: name must be [A-Za-z0-9._-]+" >&2; exit 1; }
[[ -e $ROOT || -L $ROOT ]] || mkdir -m 700 "$ROOT" 2>/dev/null || true   # shared /tmp: must be ours, a real dir
[[ -d $ROOT && ! -L $ROOT && -O $ROOT ]] && chmod go-w "$ROOT" || { echo "scratch: $ROOT is not a dir you own — refused" >&2; exit 1; }
d="$ROOT/$n"
case "${2:-}" in
  '') mkdir -p "$d"; echo "$d" ;;
  rm) [[ -e $d || -L $d ]] || exit 0
      r="$(realpath -e "$ROOT")"; p="$(realpath -e "$d")"
      [[ $p == "$r"/* && $p != "$r"/*/* ]] || { echo "scratch: $d resolves outside $ROOT — refused" >&2; exit 1; }
      rm -rf -- "$p"; echo "scratch: removed $d" ;;
  *) echo "usage: jiva scratch <name> [rm]" >&2; exit 1 ;;
esac
