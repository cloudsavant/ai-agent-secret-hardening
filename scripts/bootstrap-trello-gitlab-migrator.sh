#!/usr/bin/env bash
# Idempotent bootstrap for moving trello-gitlab-migrator secrets into Infisical.
# Automates everything except: (a) logging into Infisical, (b) creating the
# project in the UI, (c) minting the three tokens upstream, (d) the migrate.py
# code patch. Those stay manual — they're either one-time UI clicks or code
# changes that want review.

set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-../trello-gitlab-migrator}"
INFISICAL_ENV="${INFISICAL_ENV:-dev}"

msg()  { printf '\e[1;36m==>\e[0m %s\n' "$*"; }
warn() { printf '\e[1;33m==>\e[0m %s\n' "$*" >&2; }
die()  { printf '\e[1;31m==>\e[0m %s\n' "$*" >&2; exit 1; }

## 0. prereqs
command -v infisical >/dev/null || die "infisical CLI not on PATH"
command -v python3   >/dev/null || die "python3 required for config.json patch"
[[ -d "$PROJECT_DIR" ]] || die "PROJECT_DIR not found: $PROJECT_DIR"

cd "$PROJECT_DIR"

## 1. ensure the repo is linked to an Infisical project
if [[ ! -f .infisical.json ]]; then
  msg "No .infisical.json found — launching interactive \`infisical init\` (one-off)"
  infisical init
else
  msg ".infisical.json already present → skipping init"
fi

## 2. push placeholder secrets (real values get pasted in the Infisical UI)
PLACEHOLDER="REPLACE_IN_INFISICAL_UI"
msg "Writing placeholder secrets to env=$INFISICAL_ENV (value: $PLACEHOLDER)"
infisical secrets set --env="$INFISICAL_ENV" \
  GITLAB_TOKEN="$PLACEHOLDER" \
  TRELLO_API_KEY="$PLACEHOLDER" \
  TRELLO_API_TOKEN="$PLACEHOLDER" >/dev/null
warn "These are placeholders — open the Infisical UI and paste the real values before running migrate.py"

## 3. strip plaintext tokens from config.json / config.example.json
msg "Scrubbing token fields from config*.json"
python3 - <<'PY'
import json, pathlib
for name in ("config.json", "config.example.json"):
    p = pathlib.Path(name)
    if not p.exists():
        continue
    c = json.loads(p.read_text())
    changed = False
    for path in (("gitlab", "token"), ("trello", "api_key"), ("trello", "api_token")):
        node = c
        for k in path[:-1]:
            node = node.get(k) if isinstance(node, dict) else None
            if node is None:
                break
        if isinstance(node, dict) and path[-1] in node:
            node.pop(path[-1])
            changed = True
    if changed:
        p.write_text(json.dumps(c, indent=2) + "\n")
        print(f"  scrubbed: {name}")
PY

## 4. .gitignore hygiene
msg "Updating .gitignore"
touch .gitignore
for entry in ".infisical.json" "config.json"; do
  grep -qxF "$entry" .gitignore || echo "$entry" >> .gitignore
done

## 5. smoke test — confirms injection works, even with placeholders
msg "Smoke test — all three secrets should print PRESENT (placeholder value)"
infisical run --env="$INFISICAL_ENV" -- python3 -c '
import os
for k in ("GITLAB_TOKEN", "TRELLO_API_KEY", "TRELLO_API_TOKEN"):
    v = os.environ.get(k)
    print(k, "PRESENT" if v else "MISSING", "(placeholder)" if v == "REPLACE_IN_INFISICAL_UI" else "")
'

msg "Done. Next steps:"
echo "    1. Open Infisical UI → project trello-gitlab-migrator → env=$INFISICAL_ENV"
echo "       → replace the three REPLACE_IN_INFISICAL_UI values with real tokens"
echo "    2. Patch migrate.py to read from os.environ (see EXAMPLE-trello-gitlab-migrator.md §2)"
echo "    3. Run:  infisical run --env=$INFISICAL_ENV -- python3 migrate.py config.json"
