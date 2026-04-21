# Vault — hybrid secrets with Infisical + AI-agent hardening

> **Disclaimer**
>
> 1. **This is a proof-of-concept.** It may contain bugs, incomplete flows, or edge cases that haven't been addressed. Use it for learning and experimentation, not as a production-grade security product out of the box.
> 2. **Review every script and config before running it in your environment.** File paths, hook patterns, and permission models may need adaptation to your OS, shell, and tooling.
> 3. **Treat this repo as a guideline and template** for hardening AI coding agents against secret exfiltration — not as a turnkey solution. Your threat model, infrastructure, and operational context will differ.

Self-hosted Infisical secrets store plus a Claude Code PreToolUse hook that blocks AI coding agents from reading secret material. Ships with installers (shell scripts + Ansible) so rolling this out to a second laptop or server is one command.

## Read order

1. **[HARDENING.md](HARDENING.md)** — the critical piece. Infisical alone doesn't stop a local AI agent from dumping every secret; the Claude Code hook does. Install this first on any machine where an AI agent runs.
2. **[POC.md](POC.md)** — self-hosted stack, CLI install, first `infisical run` injection proof.
3. **Worked examples** — real-world migrations from plaintext `.env` / `config.json` to Infisical:
   - [docs/examples/trello-gitlab-migrator.md](docs/examples/trello-gitlab-migrator.md) (start here — small)
4. **[ansible/README.md](ansible/README.md)** — fleet rollout pattern.

## Layout

```
vault/
├── README.md             ← you are here
├── HARDENING.md          ← read first (agent-isolation rationale + rules)
├── POC.md                ← stack bring-up + smoke test
├── stack/                ← self-hosted Infisical (docker compose)
│   ├── docker-compose.yml
│   ├── .env.template     ← committed; installer generates per-host .env
│   └── .env              ← gitignored; per-host secrets (encryption keys, DB pw)
├── claude-hooks/         ← Claude Code PreToolUse guard
│   └── protect_infisical.py
├── scripts/              ← idempotent installers + bootstrappers
│   ├── install-claude-hooks.sh
│   ├── install-cli.sh
│   ├── install-stack.sh
│   ├── verify-hardening.sh
│   └── bootstrap-trello-gitlab-migrator.sh
├── ansible/              ← thin wrapper that runs the scripts across a fleet
│   ├── playbook.yml
│   └── README.md
└── docs/examples/        ← per-project migration recipes
    └── trello-gitlab-migrator.md
```

## Quickstart (single laptop)

```bash
cd path/to/vault

# 1. lock out the AI agent from Infisical first
bash scripts/install-claude-hooks.sh
bash scripts/verify-hardening.sh          # 12 probes, all BLOCK/allow as expected

# 2. install the CLI
bash scripts/install-cli.sh

# 3. start the self-hosted stack (only on the host that runs Infisical)
bash scripts/install-stack.sh             # generates stack/.env with fresh keys

# 4. open http://localhost:8080, sign up, create your first project + secrets

# 5. in any consuming repo:
cd /path/to/my-app
infisical login                           # interactive, one-off per machine
infisical init                            # pick the project
infisical run --env=dev -- my-app-command
```

## What's intentionally manual (crown-jewel gates)

- Signing up the admin account on a new stack
- `infisical login` per laptop
- Minting upstream API tokens (GitLab, AWS, etc.) in their respective UIs
- Pasting the real token values into the Infisical UI
- Placing machine-identity client secrets into root-owned `/etc/infisical/*.env` on service hosts

See [HARDENING.md §Rollout checklist](HARDENING.md#rollout-checklist-per-machine) for the per-machine order of operations.

## Status

POC phase. Runs on a single WSL2 laptop against a local Docker stack. Validated: `infisical run` injection (see POC.md), two migrations drafted (one applied with placeholder tokens, one design-only), hardening hook installed and all 12 probes passing.
