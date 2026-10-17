# Support

JIVA is an alpha maintained by one person, best effort. Before asking:

1. Read the [README](README.md) and [docs/QUICKSTART.md](docs/QUICKSTART.md).
2. Run `jiva doctor` (or `just doctor` inside the checkout); most problems show up as a FAIL line.
   A session that looks busy but never moves is usually parked at a permission prompt: `jiva pending`.
3. Search [existing issues](https://github.com/MeiuxMeiux/jiva/issues?q=is%3Aissue).

## Where to ask

| what | where |
|---|---|
| bug (something does not work as documented) | [bug report](https://github.com/MeiuxMeiux/jiva/issues/new?template=bug_report.yml) |
| idea, new verb or recipe | [feature request](https://github.com/MeiuxMeiux/jiva/issues/new?template=feature_request.yml) |
| security problem | **not** an issue: see [SECURITY.md](SECURITY.md) |
| conduct problem | see [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) |
| anything else | <jiva@meiuxmeiux.com> |

Never paste keys, tokens, private board lines or `.jiva/` state you have not read first.

## Not supported

- Claude Code itself (sessions, billing, models): ask Anthropic.
- Setups that share the jiva tmux socket with your own sessions.
- macOS (untested; needs Homebrew bash, coreutils, util-linux). Linux and WSL2 are supported.
