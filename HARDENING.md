# Hardening: keeping AI agents out of Infisical

> **This is the critical layer.** Infisical on its own gives you rotation, revocation, and audit — but **not** protection against a locally-running AI coding agent. An agent running in your shell inherits your Infisical login and can read every secret. The defenses below sit at the agent layer (Claude Code hooks), not the Infisical layer, and must be installed on every machine where an AI coding agent runs.

## Threat model

What an AI agent with a normal user shell can do to a logged-in Infisical CLI session:

```bash
infisical secrets --env=dev --plain           # print everything
infisical export --env=dev --format=dotenv    # dump to disk
infisical run --env=dev -- env                # inject + dump via subprocess
cat ~/.infisical/infisical-config.json        # read session metadata
cat ~/infisical-keyring/$USER                 # encrypted blob, but the passphrase sits next to it
```

None of these are prevented by Infisical — they're legitimate CLI features. The agent looks identical to the authenticated human.

## Defense layers (in priority order)

### 1. Claude Code PreToolUse hook — blocks agent tool calls

A Python hook at `~/.claude/hooks/protect_infisical.py` intercepts `Bash` and `Read` tool calls from the agent and refuses any that would touch Infisical secret material. Managed via `~/.claude/settings.json`. Escape hatch: set `INFISICAL_ALLOW_AGENT=1` in the shell *before* launching `claude` for the rare case you want the agent to drive.

Blocked Bash patterns:

- `infisical secrets …`
- `infisical export …`
- `infisical dynamic-secrets …`
- `infisical run …` (yes, all of it — agents can write code, users run it)
- `cat|head|tail|less|source` of `~/.infisical/*`, `~/infisical-keyring/*`

Blocked Read tool paths:

- `~/.infisical/**`
- `~/infisical-keyring/**`

Canonical copy: [claude-hooks/protect_infisical.py](claude-hooks/protect_infisical.py). Installer: [scripts/install-claude-hooks.sh](scripts/install-claude-hooks.sh). Probe suite: [scripts/verify-hardening.sh](scripts/verify-hardening.sh).

### 2. Filesystem lockdown — agents physically can't open secret files

The hook (layer 1) is regex-based and can be bypassed by an agent writing custom Python or using indirect reads (`base64 <`, `python3 -c "open(…).read()"`). Filesystem permissions close that gap: if the Infisical session files are root-owned, no user-level code can open them — regardless of how creative the agent gets.

Run once after `infisical login` (and re-run after each new login, since it recreates session files):

```bash
sudo scripts/lockdown-infisical-paths.sh <username>
```

What it does:

