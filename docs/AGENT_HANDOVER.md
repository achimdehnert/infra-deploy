# AGENT_HANDOVER — infra-deploy
> Lesen vor jeder Session. Aktualisieren nach jeder Session.

## Aktueller Stand
| Attribut | Wert |
|---|---|
| Zuletzt aktualisiert | 2026-03-05 |
| Branch | main |
| Phase | Produktiv / stabile Infrastruktur |

## Was wurde zuletzt getan?
- 2026-03-05 — GitHub-Infra eingerichtet (Issue Templates, CORE_CONTEXT, AGENT_HANDOVER)

## Offene Aufgaben (Priorisiert)
- [ ] Workflows regelmäßig auf Aktualität prüfen (neue Services eintragen)
- [ ] illustration-hub in Service Registry ergänzen wenn deployed
- [ ] odoo-hub in Service Registry ergänzen wenn deployed

## Bekannte Probleme / Technical Debt
| Problem | Priorität |
|---|---|
| issue-triage.yml fehlt (kein Project-Board für infra-deploy) | Low |

## Wichtige Befehle
```bash
# Deploy via GitHub UI: Actions → deploy-service → Run workflow
# Oder via API:
curl -X POST -H "Authorization: token $GITHUB_TOKEN" \
  https://api.github.com/repos/achimdehnert/infra-deploy/dispatches \
  -d '{"event_type": "deploy-service", "client_payload": {"service": "<name>", "image_tag": "latest"}}'
```
