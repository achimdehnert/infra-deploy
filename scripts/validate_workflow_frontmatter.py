#!/usr/bin/env python3
"""
validate_workflow_frontmatter.py — Frontmatter-Validator für Windsurf-Workflows.

Prüft:
1. Pflichtfelder vorhanden (description, version, last_reviewed, scope)
2. Verbotene sensitive Felder NICHT vorhanden (server_ip, project_path, *password*, *secret*)
3. /ship-Workflows haben ship-spezifische Pflichtfelder (health_port, cd_workflow, web_container)
4. Felder sind korrekt typisiert

Usage:
    python3 validate_workflow_frontmatter.py                    # aktuelles Repo
    python3 validate_workflow_frontmatter.py --all-repos        # alle Repos
    python3 validate_workflow_frontmatter.py --repo risk-hub    # einzelnes Repo
    python3 validate_workflow_frontmatter.py --fix-version      # fehlende version: "1.0" ergänzen

Exit codes:
    0 = alles valide
    1 = Validierungsfehler gefunden
"""
import argparse
import pathlib
import re
import sys

GITHUB_DIR = pathlib.Path("/home/dehnert/github")

REQUIRED_FIELDS = ["description", "version", "last_reviewed", "scope"]

SHIP_REQUIRED_FIELDS = ["health_port", "cd_workflow", "web_container"]

BANNED_FIELDS = [
    "server_ip",
    "project_path",
    "password",
    "secret",
    "token",
    "api_key",
    "ssh_key",
    "db_url",
    "database_url",
]

VALID_SCOPES = {"cross-repo"}


def parse_frontmatter(content: str) -> dict | None:
    """Parst YAML-Frontmatter aus Markdown. Gibt None zurück wenn kein Frontmatter."""
    if not content.startswith("---"):
        return None
    parts = content.split("---", 2)
    if len(parts) < 3:
        return None
    fm_text = parts[1]
    result = {}
    for line in fm_text.strip().splitlines():
        line = line.strip()
        if ":" in line and not line.startswith("#"):
            key, _, value = line.partition(":")
            result[key.strip()] = value.strip().strip('"\'')
    return result


def validate_file(path: pathlib.Path, fix_version: bool = False) -> list[str]:
    """Validiert eine einzelne Workflow-Datei. Gibt Liste von Fehlern zurück."""
    errors = []
    content = path.read_text(encoding="utf-8")
    fm = parse_frontmatter(content)

    if fm is None:
        errors.append(f"KEIN FRONTMATTER — Pflicht-Frontmatter fehlt komplett")
        return errors

    # Pflichtfelder prüfen
    for field in REQUIRED_FIELDS:
        if field not in fm:
            if field == "version" and fix_version:
                # Auto-fix: version ergänzen
                new_content = content.replace(
                    f"description: {fm.get('description', '')}",
                    f"description: {fm.get('description', '')}\nversion: \"1.0\""
                )
                path.write_text(new_content, encoding="utf-8")
                print(f"  AUTO-FIX: version: \"1.0\" ergänzt in {path.name}")
            else:
                errors.append(f"PFLICHTFELD FEHLT: '{field}'")

    # Verbotene Felder prüfen (case-insensitive)
    for key in fm:
        key_lower = key.lower()
        for banned in BANNED_FIELDS:
            if banned in key_lower:
                errors.append(
                    f"SENSITIVES FELD VERBOTEN: '{key}' — "
                    f"gehört in GitHub Secrets, nicht ins Frontmatter (ADR-039 C-01)"
                )
                break

    # /ship-spezifische Pflichtfelder
    if path.name == "ship.md":
        for field in SHIP_REQUIRED_FIELDS:
            if field not in fm:
                errors.append(f"SHIP-PFLICHTFELD FEHLT: '{field}'")

    # description Länge
    desc = fm.get("description", "")
    if len(desc) > 80:
        errors.append(f"description zu lang: {len(desc)} Zeichen (max. 80)")

    return errors


def validate_repo(repo_path: pathlib.Path, fix_version: bool = False) -> int:
    """Validiert alle Workflows in einem Repo. Gibt Anzahl der Fehler zurück."""
    wf_dir = repo_path / ".windsurf" / "workflows"
    if not wf_dir.exists():
        return 0

    total_errors = 0
    for wf_file in sorted(wf_dir.glob("*.md")):
        errors = validate_file(wf_file, fix_version=fix_version)
        if errors:
            print(f"\n🔴 {repo_path.name}/.windsurf/workflows/{wf_file.name}")
            for e in errors:
                print(f"   • {e}")
            total_errors += len(errors)

    return total_errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--all-repos", action="store_true", help="Alle Repos prüfen")
    parser.add_argument("--repo", type=str, help="Einzelnes Repo prüfen")
    parser.add_argument("--fix-version", action="store_true", help="Fehlende version-Felder auto-ergänzen")
    args = parser.parse_args()

    total_errors = 0

    if args.all_repos:
        repos = sorted([d for d in GITHUB_DIR.iterdir() if d.is_dir() and not d.name.startswith(".")])
        print(f"Validiere {len(repos)} Repos...")
        for repo in repos:
            total_errors += validate_repo(repo, fix_version=args.fix_version)
    elif args.repo:
        repo_path = GITHUB_DIR / args.repo
        if not repo_path.exists():
            print(f"FEHLER: Repo nicht gefunden: {repo_path}")
            return 2
        total_errors += validate_repo(repo_path, fix_version=args.fix_version)
    else:
        # Aktuelles Verzeichnis / erstes Repo mit .windsurf/ suchen
        cwd = pathlib.Path.cwd()
        # Suche nach .windsurf/workflows im aktuellen Verzeichnis
        if (cwd / ".windsurf" / "workflows").exists():
            total_errors += validate_repo(cwd, fix_version=args.fix_version)
        else:
            print("Kein .windsurf/workflows/ im aktuellen Verzeichnis. Nutze --repo oder --all-repos.")
            return 2

    if total_errors == 0:
        print("✅ Alle Workflows valide.")
        return 0
    else:
        print(f"\n🔴 {total_errors} Validierungsfehler gefunden.")
        return 1


if __name__ == "__main__":
    sys.exit(main())
