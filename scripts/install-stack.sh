#!/usr/bin/env bash
# Idempotent: generates per-host .env (if missing) and brings up the Infisical
# docker-compose stack. Safe to re-run; keeps existing .env intact.

set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
STACK_DIR="$HERE/stack"
ENV_FILE="$STACK_DIR/.env"
ENV_TEMPLATE="$STACK_DIR/.env.template"
COMPOSE_FILE="$STACK_DIR/docker-compose.yml"

msg() { printf '\e[1;36m==>\e[0m %s\n' "$*"; }
die() { printf '\e[1;31m==>\e[0m %s\n' "$*" >&2; exit 1; }

command -v docker >/dev/null || die "docker required"
docker compose version >/dev/null 2>&1 || die "docker compose plugin required"
[[ -f "$COMPOSE_FILE" ]] || die "missing: $COMPOSE_FILE"

if [[ ! -f "$ENV_FILE" ]]; then
  [[ -f "$ENV_TEMPLATE" ]] || die "neither .env nor .env.template found in $STACK_DIR"
  msg "generating $ENV_FILE from template with fresh per-host keys"
  enc_key=$(openssl rand -hex 16)
  auth_secret=$(openssl rand -base64 32)
  db_pw=$(openssl rand -hex 12)
  sed \
    -e "s|__ENCRYPTION_KEY__|$enc_key|" \
    -e "s|__AUTH_SECRET__|$auth_secret|" \
    -e "s|__POSTGRES_PASSWORD__|$db_pw|" \
    "$ENV_TEMPLATE" > "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  msg "secrets written to $ENV_FILE (mode 0600) — do NOT commit this file"
else
  msg "$ENV_FILE already exists → leaving it alone"
fi

msg "docker compose up -d"
(cd "$STACK_DIR" && docker compose up -d)

msg "waiting for Infisical to answer on :8080"
for _ in $(seq 1 30); do
  code=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/api/status || true)
  if [[ "$code" == "200" ]]; then
    msg "Infisical up at http://localhost:8080 (HTTP 200)"
    exit 0
  fi
  sleep 2
done
die "Infisical did not become healthy in 60s — check: (cd $STACK_DIR && docker compose logs infisical)"
