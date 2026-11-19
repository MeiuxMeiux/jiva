#!/usr/bin/env bash
# plugin wrapper → core/hooks/perm-relay.sh (opt-in: not in hooks.json; add a PermissionRequest entry to wire it)
# shellcheck source=plugin/hooks/_exec.sh
source "$(dirname "$(readlink -f "$0")")/_exec.sh"
