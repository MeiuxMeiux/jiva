# DEPLOY — maintainer runbook (static site on your own Apache host)

Agents never run ssh/rsync/deploy. A person runs `just deploy` (scripts/deploy.sh) or the steps below.
Put the host in a gitignored `deploy.env`: `JIVA_DEPLOY_HOST=jiva-deploy@your-server`.
Agents provide the build, the checks, and a read-only `just site-verify <url>` (curl only).

## Layout: atomic, static, reversible
```
/var/www/jiva.meiuxmeiux.com/
├─ releases/<git-sha>/        # one copy of site/build per release; keep the newest 5
└─ current -> releases/<sha>  # Apache DocumentRoot; swapped atomically
```
Vhost: `site/deploy/apache-jiva.conf` (canonical; security headers via `Header always set`).
`just site-check` fails if its CSP differs from the meta tag in site/src/index.html.

## One-time server prep (you, as root on your server)
1. Recon first, read-only: `apache2ctl -S`, `ss -tlnp`, `certbot certificates`, `df -h`;
   locally `dig +short jiva.meiuxmeiux.com A AAAA` (A → your server, no stale AAAA).
2. `a2enmod headers` (if not already on).
3. Optional deploy user: `adduser --disabled-password jiva-deploy`, make it the owner of
   `/var/www/jiva.meiuxmeiux.com`, and give it its own key, so day-to-day deploys stop using root.
4. `mkdir -p /var/www/jiva.meiuxmeiux.com/releases`, copy apache-jiva.conf to
   `/etc/apache2/sites-available/jiva.conf`, then `a2ensite jiva`.
5. `apache2ctl configtest`, then `systemctl reload apache2`. **Never restart**: other sites live here.
6. `certbot --apache -d jiva.meiuxmeiux.com`. It clones the vhost (headers included) into :443.

## Each release (you)
```
just site-check && just sec                       # local gates: build, check, secrets; all green
SHA=$(git rev-parse --short=12 HEAD); git status --porcelain site   # must be empty
rsync -a --delete site/build/ $JIVA_DEPLOY_HOST:/var/www/jiva.meiuxmeiux.com/releases/$SHA/
ssh $JIVA_DEPLOY_HOST "cd /var/www/jiva.meiuxmeiux.com && \
  ln -sfn releases/$SHA current.tmp && mv -T current.tmp current"
just site-verify https://jiva.meiuxmeiux.com      # every header, 200 /, 4xx /../, < 400 KB, SRI
```
Prune: on the server, `ls -1t releases`, then delete everything older than the newest 5. Never
delete the one `current` points at.

## Rollback (you)
`ssh $JIVA_DEPLOY_HOST "cd /var/www/jiva.meiuxmeiux.com && ls -1t releases"`, pick the previous
sha, then run the same `ln -sfn releases/<prev> current.tmp && mv -T current.tmp current` swap.
Then run `just site-verify https://jiva.meiuxmeiux.com`.

## Local rehearsal
`just site-dev` (it serves build/ and returns 404 for any `..` path), then
`just site-verify http://127.0.0.1:<port>`. With no vhost, HSTS/COOP/nosniff/etc. report
"skip (meta-only)"; CSP and Referrer-Policy are checked against their meta tags.
