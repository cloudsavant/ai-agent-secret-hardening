#!/usr/bin/env python3
"""
Infisical Guard PreToolUse Hook for Claude Code.

Blocks Bash/Read tool calls from the AI agent that would read Infisical secrets
or session material. Designed to run alongside protect_credentials.py; registered
in ~/.claude/settings.json under hooks.PreToolUse.

Escape hatch: if the environment variable INFISICAL_ALLOW_AGENT is set to "1"
when `claude` is launched, this hook allows everything. Use sparingly.
"""

import json
import os
import re
import sys

# -- tool-call patterns ------------------------------------------------------

# Bash subcommands that can exfiltrate secrets
BLOCKED_INFISICAL_SUBCMDS = r"(?:secrets|export|dynamic-secrets|run)\b"

# File-reading commands
_READ_CMDS = r"(?:cat|head|tail|less|more|source|\.(?:\s)|xxd|od|strings|grep|awk|sed)"

# Paths that contain Infisical session / keyring material
_INFISICAL_PATHS = r"(?:~/|/home/\w+/)(?:\.infisical(?:/[^\s'\"]*)?|infisical-keyring(?:/[^\s'\"]*)?)"

BLOCKED_BASH_PATTERNS = [
    # `infisical <dangerous-subcommand>`
    re.compile(rf"(?:^|[;&|`\s(]){{2,}}?infisical\s+{BLOCKED_INFISICAL_SUBCMDS}"),
    re.compile(rf"(?:^|[;&|`\s(])infisical\s+{BLOCKED_INFISICAL_SUBCMDS}"),
    # reading Infisical session / keyring files
    re.compile(rf"(?:^|[;&|`\s]){_READ_CMDS}\s+['\"]?{_INFISICAL_PATHS}"),
]

BLOCKED_FILE_PATTERNS = [
    re.compile(r".*[/\\]\.infisical[/\\].*"),
    re.compile(r".*[/\\]\.infisical$"),
    re.compile(r".*[/\\]infisical-keyring[/\\].*"),
    re.compile(r".*[/\\]infisical-keyring$"),
]

BLOCK_MESSAGE = """BLOCKED by protect_infisical.py: AI agents are not permitted to run
`infisical secrets|export|run|dynamic-secrets` or read Infisical session material.

Why: these commands return cleartext secrets. The human user should run them in
their own terminal when needed.

Escape hatch (use sparingly): restart Claude Code with
  INFISICAL_ALLOW_AGENT=1 claude
and this hook will permit everything for that session.

Hook source: vault/claude-hooks/protect_infisical.py"""


def is_blocked_bash(command: str) -> bool:
    if not command:
        return False
    return any(p.search(command) for p in BLOCKED_BASH_PATTERNS)


def is_blocked_file(file_path: str) -> bool:
    if not file_path:
        return False
    normalized = os.path.realpath(os.path.expanduser(file_path))
    return any(p.match(normalized) for p in BLOCKED_FILE_PATTERNS)


def main() -> None:
    if os.environ.get("INFISICAL_ALLOW_AGENT") == "1":
        sys.exit(0)

    try:
        data = json.loads(sys.stdin.read())
    except Exception:
        sys.exit(0)

    tool = data.get("tool_name", "")
    args = data.get("tool_input", {}) or {}

    if tool == "Bash" and is_blocked_bash(args.get("command", "")):
        print(BLOCK_MESSAGE, file=sys.stderr)
        sys.exit(2)

    if tool == "Read" and is_blocked_file(args.get("file_path", "")):
        print(BLOCK_MESSAGE, file=sys.stderr)
        sys.exit(2)

    sys.exit(0)


if __name__ == "__main__":
    main()
