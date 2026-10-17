#!/usr/bin/env bash
# plugin wrapper → core/hooks/session-start.sh
# shellcheck source=plugin/hooks/_exec.sh
source "$(dirname "$(readlink -f "$0")")/_exec.sh"
