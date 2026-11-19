# site — static marketing page, local only. Imported by the root justfile.

# site: build then serve site/build on 127.0.0.1:<random high port> (foreground; Ctrl-C stops)
site-dev: site-build
    #!/usr/bin/env bash
    set -uo pipefail
    for _ in 1 2 3 4 5; do
      port=$(shuf -i 20000-60000 -n 1)
      echo "site-dev: http://127.0.0.1:$port/  (WSL2: open it in the Windows browser)"
      python3 -I "{{source_directory()}}/scripts/serve.py" "$port" && exit 0
      echo "site-dev: port $port busy, retrying"
    done
    exit 1

# site: generate partials/reference.html (jiva help + just --list), include partials, bundle + minify css/js into site/build/
site-build:
    @python3 -I "{{source_directory()}}/scripts/reference.py"
    @python3 -I "{{source_directory()}}/scripts/build.py"

# site: html validity, no third-party urls / inline js+css, CSP parity, drift vs CLI, a11y, ≤150 lines, initial load < 400 KB, build < 3 MB
site-check: site-build
    @python3 -I "{{source_directory()}}/scripts/check.py"

# site: read-only header/status/weight/SRI checks against a url, curl only (127.0.0.1 allows meta-only)
site-verify url:
    @bash "{{source_directory()}}/scripts/verify.sh" {{url}}
