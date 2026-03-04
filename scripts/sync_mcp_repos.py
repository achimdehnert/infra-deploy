#!/usr/bin/env python3
"""
sync_mcp_repos.py — Windsurf MCP filesystem-Server automatisch synchronisieren.

Ermittelt alle Verzeichnisse unter GITHUB_DIR, vergleicht mit mcp_config.json
und trägt fehlende Repos ein. Entfernt Pfade die nicht mehr existieren.

Primärer Pfad: infra-deploy/scripts/sync_mcp_repos.py  (ADR-039 H-04)
Fallback:      bfagent/scripts/sync_mcp_repos.py

Usage:
    python3 /home/dehnert/github/infra-deploy/scripts/sync_mcp_repos.py
    python3 /home/dehnert/github/infra-deploy/scripts/sync_mcp_repos.py --dry-run
"""
import argparse
import json
import os
import sys

GITHUB_DIR = "/home/dehnert/github"
MCP_CONFIG = "/home/dehnert/.codeium/windsurf/mcp_config.json"


def get_repos_on_disk() -> list[str]:
    """Alle echten Repo-Verzeichnisse unter GITHUB_DIR."""
    return sorted([
        os.path.join(GITHUB_DIR, d)
        for d in os.listdir(GITHUB_DIR)
        if os.path.isdir(os.path.join(GITHUB_DIR, d))
        and not d.startswith(".")
    ])


def sync(dry_run: bool = False) -> int:
    if not os.path.exists(MCP_CONFIG):
        print(f"FEHLER: {MCP_CONFIG} nicht gefunden", file=sys.stderr)
        return 1

    with open(MCP_CONFIG, "r", encoding="utf-8") as f:
        config = json.load(f)

    args: list[str] = config["mcpServers"]["filesystem"]["args"]
    prefix = [a for a in args if not a.startswith(GITHUB_DIR)]
    configured = set(a for a in args if a.startswith(GITHUB_DIR))
    on_disk = set(get_repos_on_disk())

    new_repos = sorted(on_disk - configured)
    stale_repos = sorted(configured - on_disk)

    if not new_repos and not stale_repos:
        print(f"Alles aktuell — {len(configured)} Repos konfiguriert, keine Änderungen.")
        return 0

    if new_repos:
        print(f"NEU ({len(new_repos)}):")
        for r in new_repos:
            print(f"  + {r}")

    if stale_repos:
        print(f"ENTFERNT — nicht mehr auf Disk ({len(stale_repos)}):")
        for r in stale_repos:
            print(f"  - {r}")

    if dry_run:
        print("\n[DRY-RUN] Keine Änderungen geschrieben.")
        return 0

    updated_repos = sorted(on_disk)
    config["mcpServers"]["filesystem"]["args"] = prefix + updated_repos

    with open(MCP_CONFIG, "w", encoding="utf-8") as f:
        json.dump(config, f, indent=2, ensure_ascii=False)

    print(f"\nGesamt: {len(updated_repos)} Repos in mcp_config.json konfiguriert.")
    print("Windsurf neu starten: Cmd+Shift+P -> Reload Window")
    return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true", help="Nur anzeigen, nichts schreiben")
    args = parser.parse_args()
    sys.exit(sync(dry_run=args.dry_run))
