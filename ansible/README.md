# Ansible rollout for Infisical + hardening

Thin Ansible wrapper around the shell scripts in `../scripts/`. All logic lives in the scripts (so you can test them locally without Ansible); this playbook just syncs the repo to each host and invokes them.

## One-time setup on the control machine

```bash
pip install ansible
ansible-galaxy collection install ansible.posix     # for synchronize module
```

Create `inventory.yml` (gitignored — holds hostnames/IPs):

```yaml
all:
  children:
    laptops:
      hosts:
        dev-laptop: {ansible_host: 192.0.2.10, ansible_user: devuser}
    servers:
      hosts:
        infisical-prod: {ansible_host: 192.0.2.20, ansible_user: deploy}
```

## Run

```bash
# Everything — laptops and servers
ansible-playbook -i inventory.yml playbook.yml

# Only hardening (hooks), no CLI, no stack — useful when Claude Code was freshly installed
ansible-playbook -i inventory.yml playbook.yml --tags=hardening

# Only the server (docker compose up)
ansible-playbook -i inventory.yml playbook.yml --tags=server

# Single host
ansible-playbook -i inventory.yml playbook.yml --limit=dev-laptop
```

## What this does NOT automate (intentional — crown-jewel gates)

- `infisical login` on each laptop — interactive, human-only
- Secret values themselves — created in the UI or via CLI by a human
- Machine-identity client-secret placement on servers — root-owned `/etc/infisical/*.env`, delivered out-of-band

These stay manual by design. See [../HARDENING.md](../HARDENING.md) for the rationale.

## Testing the scripts without Ansible

Every script is idempotent and runnable locally. The playbook is just `ansible-playbook -i inventory.yml` around:

```bash
bash scripts/install-claude-hooks.sh
bash scripts/verify-hardening.sh
bash scripts/install-cli.sh
bash scripts/install-stack.sh          # servers only
```

So you can dry-run on a new laptop by cloning the vault repo and running those four commands in order.
