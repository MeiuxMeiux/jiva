> Original design brief (historical; may be out of date).

# JIVA — kickoff brief

> Written for the first session in the repo (the "desk"). For current behaviour: README.md, docs/QUICKSTART.md, `jiva help`.

## Status 2026-10-13
- Runs: bash + just runtime (`bin/jiva`, `core/`) on a private `tmux -L jiva` server: watchdog, boss, workers,
  file-bus verbs, typed asks, breakers, rotation, dashboard, roster, local plugin. Build state: `docs/history/PLAN.md` "Build order".
- Start: `jiva up [workers]` from the target repo (`jiva status`, `jiva doctor`, `jiva down`); `jiva help` / `just --list` are the truth.
- Facts live in `notes/<area>.md` (core, plugin, site, …); this brief below is history, not current state.
- Done by a person, not an agent: deploy the site (`docs/DEPLOY.md`), install the plugin into ~/.claude (`just plugin install`),
  restart the fleet (`jiva down` then `jiva up`), and the one-time trust dialog / `! just keepalive`.

## 0. What JIVA is (one paragraph, also the portable blurb seed)

JIVA (Sanskrit *jīva*: a living soul that keeps being reborn) runs many Claude Code sessions in parallel from **one** terminal. The **desk** is the only session the human talks to; every permission, decision and `!` command bubbles there. The desk launches a **boss** in a private tmux server, and the boss orchestrates N **workers** (models are configurable). Every session, desk included, is rebuilt from a ≤40-line handoff before ~200k tokens, so context never rots. Agents share one checkout and avoid collisions through directory claims instead of worktrees. They drive the repo through `just` recipes, commit and push on milestones, and are throttled by non-LLM breakers so nothing loops and burns tokens. Names and avatars are cosmetic labels, never personalities.

The architecture plan is in `docs/history/PLAN.md`. Read it only when a task touches core runtime work.

## 1. Ground rules for this repo (enforce from commit one)

- **Secrets.** API keys live in a local keys directory outside the repo (`JIVA_KEYS_DIR`). Never `cat`, `echo` or print them, because Claude Code stores Bash output in `~/.claude/projects/*` transcripts. Scripts read them internally (inside the script, never as a command-line argument); `scripts/keys.sh` holds the *paths*, never the values. Install `gitleaks` as a pre-commit hook before the first push.
- **No copyrighted art in git history, ever.** Private test avatars go in `packs/local/` (gitignored), and the public site uses only original generated art.
- **Asks bubble up.** Anything that touches the server, pushes to the remote, creates a GitHub repo, or spends more than $2 on image generation stops and asks the human at the desk.
- **Files stay ≤150 lines.** Prefer `just <recipe>` over ad-hoc multi-step shell. When you repeat a sequence twice, propose a recipe.

## 2. Repo layout

```
jiva/
├─ CLAUDE.md            # ≤8 lines: "run `just --list`; read docs/ only on demand; area notes in notes/"
├─ justfile             # root: imports site/, core/, sec/ modules
├─ docs/                # QUICKSTART.md, DEPLOY.md; history/ (this brief, PLAN.md)
├─ notes/               # per-area durable facts, ≤30 lines each (site.md, core.md, deploy.md)
├─ core/                # Go runtime later (cmd/jiva, internal/…); empty stub for now
├─ plugin/              # Claude Code plugin (hooks, skills, statusline) — later
├─ site/
│  ├─ src/              # index.html, css/, js/ (vanilla), fonts/ (self-hosted, OFL)
│  ├─ art/
│  │  ├─ prompts.yaml   # every asset: id, model, prompt, size, transparent, budget
│  │  ├─ raw/           # gitignored: every generation, cached by prompt hash
│  │  └─ final/         # committed: chosen + post-processed assets
│  ├─ build/            # gitignored output (hashed, minified)
│  └─ deploy/           # nginx/caddy vhost snippet, security headers, robots.txt
├─ scripts/             # art-gen, art-post, build, keys.sh — small, single-purpose
├─ packs/local/         # gitignored private test roster — never committed
└─ .jiva/               # gitignored runtime state (bus, claims, state.json, STOP)
```

## 3. Repository (do first, after asking)

