# plugin (Claude Code 2.1.296)
- Install needs a marketplace; `claude plugin install <path>` doesn't exist. plugin/ is its own
  marketplace (`.claude-plugin/marketplace.json`, name jiva-local, source "./"): `plugin/install.sh install`
  = `marketplace add <plugin dir>` + `install jiva@jiva-local --scope user`.
- Local-folder marketplace, relative source: `Read from:` the checkout; after edits
  run `/reload-plugins`. No reinstall or version bump needed.
- `claude plugin details <name>` only takes installed names. For an uninstalled folder, use `--plugin-dir`.
- Classic `hooks/hooks.json` (event → command hooks, `${CLAUDE_PLUGIN_ROOT}`) still works alongside the
  newer TS "mods" (`{"modules": [...]}`). Wrappers source hooks/_exec.sh → exec core/hooks/<same>.sh;
  JIVA_HOME comes from env, else the plugin's parent dir. core/lib.sh then re-derives it from the core path.
- Skills may be symlinks (validate warns+skips; sessions follow them): SKILL.md → core/roles/*.md, no frontmatter
  (~20 tok desc). NEVER sed -i/open('w') them (breaks mode 120000); `check.sh skills` FAILs on any non-link.
- CAN'T: own `statusLine`. Plugin settings.json isn't read for it (validate ignores the file). Manual line:
  `"statusLine": {"type":"command","command":"<checkout>/plugin/hooks/statusline.sh"}` (install.sh prints it).
  Alternative: a TS mod calling `$.ui.status()` (needs `$.process` to run the script; not done).
- No `jiva`-on-PATH install: the plugin does not put bin/ on PATH. /jiva-inbox needs `jiva` on PATH.
- Test without touching real settings: `CLAUDE_CONFIG_DIR=<scratch>` for install/details. `claude -p` there
  says "Not logged in", so prove hooks with `claude -p --plugin-dir plugin/` under the real login.
- Hooks mode (core/lib.sh hooks_mode): `jiva up`/spawn/respawn render $J/settings.json WITHOUT "hooks"
  (statusLine only) when `jiva plugin status` exits 0, else full hooks; `up` prints "hooks: plugin|settings".
  JIVA_HOOKS=plugin|settings overrides. Never installs/uninstalls as a side effect.
- `plugin/install.sh status` reads $CLAUDE_CONFIG_DIR/plugins/installed_plugins.json (scope user) +
  settings.json enabledPlugins (false = off); no `claude` call. `jiva doctor plugin` round-trips in a scratch
  CLAUDE_CONFIG_DIR. Installing into the real ~/.claude is the keeper's call (`just plugin install`).
- Local install copies into plugins/cache/jiva-local/jiva/<ver> (installPath), not the checkout.
- Wrappers: pane env (cmdline) carries JIVA_HOME/TARGET/ROLE/NAME; core hooks take TARGET from
  CLAUDE_PROJECT_DIR first. perm-relay.sh wrapper exists, opt-in (not in hooks.json).
- check.sh runs `claude plugin validate plugin/` when claude is on PATH (symlink-skill warning is expected).
- Drift: `plugin/check.sh` FAILs if plugin/**/*.md (symlinked skills too) names a `jiva <sub>`/`just <recipe>` the CLI lacks; WARNs on unmentioned verbs.
- Verb tables: each role card (core/roles/*.md) ends with "## Verbs you use" (verb · when); keeper verbs live in commands/jiva-desk.md. check.sh WARNs on any `jiva help` verb none names; ALLOW stays empty.
