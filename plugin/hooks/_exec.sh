# shellcheck shell=bash
# _exec — sourced by each wrapper: run the core hook of the same name from JIVA_HOME
# (env, else the checkout this plugin sits in: plugin/ is a child of it).
here="$(dirname "$(readlink -f "${BASH_SOURCE[1]}")")"
home="${JIVA_HOME:-$(cd "$here/../.." && pwd)}"
exec "$home/core/hooks/$(basename "${BASH_SOURCE[1]}")" "$@"
