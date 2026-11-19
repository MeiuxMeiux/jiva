# kit — portable hive files (kit/) → one markdown (scripts/kit-build.py, `just kit [out]`, site build/kit.md)
- kit/ORDER lists every emitted file (relative to kit/, emitted as .hive/<path>); a missing entry fails the build,
  so the site build fails too until every ORDER file exists.
- Run order rows in kit-build.py RUN map 1:1 to docs/MICRO.md "## Phase N" headings; adding a phase there fails the
  build until RUN gets a row. Fences grow past the longest backtick run inside a file.
- kit/roles use `just hive <recipe>` (kit/hive.just is a just module: `mod hive`), never `jiva` verbs.
- Under `set -o pipefail`, `cmd | grep -q` can false-fail: grep exits early, cmd dies of SIGPIPE (w1).
