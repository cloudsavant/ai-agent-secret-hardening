#!/usr/bin/env bash
# Idempotent installer: copies protect_infisical.py into ~/.claude/hooks/ and
# registers it as a PreToolUse hook for Read|Bash in ~/.claude/settings.json.
#
# Safe to re-run. Requires jq.

set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$HERE/claude-hooks/protect_infisical.py"
DEST_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
HOOK_DEST="$DEST_DIR/hooks/protect_infisical.py"
SETTINGS="$DEST_DIR/settings.json"

msg()  { printf '\e[1;36m==>\e[0m %s\n' "$*"; }
warn() { printf '\e[1;33m==>\e[0m %s\n' "$*" >&2; }
die()  { printf '\e[1;31m==>\e[0m %s\n' "$*" >&2; exit 1; }

command -v jq >/dev/null || die "jq required"
[[ -f "$SRC" ]] || die "source hook not found: $SRC"
[[ -d "$DEST_DIR" ]] || die "Claude config dir missing: $DEST_DIR"

## 1. install hook file
mkdir -p "$DEST_DIR/hooks"
install -m 0755 "$SRC" "$HOOK_DEST"
msg "installed hook → $HOOK_DEST"

## 2. patch settings.json idempotently
[[ -f "$SETTINGS" ]] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.bak.$(date +%s)"

tmp=$(mktemp)
jq --arg cmd "$HOOK_DEST" '
  .hooks //= {}
  | .hooks.PreToolUse //= []
  # find or create the Read|Bash matcher entry
  | (.hooks.PreToolUse | map(.matcher == "Read|Bash") | index(true)) as $idx
  | if $idx == null then
      .hooks.PreToolUse += [{matcher: "Read|Bash", hooks: [{type: "command", command: $cmd}]}]
    else
      .hooks.PreToolUse[$idx].hooks //= []
      | if (.hooks.PreToolUse[$idx].hooks | map(.command) | index($cmd)) == null then
          .hooks.PreToolUse[$idx].hooks += [{type: "command", command: $cmd}]
        else . end
    end
' "$SETTINGS" > "$tmp"

mv "$tmp" "$SETTINGS"
msg "registered hook in $SETTINGS"

## 3. report
echo
msg "current PreToolUse hooks:"
jq '.hooks.PreToolUse' "$SETTINGS"
echo
msg "Done. Restart Claude Code (new session) for the hook to take effect on agent tool calls."
