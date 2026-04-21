#!/usr/bin/env bash
# Idempotent: installs the Infisical CLI into $HOME/.npm-global (no sudo).
# Adds the bin path to ~/.bashrc if missing. Re-runnable.

set -euo pipefail

PREFIX="${NPM_PREFIX:-$HOME/.npm-global}"

msg() { printf '\e[1;36m==>\e[0m %s\n' "$*"; }
die() { printf '\e[1;31m==>\e[0m %s\n' "$*" >&2; exit 1; }

command -v node >/dev/null || die "node required (install nodejs first)"
command -v npm  >/dev/null || die "npm required"

mkdir -p "$PREFIX"
npm config set prefix "$PREFIX" >/dev/null
export PATH="$PREFIX/bin:$PATH"

if command -v infisical >/dev/null && [[ "$(command -v infisical)" == "$PREFIX/bin/infisical" ]]; then
  current=$(infisical --version 2>&1 | awk '{print $NF}' | tr -d '\r')
  msg "Infisical CLI already installed: v$current — checking for updates"
  npm update -g @infisical/cli >/dev/null 2>&1 || true
else
  msg "Installing @infisical/cli to $PREFIX"
  npm install -g @infisical/cli >/dev/null
fi

msg "installed: $(infisical --version)"

# PATH line in ~/.bashrc (idempotent)
rc="$HOME/.bashrc"
line='export PATH="$HOME/.npm-global/bin:$PATH"'
if [[ -f "$rc" ]] && ! grep -qxF "$line" "$rc"; then
  printf '\n# added by vault/scripts/install-cli.sh\n%s\n' "$line" >> "$rc"
  msg "added PATH line to $rc (open a new shell to pick it up)"
fi