- `~/.infisical/` → `root:<user>` owner, mode `750/640` (user can read via group, agent code running as user can read too — but combined with the hook, the agent never gets to execute the read)
- `~/infisical-keyring/` → same treatment
- `/etc/infisical/` → `root:root`, mode `700/600` (machine identity creds, fully isolated)
- `~/.claude/hooks/protect_infisical.py` → `root:<user>`, mode `755` (agent can't overwrite the hook)
- `~/.claude/settings.json` → `root:<user>`, mode `644` (agent can't disable its own hooks)

**Important:** after running this, `infisical login` will fail because it needs to write to `~/.infisical/`. Temporarily restore ownership (`sudo chown -R $USER ~/.infisical`), log in, then re-run the lockdown script.

Installer: [scripts/lockdown-infisical-paths.sh](scripts/lockdown-infisical-paths.sh).

### 3. Claude Code sandbox — network and filesystem isolation

Claude Code supports a `--sandbox` flag that restricts the agent's filesystem and network access at the OS level (not just via hooks). This is the strongest local defense — even if the agent bypasses hooks AND permissions, the sandbox prevents it from reaching secret paths or exfiltrating data over the network.

Enable it when launching Claude Code:

```bash
claude --sandbox
```

Or set it permanently in `~/.claude/settings.json`:

```json
{
  "permissions": {
    "sandbox": true
  }
}
```

Use sandbox mode as the outermost fence. The hook catches known patterns (fast, informative error messages), filesystem perms stop unknown patterns, and the sandbox stops everything else.

### 4. Machine identities — apps don't inherit your human login

Don't let long-running services (app servers, CI jobs, cron) authenticate as "you logged in on this laptop." Create a **Machine Identity** per host in the Infisical UI, scope it to one project + one env, and hand the host a client-ID / client-secret pair stored in a root-owned file (`0600`, outside any dev-user home). The application uses those to fetch secrets; the AI agent, running as your user, has no path to that file.

Rollout pattern:

```bash
# On the target host, as root:
install -m 0600 -o root -g root /dev/stdin /etc/infisical/<project>.env <<EOF
INFISICAL_MACHINE_IDENTITY_CLIENT_ID=...
INFISICAL_MACHINE_IDENTITY_CLIENT_SECRET=...
EOF

# systemd unit references it:
#   EnvironmentFile=/etc/infisical/<project>.env
#   ExecStart=/usr/local/bin/infisical run --projectId=... --env=prod -- /opt/<app>/run.sh
```

The laptop keeps a logged-in user session for admin work (editing secrets in the UI, rotating) — but no production app runs off that session.

### 5. Audit + short TTLs — safety net

Infisical's UI shows every secret read with timestamp, source IP, identity. Treat that as the tripwire: rotate any token touched by an unexpected source, and keep TTLs short enough (24h–7d for high-blast-radius tokens) that exfiltration has a narrow useful window.

### 6. Machine identity rotation procedure

Machine identity client secrets don't auto-rotate — plan for manual rotation on a schedule (90 days recommended for production).

**Rotation steps:**

1. In Infisical UI → Machine Identities → select identity → **Regenerate Client Secret** (old secret stays valid until you revoke it)
2. On the target host, as root, update the credential file:
   ```bash
   # edit /etc/infisical/<project>.env with the new client secret
   sudo vi /etc/infisical/<project>.env
   ```
3. Restart the service that uses it: `sudo systemctl restart <service>`
4. Verify the service is healthy and reading secrets correctly
5. Back in Infisical UI → **Revoke** the old client secret
6. Log the rotation in your ops channel / runbook

**Emergency rotation** (suspected compromise): skip step 1 — go straight to Infisical UI → Revoke the current secret, then create a new one and update the host. Accept the brief downtime.

## What this POC does NOT defend against

- A root-privileged agent on the same host — hooks and file perms don't matter
- ~~An agent that can patch `~/.claude/settings.json` to disable its own hooks~~ → **mitigated** by layer 2 (root-owned settings.json)
- ~~An agent that can patch the hook script itself~~ → **mitigated** by layer 2 (root-owned hook file)
- A compromised base image / CI runner — Infisical is one piece; host hardening is separate
- The user copy-pasting a secret from the UI into a chat

## Rollout checklist (per machine)

Order matters — hooks first, then stack, then CLI auth.

- [ ] Install Claude Code hooks: `scripts/install-claude-hooks.sh`
- [ ] Verify hooks: `scripts/verify-hardening.sh` (all probes should pass)
- [ ] Install Infisical CLI: `scripts/install-cli.sh` (npm, no sudo)
- [ ] *(Server hosts only)* Bring up Infisical stack: `scripts/install-stack.sh`
- [ ] `infisical login` — human admin only; for service hosts, use machine identity instead
- [ ] Lock down filesystem: `sudo scripts/lockdown-infisical-paths.sh <username>`
- [ ] Enable Claude Code sandbox: `claude --sandbox` or set in settings.json
- [ ] For each app migrated to Infisical: provision a dedicated machine identity, drop creds into `/etc/infisical/<project>.env` (root-owned, `0600`)

Ansible wrapper: [ansible/playbook.yml](ansible/playbook.yml) runs the scripts above across an inventory.

## Operational rules

- **Never** set `INFISICAL_ALLOW_AGENT=1` in `~/.bashrc` / `~/.profile`. It's a per-invocation escape, not a default.
- When an agent asks to run `infisical run -- some-app`, do it yourself in a human terminal and paste the output back — don't grant the escape.
- On a shared laptop, `infisical logout` at end of session; the human-user session is the crown jewel.
- Review Infisical audit log weekly; rotate anything read from an unexpected IP or at an unexpected time.
