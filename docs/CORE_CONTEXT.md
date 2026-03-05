# CORE_CONTEXT — infra-deploy
> Pflichtlektüre für jeden Coding Agent, Contributor und Reviewer.

## 1. Projekt-Identität
| Attribut | Wert |
|---|---|
| Repo | achimdehnert/infra-deploy |
| Produkt | Zentralisierte Deployment-API für alle Platform-Services |
| Zweck | Single entry point für alle Write-Operationen (Deploy, Rollback, Migrations, Backups) |

## 2. Architektur
- ADR-021: Unified Deployment Pattern
- ADR-067: Read/Write-Split (MCP local vs. GitHub Actions server-side)
- **Read-only ops** → deployment-mcp (lokal, schnell)
- **Write ops** → dieses Repo via repository_dispatch / workflow_dispatch

## 3. Workflows
| Workflow | Trigger | Zweck |
|---|---|---|
| deploy-service.yml | dispatch | Deploy + Health-Check + Auto-Rollback |
| rollback.yml | dispatch | Rollback auf vorherigen/spez. Tag |
| migrate.yml | dispatch | Django Migrations (mit optionalem Backup) |
| db-backup.yml | dispatch + schedule 02:00 UTC | PostgreSQL Backup (7-day retention) |
| health-check.yml | dispatch + schedule */15min | Health-Check aller/spez. Services |

## 4. Service Registry (Hetzner 88.198.191.108)
| Service | Deploy Path | Health URL |
|---|---|---|
| bfagent | /opt/bfagent-app | https://bfagent.iil.pet/healthz/ |
| risk-hub | /opt/risk-hub | https://demo.schutztat.de/health/ |
| travel-beat | /opt/travel-beat | https://drifttales.com/health/ |
| weltenhub | /opt/weltenhub | https://weltenforger.com/health/ |
| dev-hub | /opt/dev-hub | https://devhub.iil.pet/livez/ |
| pptx-hub | /opt/pptx-hub | https://prezimo.com/livez/ |
| trading-hub | /opt/trading-hub | https://trading-hub.iil.pet/livez/ |

## 5. Regeln (NON-NEGOTIABLE)
```
- Write ops: IMMER via GitHub Actions (nie direkt SSH)
- Read ops: deployment-mcp lokal
- Self-hosted runner auf 88.198.191.108 (/opt/actions-runner)
- Deploy state: /opt/deploy/production/.deployed/<service>.tag
```
