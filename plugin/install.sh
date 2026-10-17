#!/usr/bin/env bash
# plugin/install.sh install|uninstall|status [-q] — the jiva plugin at user scope, from this LOCAL folder.
# This folder is its own marketplace (jiva-local, .claude-plugin/marketplace.json, source "./"), so an
# installed session reads the plugin straight from the checkout: edit + /reload-plugins, no reinstall.
# Never publishes, never touches GitHub. Status line: plugins can't own it — see notes/plugin.md.
set -euo pipefail
here="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
mk=jiva-local id="jiva@jiva-local"
has_mk() { claude plugin marketplace list 2>/dev/null | grep -q "$mk"; }
case "${1:-status}" in
  install)
    has_mk || claude plugin marketplace add "$here" --scope user
    claude plugin install "$id" --scope user
    echo "statusLine (manual, ~/.claude/settings.json):"
    printf '  "statusLine": {"type": "command", "command": "%s/hooks/statusline.sh"}\n' "$here" ;;
  uninstall)
    claude plugin uninstall "$id" --scope user 2>/dev/null || true
    has_mk && claude plugin marketplace remove "$mk" ;;
  status) # cheap + machine-readable: exit 0 = installed at user scope and not disabled (json only, no `claude`)
    cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
    jq -e --arg id "$id" '.plugins[$id] // [] | any(.scope == "user")' "$cfg/plugins/installed_plugins.json" \
      >/dev/null 2>&1 && [[ $(jq -r --arg id "$id" '.enabledPlugins[$id] != false' "$cfg/settings.json" 2>/dev/null \
      || echo true) == true ]] || { [[ -n ${2:-} ]] || echo "jiva plugin: not installed ($cfg)"; exit 1; }
    [[ -n ${2:-} ]] || echo "jiva plugin: installed at user scope ($cfg)" ;;
  *) echo "usage: plugin/install.sh install|uninstall|status" >&2; exit 2 ;;
esac
