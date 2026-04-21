#!/usr/bin/env bash
# Locks down Infisical session/keyring directories so only root (and the
# owning user via sudo) can read them. This is the filesystem-level defense
# that complements the Claude Code hook — even if the agent bypasses regex
# matching, it physically cannot open these files.
#
# Run as root (or via sudo) on each machine after `infisical login`.
# Idempotent and safe to re-run.

set -euo pipefail

msg()  { printf '\e[1;36m==>\e[0m %s\n' "$*"; }
warn() { printf '\e[1;33m==>\e[0m %s\n' "$*" >&2; }
die()  { printf '\e[1;31m==>\e[0m %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "must run as root (sudo $0)"

TARGET_USER="${1:-}"
[[ -n "$TARGET_USER" ]] || die "usage: sudo $0 <username>"

USER_HOME=$(eval echo "~$TARGET_USER") 2>/dev/null
[[ -d "$USER_HOME" ]] || die "home directory not found for user: $TARGET_USER"

lockdown_dir() {
  local dir="$1"
  if [[ -d "$dir" ]]; then
    chown -R root:"$TARGET_USER" "$dir"
    chmod 750 "$dir"
    find "$dir" -type f -exec chmod 640 {} \;
    find "$dir" -type d -exec chmod 750 {} \;
    msg "locked down $dir (owner=root, group=$TARGET_USER, mode=750/640)"
  else
    warn "not found (skipping): $dir"
  fi
}

# Infisical CLI config / session
lockdown_dir "$USER_HOME/.infisical"

# Infisical keyring material
lockdown_dir "$USER_HOME/infisical-keyring"

# Machine identity creds (servers)
if [[ -d /etc/infisical ]]; then
  chown -R root:root /etc/infisical
  chmod 700 /etc/infisical
  find /etc/infisical -type f -exec chmod 600 {} \;
  msg "locked down /etc/infisical (root-only, mode=700/600)"
fi

# Protect the hook itself from agent tampering
HOOK_FILE="$USER_HOME/.claude/hooks/protect_infisical.py"
if [[ -f "$HOOK_FILE" ]]; then
  chown root:"$TARGET_USER" "$HOOK_FILE"
  chmod 755 "$HOOK_FILE"         # readable+executable by all, writable only by root
  msg "write-protected $HOOK_FILE (owner=root, mode=755)"
fi

# Protect settings.json from agent self-patching
SETTINGS_FILE="$USER_HOME/.claude/settings.json"
if [[ -f "$SETTINGS_FILE" ]]; then
  chown root:"$TARGET_USER" "$SETTINGS_FILE"
  chmod 644 "$SETTINGS_FILE"     # readable by all, writable only by root
  msg "write-protected $SETTINGS_FILE (owner=root, mode=644)"
fi

echo
msg "filesystem lockdown complete for user '$TARGET_USER'"
msg "the user can still READ Infisical session via group perms,"
msg "but AI agents writing code cannot open root-owned files."
msg ""
msg "NOTE: after 'infisical login' you may need to re-run this script"
msg "      since login recreates session files as the user."
