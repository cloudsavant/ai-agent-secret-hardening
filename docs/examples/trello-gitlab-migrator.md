# Example: `trello-gitlab-migrator` → Infisical

Smaller worked example — one-shot script, two (really three) API tokens, no long-running service. Good first migration after the POC.

> **TL;DR (automated path):** create the Infisical project in the UI, then run `./scripts/bootstrap-trello-gitlab-migrator.sh` from the vault repo. It handles steps 1, 3, 4, 6 below. Steps 2 (code patch) and 5 (doc update) stay manual. See [scripts/bootstrap-trello-gitlab-migrator.sh](scripts/bootstrap-trello-gitlab-migrator.sh).

## Secrets in scope

| Name | Where it lives today | Notes |
|---|---|---|
| `GITLAB_TOKEN` | Plaintext in `config.json` → `gitlab.token` | Per instructions in `get_gitlab_token.md` |
| `TRELLO_API_KEY` | **Missing from the project** | App-level key from <https://trello.com/app-key> |
| `TRELLO_API_TOKEN` | **Missing from the project** | User-level OAuth-ish token generated off the API key |

The script currently reads a local Trello backup dump (`trello.backup_dir`), so Trello creds were never wired in — but they're needed for any live API use and should be provisioned now so the config shape is future-proof.

## 1. Add the three secrets in Infisical

Create project `trello-gitlab-migrator` in the UI, then:

```bash
cd path/to/trello-gitlab-migrator
infisical init                              # pick the new project → writes .infisical.json
echo .infisical.json >> .gitignore          # optional, contains project/env refs only

infisical secrets set --env=dev \
  GITLAB_TOKEN='<paste-from-gitlab-ui>' \
  TRELLO_API_KEY='<from-trello.com/app-key>' \
  TRELLO_API_TOKEN='<generated-trello-token>'
```

Verify:

```bash
infisical secrets --env=dev | grep -E '^(GITLAB_TOKEN|TRELLO_)'
```

## 2. Change `migrate.py` to read tokens from env, not config

Strip the secret fields from `config.json` and have the script pull them from the process env. Rough shape (adjust to actual code):

```python
import os, json, sys

with open(sys.argv[1]) as f:
    config = json.load(f)

# Inject secrets from env — fail loud if missing
for key in ("GITLAB_TOKEN", "TRELLO_API_KEY", "TRELLO_API_TOKEN"):
    if key not in os.environ:
        sys.exit(f"Missing env var: {key} (run via `infisical run`)")

config["gitlab"]["token"] = os.environ["GITLAB_TOKEN"]
config.setdefault("trello", {})["api_key"] = os.environ["TRELLO_API_KEY"]
config["trello"]["api_token"] = os.environ["TRELLO_API_TOKEN"]
```

## 3. Clean up `config.json` / `config.example.json`

Remove the `token` field from `config.json` entirely (not just blank it):

```bash
python3 -c "
import json, pathlib
for p in ['config.json', 'config.example.json']:
    fp = pathlib.Path(p)
    if not fp.exists(): continue
    c = json.loads(fp.read_text())
    c.get('gitlab', {}).pop('token', None)
    c.get('trello', {}).pop('api_key', None)
    c.get('trello', {}).pop('api_token', None)
    fp.write_text(json.dumps(c, indent=2))
"
```

And add `config.json` to `.gitignore` if it was previously tracked — it may still hold non-secret per-user data but it's safest to treat it as local-only now.

## 4. Run under Infisical

Replace the old invocation:

```bash
# Before
python3 migrate.py config.json

# After
infisical run --env=dev -- python3 migrate.py config.json
```

Dry-run smoke test first — it should print 3 injected secrets and proceed:

```bash
infisical run --env=dev -- python3 -c \
  "import os; [print(k, 'OK' if os.environ.get(k) else 'MISSING') for k in ('GITLAB_TOKEN','TRELLO_API_KEY','TRELLO_API_TOKEN')]"
```

Expected:

```text
GITLAB_TOKEN OK
TRELLO_API_KEY OK
TRELLO_API_TOKEN OK
```

## 5. Update `get_gitlab_token.md`

The current file ends with `export GITLAB_TOKEN=...` and a `python3 -c` that writes the token into `config.json`. That whole section is now wrong — replace it with:

```bash
# After creating the token in the GitLab UI:
infisical secrets set --env=dev GITLAB_TOKEN='<paste-token>'
infisical run --env=dev -- python3 migrate.py config.json
```

## 6. Token rotation drill (prove the value)

When a token is revoked upstream:

1. Mint a new one in the GitLab / Trello UI
2. `infisical secrets set --env=dev GITLAB_TOKEN=<new>`
3. Next run picks it up — no code change, no file edit, no restart (for short-lived scripts; a long-running daemon would need a SIGHUP or restart)

## Rollback

If Infisical is down, temporarily export the three vars in the shell and run the script directly — it will see them in the env just the same:

```bash
export GITLAB_TOKEN=... TRELLO_API_KEY=... TRELLO_API_TOKEN=...
python3 migrate.py config.json
```