Create the GitHub repo and push only after asking the human. Add `.gitignore` (raw/, build/, packs/local/, .jiva/, *.key, .env*) and the gitleaks hook **before** the first push.

## 4. The website — jiva.meiuxmeiux.com on the maintainer's server

### 4a. Server recon (read-only, first)
`just server-audit` should run only read-only commands over ssh to the deploy host (`$JIVA_DEPLOY_HOST` from gitignored deploy.env): OS, which of nginx/caddy/apache is running, existing vhosts, certbot presence, open ports (`ss -tlnp`), firewall, disk. It also runs `dig +short jiva.meiuxmeiux.com A AAAA` locally to confirm the A record resolves to that host and that no stale AAAA exists. The server likely hosts other things. **Never restart the web server.** Validate the config (`nginx -t`) and then reload.

Recommend (ask before doing it) a `jiva-deploy` user whose SSH key can write only to `/var/www/jiva.meiuxmeiux.com/`, so day-to-day deploys stop using root.

### 4b. Deploy model: atomic, static, reversible
```
/var/www/jiva.meiuxmeiux.com/
├─ releases/<git-sha>/   # rsync'd build
└─ current -> releases/<git-sha>
```
`just deploy` runs build, then check, then sec, then rsync to a new release dir, then swaps the symlink with `ln -sfn` and `mv -T`, then runs `deploy-verify`. Keep the last 5 releases. `just rollback` re-points the symlink. TLS uses certbot (or Caddy's automatic HTTPS if Caddy is already running). Deploys bubble a ship notice to the desk.

### 4c. Security headers (in the vhost, not meta tags)
- Strict CSP: `default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' data:; font-src 'self'; connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'`. No inline JS or CSS, and no third-party CDN on the marketing site. Self-host fonts so nothing leaks visitor IPs.
- HSTS (start at a short max-age, raise later), `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`, a `Permissions-Policy` that denies everything, `Cross-Origin-Opener-Policy: same-origin`.
- No server-side code, forms, cookies or analytics. A static site leaves nothing to attack.

### 4d. Scans (`just sec`)
gitleaks (whole history) · trivy fs · `deploy-verify` runs curl -I header assertions, testssl.sh, the MDN HTTP Observatory score, lychee link check, html-validate, and a page-weight budget (aim for under 400 KB on first load, art included). Fail the deploy on any red result.

## 5. Art pipeline — models (as checked in Oct 2026; catalogs change)

| Job | Model | Why |
|---|---|---|
| Favicon, logo mark, icon pack, button shapes, dividers | **Recraft V4 Vector** (`recraft/recraft-v4-vector`, OpenRouter, ~$0.08/image, returns SVG); Pro Vector for the hero logo only | True SVG means real cut-out silhouettes that scale and can be recolored to the exact palette tokens in a script |
| Hero/banner illustration, "soul" avatars, raster cut-outs | **GPT Image 2** (`openai/gpt-image-2`) with `background: "transparent"` + `output_format: "png"`/`"webp"` | Real alpha channel. Transparency is still marked preview, and the prompt must **not** describe any backdrop. Draft at low quality, final at high. |
| Cheap drafts / alt cut-outs | **Qwen-Image-2.1** (native alpha, released Sep 20 2026) or anything cheap or free on ImageRouter | Check ImageRouter's live catalog (`GET https://api.imagerouter.io/v1/models`; the API is OpenAI-compatible at `/v1/openai`) |

On OpenRouter, list image models via `GET /api/v1/images/models`. Failed image requests are not billed there.

**Pipeline rules (these double as loop and spend protection):**
- Cache by `sha256(model+prompt+size+seed)` in `art/raw/`, so a cache hit never re-bills. Keep a running spend total in `art/raw/ledger.tsv`. Stop hard at the budget in `prompts.yaml` (default $10 total) and ask the desk for more.
- At most 3 variants per asset per run. The human picks winners into `final/` with `just art-pick <id> <n>`.
- Post-process (`just art-post`):
  - **SVG:** run SVGO, snap fills to the palette tokens, and strip any background `<rect>`.
  - **Raster:** assert alpha (`magick identify -format %A`), trim, and export AVIF + WebP + PNG.
- Derived set: `favicon.svg` (with a `prefers-color-scheme` block), 32px PNG, 180px apple-touch, 192/512 maskable, `site.webmanifest`.
- The OG card (1200×630) stays **opaque**: composite it on `#060128`.
- Button "images" are decorative SVG shapes used as CSS `mask-image`/`clip-path` backgrounds. **Labels stay real HTML text** for accessibility and SEO. Never bake words into button art.

**Shape language:** chamfered and notched corners, offset-cut polygons, a single "notch" motif reused everywhere (logo, buttons, section dividers, avatar frames). Nothing plain-round, plain-square or pill-shaped.

## 6. Design brief — "make it not look AI-made"

Palette (CSS tokens, dark only):
```css
--text:#f0e2e2; --background:#060128; --primary:#ef4fbc; --secondary:#00ffd8; --accent:#21ff00;
```
- **Primary pink:** CTAs and the logo.
- **Secondary cyan:** live and data elements (terminal cursor, token counters).
- **Accent green:** only for "healthy / alive" signals and tiny highlights. It is extremely loud on navy, so never use it on large areas.
- Pure `#000` exists only as a deep-shadow layer, if anywhere.

**Avoid (these are the AI-site tells):** a centered hero (H1, subhead, two buttons), three-card feature grids, purple-blue gradient blobs, glassmorphism everywhere, emoji bullets, "Supercharge / Unleash / Seamless" copy, an Inter-only stack, and stock "AI brain" imagery.

**Do:**
- **Grid and type:** an asymmetric editorial grid with hard alignment. Pair a characterful display face with a real monospace (self-hosted, OFL licensed; for example Bricolage Grotesque or Unbounded with JetBrains Mono or Monaspace; pick one pair and commit).
- **Dogfooded hero:** the hero is a **real recording** of a JIVA session (a tmux status bar reading `5 live · 0 flag · 412k`, souls spawning and reincarnating), rendered as an animated SVG or CSS rather than a video.
- **Copy:** written in the builder's voice, short and specific, with real numbers.
- **Motion:** one signature motion, a soul "reincarnating" (dissolve, then re-form through the notch shape). Respect `prefers-reduced-motion`.

**Page outline:**
1. Hero: one terminal, many souls.
2. The problem: tab sprawl and context rot.
3. How it works: a desk → boss → workers diagram as inline SVG.
4. Reincarnation: handoffs and the ~200k ceiling.
5. Asks bubble: the one-terminal promise.
6. The watchdog view: a static, clearly labeled sample of the dashboard.
7. "Built with itself": the ouroboros.
8. Install: clone from git and put `bin/` on PATH (an npx installer was considered and dropped).
9. Footer.

## 7. Starter justfile recipes

Planned: `init`; `art-models|gen|pick|post`; `site-dev|build|check`; `sec`, `server-audit`, `deploy`,
`deploy-verify`, `rollback`. The six agent verbs (`j-inbox`, `j-claim`, `j-report`, `j-ask`, `j-ship`,
`j-handoff`) were to follow once the core spike passed. Today `just --list` is the truth.

## 8. Order of work (tonight → this week)

1. **Hygiene.** Save the plan and this brief into `docs/`, write CLAUDE.md, `.gitignore` and the gitleaks hook. Run `just init`. *(ask)* Create the GitHub repo and push.
2. **Recon.** Run `just server-audit` and `just art-models`. Report findings to the human in under 15 lines.
3. **Art round 1** (≤$5): logo mark, notch motif, favicon, 8 icons. The human picks winners.
4. **Site v0** behind `site-dev`, then `just deploy` *(ask)* once headers and TLS pass.
5. **Core spike** (the 5 pass/fail checks from the plan) runs in parallel, because `site/` and `core/` are separate claims. That makes this the first real dogfood split: one worker on `site/`, one on `core/`, with the desk coordinating until the boss exists.

## 9. Defaults chosen (flip any)
- Static vanilla site with a tiny build script, no framework.
- Self-hosted fonts, no CDN on the marketing site.
- Atomic symlink deploys over rsync.
- A dedicated deploy user, proposed.
- $10 total art budget.
- Recraft V4 Vector for anything shape-like, GPT Image 2 transparent for illustration.
