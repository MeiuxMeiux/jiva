# kit — portable fleet files (kit/) → one markdown (scripts/kit-build.py, `just kit [out]`, site build/kit.md)
- kit/ORDER lists every emitted file (relative to kit/, emitted as .fleet/<path>); a missing entry fails the build,
  so the site build fails too until every ORDER file exists.
- Run order rows in kit-build.py RUN map 1:1 to docs/MICRO.md "## Phase N" headings; adding a phase there fails the
  build until RUN gets a row. Fences grow past the longest backtick run inside a file.
- kit/roles use `just <recipe>` from kit/fleet.just only, never `jiva` verbs (a stranger has no JIVA checkout).
