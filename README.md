# infra-deploy

Centralized deployment API for all `achimdehnert` platform services.

> Implements [ADR-021 §2.14](https://github.com/achimdehnert/platform/blob/main/docs/adr/ADR-021-unified-deployment-pattern.md) — `infra-deploy` as Deployment API.
> Architecture decision: [ADR-067](https://github.com/achimdehnert/platform/blob/main/docs/adr/ADR-067-deployment-execution-strategy.md) — Read/Write-Split (MCP local vs. GitHub Actions server-side).

---

## Purpose

This repository is the **single entry point** for all write operations:

- **Agent-triggered deploys** (via `repository_dispatch`)
- **Manual deploys** (via `workflow_dispatch` in GitHub UI)
- **Explicit rollbacks** (via `rollback.yml`)
- **Database migrations** (via `migrate.yml`)
- **Database backups** (via `db-backup.yml`, daily + on-demand)
- **Health checks** (via `health-check.yml`, every 15 min + on-demand)

Standard push-triggered CI/CD continues to use `_deploy-hetzner.yml` in each service repo. This repo is **additive**, not a replacement.

> **Read-only operations** (logs, status, DNS, SSL) remain in `deployment-mcp` local tools — they are fast and non-blocking.

---

## Workflows

| Workflow | Trigger | Purpose | Timeout |
| --- | --- | --- | --- |
| `deploy-service.yml` | `repository_dispatch` / `workflow_dispatch` | Deploy + Health-Check + Auto-Rollback | 15 min |
| `rollback.yml` | `workflow_dispatch` | Roll back to previous or specific tag | 10 min |
| `migrate.yml` | `workflow_dispatch` | Run Django migrations (with optional backup) | 10 min |
| `db-backup.yml` | `workflow_dispatch` / `schedule` (02:00 UTC) | PostgreSQL backup with 7-day retention | 30 min |
| `health-check.yml` | `workflow_dispatch` / `schedule` (*/15 min) | Health check all or specific service | 5 min |

---

## Usage

### Manual deploy (GitHub UI)

1. Go to **Actions → deploy-service → Run workflow**
2. Fill in:
   - `service`: e.g. `travel-beat`
   - `image_tag`: e.g. `latest` or a SHA like `a1b2c3d`
   - `has_migrations`: `true` or `false`

### Agent-triggered deploy (repository_dispatch)

```bash
curl -X POST \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  https://api.github.com/repos/achimdehnert/infra-deploy/dispatches \
  -d '{
    "event_type": "deploy-service",
    "client_payload": {
      "service": "travel-beat",
      "image_tag": "latest",
      "has_migrations": "false"
    }
  }'
```

### Migrations only

1. Go to **Actions → migrate → Run workflow**
2. Fill in:
   - `service`: e.g. `travel-beat`
   - `backup_first`: `true` (recommended)

### Rollback (GitHub UI)

1. Go to **Actions → rollback → Run workflow**
2. Fill in:
   - `service`: e.g. `travel-beat`
   - `target_tag`: e.g. `a1b2c3d` (leave empty for previous tag)

---

## Server State

Deploy state is tracked on `88.198.191.108` at:

```
/opt/deploy/production/.deployed/
├── <service>.tag        # Currently active image tag
├── <service>.tag.prev   # Previous tag (rollback target)
└── deploy.log           # Append-only audit log

/opt/deploy/backups/<service>/
└── <service>_YYYYMMDD_HHMMSS.sql.gz   # DB backups (7-day retention)
```

---

## Required Secrets

Set these in **Settings → Secrets → Actions**:

| Secret | Value |
| --- | --- |
| `DEPLOY_SSH_KEY` | SSH private key for `root@88.198.191.108` |

---

## Self-Hosted Runner

Workflows run on `[self-hosted, dev-server]` on `88.198.191.108`.

- **Installation path**: `/opt/actions-runner`
- **Systemd service**: `actions.runner.achimdehnert-infra-deploy.prod-server.service`
- **Runner status**: Settings → Actions → Runners

---

## Service Registry

All services deployed on Hetzner VM `88.198.191.108` via Docker Compose + GHCR images.

| Service | Brand | Deploy Path | Compose Service | Health URL | DB Container | DB Name |
| --- | --- | --- | --- | --- | --- | --- |
| `bfagent` | BF Agent | `/opt/bfagent-app` | `bfagent-web` | `https://bfagent.iil.pet/healthz/` | `bfagent_db` | `bfagent_prod` |
| `risk-hub` | Schutztat | `/opt/risk-hub` | `risk-hub-web` | `https://demo.schutztat.de/health/` | `risk_hub_db` | `risk_hub` |
| `travel-beat` | DriftTales | `/opt/travel-beat` | `travel-beat-web` | `https://drifttales.com/health/` | `travel_beat_db` | `travel_beat` |
| `weltenhub` | Weltenforger | `/opt/weltenhub` | `weltenhub-web` | `https://weltenforger.com/health/` | `bfagent_db` | `weltenhub` |
| `dev-hub` | DevHub | `/opt/dev-hub` | `devhub-web` | `https://devhub.iil.pet/livez/` | `bfagent_db` | `devhub_db` |
| `pptx-hub` | Prezimo | `/opt/pptx-hub` | `pptx-hub-web` | `https://prezimo.com/livez/` | `pptx_hub_db` | `pptx_hub` |
| `coach-hub` | KI ohne Risiko | `/opt/coach-hub` | `coach-hub-web` | `http://127.0.0.1:8007/livez/` | `coach_hub_db` | `coach_hub` |
| `trading-hub` | — | `/opt/trading-hub` | `trading-hub-web` | `https://trading-hub.iil.pet/livez/` | `trading_hub_db` | `tradinghub_prod` |
| `wedding-hub` | — | `/opt/wedding-hub` | `wedding-hub-web` | `https://wedding-hub.iil.pet/livez/` | `wedding_hub_db` | `wedding_hub` |
| `cad-hub` | nl2cad | `/opt/cad-hub` | `web` | `https://nl2cad.de/livez/` | `cad-hub-db-1` | `cad_hub` |

> **Note**: `weltenhub` and `dev-hub` share the `bfagent_db` PostgreSQL container (user: `bfagent`).
> `cad-hub` is currently stopped (not actively deployed).
