# infra-deploy

Centralized deployment API for all `achimdehnert` platform services.

> Implements [ADR-021 §2.14](https://github.com/achimdehnert/platform/blob/main/docs/adr/ADR-021-unified-deployment-pattern.md) — `infra-deploy` as Deployment API.

---

## Purpose

This repository is the **single entry point** for:

- **Agent-triggered deploys** (via `repository_dispatch`)
- **Manual deploys** (via `workflow_dispatch` in GitHub UI)
- **Explicit rollbacks** (via `rollback.yml`)

Standard push-triggered CI/CD continues to use `_deploy-hetzner.yml` in each service repo. This repo is **additive**, not a replacement.

---

## Workflows

| Workflow | Trigger | Purpose |
| --- | --- | --- |
| `deploy-service.yml` | `repository_dispatch` / `workflow_dispatch` | Deploy a service to production |
| `rollback.yml` | `workflow_dispatch` | Roll back a service to a previous tag |

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
```

---

## Required Secrets

Set these in **Settings → Secrets → Actions**:

| Secret | Value |
| --- | --- |
| `DEPLOY_SSH_KEY` | SSH private key for `root@88.198.191.108` |

---

## Self-Hosted Runner

Workflows run on `[self-hosted, dev-server]`. The runner must be registered on the dev-server and healthy.

To verify: `systemctl status actions.runner.*`

---

## Service Registry

All deploy parameters are defined in [ADR-021 §2.3](https://github.com/achimdehnert/platform/blob/main/docs/adr/ADR-021-unified-deployment-pattern.md).

| Service | Deploy path | Host port | Health URL |
| --- | --- | --- | --- |
| bfagent | `/opt/bfagent-app` | 8088 | `https://bfagent.iil.pet/healthz/` |
| risk-hub | `/opt/risk-hub` | 8090 | `https://demo.schutztat.de/healthz/` |
| travel-beat | `/opt/travel-beat` | 8002 | `https://drifttales.com/healthz/` |
| weltenhub | `/opt/weltenhub` | 8081 | `https://weltenforger.com/healthz/` |
| pptx-hub | `/opt/pptx-hub` | 8020 | *(not deployed)* |
| dev-hub | `/opt/dev-hub` | 8085 | `https://devhub.iil.pet/livez/` |
