#!/usr/bin/env bash
# Run a handful of agent-style probes through the installed Infisical guard hook
# and report which are blocked. Does NOT actually execute the commands — only
# pipes synthetic Bash-tool JSON into the hook to check the verdict.

set -uo pipefail

HOOK="${INFISICAL_HOOK:-$HOME/.claude/hooks/protect_infisical.py}"

if [[ ! -x "$HOOK" ]]; then
  echo "FAIL: hook not installed at $HOOK — run install-claude-hooks.sh first" >&2
  exit 1
fi

pass=0; fail=0

probe() {
  local expect="$1" cmd="$2"
  local payload
  payload=$(jq -nc --arg c "$cmd" '{tool_name:"Bash", tool_input:{command:$c}}')
  printf '%s' "$payload" | "$HOOK" >/dev/null 2>/dev/null
  local rc=$?
  local verdict="allow"
  [[ $rc -eq 2 ]] && verdict="BLOCK"
  if [[ "$verdict" == "$expect" ]]; then
    printf '  \e[32m✓\e[0m %-6s %-50s → %s\n' "$expect" "$cmd" "$verdict"
    pass=$((pass+1))
  else
    printf '  \e[31m✗\e[0m %-6s %-50s → %s (expected %s)\n' "$expect" "$cmd" "$verdict" "$expect"
    fail=$((fail+1))
  fi
}

probe_file() {
  local expect="$1" path="$2"
  local payload
  payload=$(jq -nc --arg p "$path" '{tool_name:"Read", tool_input:{file_path:$p}}')
  printf '%s' "$payload" | "$HOOK" >/dev/null 2>/dev/null
  local rc=$?
  local verdict="allow"
  [[ $rc -eq 2 ]] && verdict="BLOCK"
  if [[ "$verdict" == "$expect" ]]; then
    printf '  \e[32m✓\e[0m %-6s Read(%-45s) → %s\n' "$expect" "$path" "$verdict"
    pass=$((pass+1))
  else
    printf '  \e[31m✗\e[0m %-6s Read(%-45s) → %s (expected %s)\n' "$expect" "$path" "$verdict" "$expect"
    fail=$((fail+1))
  fi
}

echo "Bash probes:"
probe BLOCK  "infisical secrets --env=dev"
probe BLOCK  "infisical export --env=dev --format=dotenv"
probe BLOCK  "infisical run --env=dev -- env"
probe BLOCK  "infisical dynamic-secrets list"
probe BLOCK  "cat ~/.infisical/infisical-config.json"
probe BLOCK  "cat $HOME/infisical-keyring/user@example.com"
probe allow  "infisical --version"
probe allow  "infisical init"
probe allow  "echo hello"

echo
echo "Read probes:"
probe_file BLOCK "$HOME/.infisical/infisical-config.json"
probe_file BLOCK "$HOME/infisical-keyring/user@example.com"
probe_file allow "$HOME/some-project/README.md"

echo
echo "Summary: $pass passed, $fail failed"
[[ $fail -eq 0 ]] || exit 1
