# Production monitoring: Infisical → Grafana

> Applies to the **production Infisical stack on your dedicated server**, not the local POC.
> The server instance must be observable from your Grafana instance.

## What to monitor

### 1. Stack health (critical)

The Infisical stack (Infisical + Postgres + Redis) must be continuously probed.

| Check | Endpoint / method | Alert threshold |
|-------|-------------------|-----------------|
| Infisical API | `GET http://<infisical-host>:8080/api/status` → HTTP 200 | Down > 1 min |
| Postgres | `pg_isready` via container healthcheck | Unhealthy > 30s |
| Redis | `redis-cli ping` via container healthcheck | Unhealthy > 30s |

**Grafana setup:** Use a **Synthetic Monitoring** or **Infinity** datasource to poll the `/api/status` endpoint. Create alert rule: fire if non-200 for 2 consecutive checks (1-min interval).

### 2. Infisical audit log (security)

Infisical logs every secret read/write with timestamp, source IP, and identity. This is your tripwire for unauthorized access.

**How to get audit data into Grafana:**

Option A — **Postgres direct query** (simplest):
- Add the Infisical Postgres DB as a Grafana datasource (read-only user recommended)
- Query the `audit_logs` table for recent events
- Dashboard panels: secret reads per identity, reads from unexpected IPs, reads outside business hours

Option B — **Log shipping** (if Infisical exposes structured logs):
- Ship Infisical container logs (`docker logs`) to Loki
- Parse JSON log lines for audit events
- Query via LogQL in Grafana

| Alert | Condition |
|-------|-----------|
| Unexpected identity read | Identity not in allow-list reads a secret |
| Unexpected IP | Secret read from IP outside known range (your-local-subnet/24) |
| Off-hours access | Secret read between 00:00–06:00 (no cron jobs expected) |
| High read volume | > 50 secret reads in 5 minutes from a single identity |

### 3. Container resource usage

| Metric | Source | Alert |
|--------|--------|-------|
| Container CPU/memory | Docker metrics or cAdvisor → Prometheus | Infisical > 80% memory for 5 min |
| Disk usage (pg-data) | node_exporter filesystem metrics | > 80% of volume |
| Container restarts | Docker events or cAdvisor | Any restart |

### 4. Certificate / TLS (when enabled)

If Infisical is fronted by a reverse proxy with TLS:

| Check | Alert |
|-------|-------|
| Certificate expiry | < 14 days |
| TLS handshake | Fails for 2 consecutive checks |

## Dashboard layout suggestion

```
Row 1: Stack Health
  [Infisical API status]  [Postgres health]  [Redis health]  [Uptime %]

Row 2: Audit Activity
  [Secret reads timeline]  [Reads by identity]  [Reads by IP]  [Anomalies]

Row 3: Resources
  [CPU]  [Memory]  [Disk]  [Container restarts]
```

## Implementation steps

1. **Prereq:** Production Infisical stack running on your dedicated server
2. Add Infisical Postgres as a Grafana datasource (read-only DB user)
3. Import or create dashboard with the panels above
4. Configure alert rules → notification channel (Telegram, email, etc.)
5. Test alerts by triggering a dummy secret read from an unusual IP
6. Ship container logs to Loki (optional, for deeper audit queries)

## What NOT to expose to Grafana

- The Infisical `ENCRYPTION_KEY` or `AUTH_SECRET` — Grafana needs a **read-only Postgres user**, not the app credentials
- The admin UI — Grafana talks to the DB, not the Infisical API (except for health checks)
