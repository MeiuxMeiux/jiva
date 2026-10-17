# jiva-fleet

The npx courier for [JIVA](https://jiva.meiuxmeiux.com), a small Claude Code fleet in a private
tmux server. It checks dependencies and fetches the git checkout; it is never the runtime.
Zero dependencies, Node ≥18, Linux or WSL2 (macOS: `--force`, untested).

```
npx jiva-fleet init [dir]     # check deps, clone/update into ${JIVA_HOME:-~/.jiva}, print the PATH line
npx jiva-fleet micro [file]   # write JIVA Micro (a fleet in one file) to ./JIVA.md (--force overwrites)
npx jiva-fleet doctor         # run jiva doctor from the installed checkout
```

`init` never edits your shell rc; add the printed `export PATH=…` line yourself.
Source: https://github.com/MeiuxMeiux/jiva (MIT).
