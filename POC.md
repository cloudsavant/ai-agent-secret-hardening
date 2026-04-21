# Infisical Local POC

Minimal self-hosted Infisical stack on the dev laptop to validate the `infisical run` injection workflow before committing to the full 4-hour rollout.

> **Before using this on any machine with an AI coding agent, read [HARDENING.md](HARDENING.md) and run `scripts/install-claude-hooks.sh`.** A logged-in Infisical CLI session is fully readable by any agent running as your user — the hooks are what block that, not Infisical itself.

## Stack

Docker Compose on localhost:

- `infisical/infisical:latest-postgres` — standalone backend + frontend, exposed on <http://localhost:8080>
- `postgres:16-alpine` — internal only (host 5432 is in use)
- `redis:7-alpine` — internal only

Files (under `stack/`):

- `stack/docker-compose.yml` — service definitions
- `stack/.env` — `ENCRYPTION_KEY`, `AUTH_SECRET`, Postgres creds, `SITE_URL` (gitignored)
- `stack/.env.template` — committed template; `scripts/install-stack.sh` generates `.env` from it with fresh per-host keys
- `stack/pg-data/`, `stack/redis-data/` — bind-mounted volumes (created on first `up`)

## Bring up / tear down

```bash
cd path/to/vault/stack
docker compose up -d
docker compose ps
docker compose logs -f infisical
docker compose down          # stop, keep data
docker compose down -v       # stop, wipe data
```

Or, from any directory, use the installer which handles `.env` generation too: `scripts/install-stack.sh`.

Health check: `curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080/api/status` → `200`.

## CLI

Installed via npm to a user prefix (no sudo):

```bash
mkdir -p ~/.npm-global
npm config set prefix "$HOME/.npm-global"
npm install -g @infisical/cli
# PATH export added to ~/.bashrc:
#   export PATH="$HOME/.npm-global/bin:$PATH"
infisical --version   # 0.43.76
```

Package: [`@infisical/cli`](https://www.npmjs.com/package/@infisical/cli). The official Debian repo (`artifacts-cli.infisical.com`) is the documented path but needs sudo; npm avoids that for a POC.

## First-run workflow

1. Browser → <http://localhost:8080> → sign up admin account (local only, any email/password)
2. Create project `poc`, add secret `POC_TOKEN=hello-from-infisical` in the `Development` env
3. Terminal:

   ```bash
   cd path/to/vault
   infisical login                       # choose Self Hosted, domain http://localhost:8080
   infisical init                        # pick the poc project → writes .infisical.json
   infisical run --env=dev -- printenv POC_TOKEN
   ```

   Expected: `hello-from-infisical` printed to stdout, with nothing written to disk.

## Success criteria

- [x] UI reachable at <http://localhost:8080>
- [x] Admin account created
- [x] Secret added in `dev` env
- [x] `infisical run --env=dev -- printenv POC_TOKEN` prints the value
- [x] No plaintext secret in `.env`, shell history, or `.infisical.json`

**Verified 2026-04-21:**

```text
$ infisical run --env=dev -- printenv POC_TOKEN
2026-04-21T07:56:33+02:00 INF Injecting 1 Infisical secrets into your application process
hello-from-infisical
```

## Secrets / key material

Generated once for the POC (stored in `.env`, not committed):

- `ENCRYPTION_KEY` — 32-char hex (`openssl rand -hex 16`)
- `AUTH_SECRET` — base64 32 bytes (`openssl rand -base64 32`)

These must **not** be reused in the NAS/NUC or prod deployment — regenerate per environment.

## Known caveats

- Postgres port 5432 is already bound on the host; the container's Postgres is not published (internal network only). If you need external DB access for debugging, add `ports: ["5433:5432"]` temporarily.
- `latest-postgres` tag drifts; before prod, pin to a specific Infisical version.
- Telemetry disabled via `TELEMETRY_ENABLED=false`.

## Worked examples

- [docs/examples/trello-gitlab-migrator.md](docs/examples/trello-gitlab-migrator.md) — **start here**, simpler one-shot script: `GITLAB_TOKEN` + `TRELLO_API_KEY` + `TRELLO_API_TOKEN` (last two were missing from the project and get provisioned fresh).

## Migration path (POC → NAS/NUC or Cloud)

1. Export data: `docker compose exec db pg_dump -U infisical infisical > infisical.sql`
2. Stand up target stack (same compose, regenerated `ENCRYPTION_KEY`/`AUTH_SECRET`, point `SITE_URL` at the new host)
3. `psql` the dump in — but note: secrets are encrypted with the old `ENCRYPTION_KEY`, so keep that key or re-enter secrets on the new instance
4. Update CLI: `infisical login` against the new domain, re-run `infisical init` in each project

For Infisical Cloud: skip the dump, just re-enter secrets via the UI/CLI — keys differ anyway and the dataset is small at POC stage.
