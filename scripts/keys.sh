#!/usr/bin/env bash
# Source this from other scripts; it exports keys without ever printing them.
# Paths only — never values. Vars are read by the scripts that source this file.
# shellcheck disable=SC2034
KEYS_DIR="${JIVA_KEYS_DIR:-/var/keys}"
OPENROUTER_KEY_FILE="$KEYS_DIR/open-router.key"
IMAGEROUTER_KEY_FILE="$KEYS_DIR/image-router.key"

load_key() { # load_key VAR_NAME FILE
  [[ -r "$2" ]] || { echo "keys.sh: missing $2" >&2; return 1; }
  export "$1"="$(< "$2")"
}
