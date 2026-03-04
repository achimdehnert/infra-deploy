#!/usr/bin/env python3
"""
check_workflow_reviews.py — Überprüft ob Windsurf-Workflows ihren Review-Zyklus überschritten haben.

Liest last_reviewed + review_interval_days aus dem Frontmatter jedes Workflows.
Gibt eine Liste von überfälligen Reviews aus. Kann GitHub Issues öffnen.

Usage:
    python3 check_workflow_reviews.py                    # nur anzeigen
    python3 check_workflow_reviews.py --create-issues    # GitHub Issues erstellen (braucht GITHUB_TOKEN)
    python3 check_workflow_reviews.py --days-warning 14  # warnen wenn <= 14 Tage bis Review

Exit codes:
    0 = alles aktuell
    1 = Reviews überfällig
"""
import argparse
import os
import pathlib
import re
import sys
from datetime import date, timedelta

GITHUB_DIR = pathlib.Path("/home/dehnert/github")
DEFAULT_INTERVAL_DAYS = 90
DEFAULT_WARNING_DAYS = 14


def parse_frontmatter(content: str) -> dict:
    if not content.startswith("---"):
        return {}
    parts = content.split("---", 2)
    if len(parts) < 3:
        return {}
    result = {}
    for line in parts[1].strip().splitlines():
        if ":" in line and not line.startswith("#"):
            key, _, value = line.partition(":")
            result[key.strip()] = value.strip().strip('"\'')
    return result


def check_reviews(warning_days: int = DEFAULT_WARNING_DAYS) -> list[dict]:
    """Gibt Liste von Workflows zurück die Review brauchen."""
    today = date.today()
    overdue = []

    for repo_dir in sorted(GITHUB_DIR.iterdir()):
        if not repo_dir.is_dir() or repo_dir.name.startswith("."):
            continue
        wf_dir = repo_dir / ".windsurf" / "workflows"
        if not wf_dir.exists():
            continue

        for wf_file in sorted(wf_dir.glob("*.md")):
            content = wf_file.read_text(encoding="utf-8")
            fm = parse_frontmatter(content)

            last_reviewed_str = fm.get("last_reviewed", "")
            if not last_reviewed_str:
                overdue.append({
                    "repo": repo_dir.name,
                    "workflow": wf_file.name,
                    "reason": "last_reviewed fehlt im Frontmatter",
                    "days_overdue": None,
                    "next_review": None,
                })
                continue

            try:
                last_reviewed = date.fromisoformat(last_reviewed_str)
            except ValueError:
                overdue.append({
                    "repo": repo_dir.name,
                    "workflow": wf_file.name,
                    "reason": f"last_reviewed ungültiges Format: '{last_reviewed_str}'",
                    "days_overdue": None,
                    "next_review": None,
                })
                continue

            interval = int(fm.get("review_interval_days", DEFAULT_INTERVAL_DAYS))
            next_review = last_reviewed + timedelta(days=interval)
            days_until = (next_review - today).days

            if days_until <= warning_days:
                overdue.append({
                    "repo": repo_dir.name,
                    "workflow": wf_file.name,
                    "reason": f"Review {'überfällig' if days_until < 0 else f'in {days_until} Tagen fällig'}",
                    "days_overdue": -days_until if days_until < 0 else 0,
                    "next_review": next_review.isoformat(),
                    "last_reviewed": last_reviewed_str,
                })

    return overdue


def create_github_issue(overdue: list[dict]) -> None:
    """Erstellt GitHub Issue in bfagent mit allen überfälligen Reviews."""
    try:
        import httpx
    except ImportError:
        print("httpx nicht installiert — kein Issue erstellt")
        return

    token = os.environ.get("GITHUB_TOKEN")
    if not token:
        print("GITHUB_TOKEN nicht gesetzt — kein Issue erstellt")
        return

    today = date.today().isoformat()
    body_lines = [
        f"# Workflow-Reviews überfällig ({today})\n",
        f"**{len(overdue)} Workflows** benötigen einen Review:\n",
        "| Repo | Workflow | Status | Letzter Review |",
        "|------|----------|--------|----------------|",
    ]
    for item in overdue:
        body_lines.append(
            f"| {item['repo']} | `{item['workflow']}` | {item['reason']} | {item.get('last_reviewed', '—')} |"
        )
    body_lines.append(f"\n*Generiert von `check_workflow_reviews.py` am {today}*")

    r = httpx.post(
        "https://api.github.com/repos/achimdehnert/bfagent/issues",
        headers={"Authorization": f"token {token}", "Accept": "application/vnd.github.v3+json"},
        json={
            "title": f"[Workflow-Review] {len(overdue)} überfällige Reviews ({today})",
            "body": "\n".join(body_lines),
            "labels": ["workflow-review", "maintenance"],
        },
        timeout=10,
    )
    if r.status_code == 201:
        print(f"✅ GitHub Issue erstellt: {r.json()['html_url']}")
    else:
        print(f"Fehler beim Issue erstellen: {r.status_code} — {r.text[:200]}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--create-issues", action="store_true", help="GitHub Issue für überfällige Reviews erstellen")
    parser.add_argument("--days-warning", type=int, default=DEFAULT_WARNING_DAYS,
                        help=f"Warnen wenn <= N Tage bis Review (default: {DEFAULT_WARNING_DAYS})")
    args = parser.parse_args()

    overdue = check_reviews(warning_days=args.days_warning)

    if not overdue:
        print(f"✅ Alle Workflows haben aktuellen Review (Warnschwelle: {args.days_warning} Tage).")
        return 0

    print(f"🔴 {len(overdue)} Workflows benötigen Review:\n")
    for item in overdue:
        days_info = f" ({item['days_overdue']} Tage überfällig)" if item.get("days_overdue") else ""
        print(f"  • {item['repo']}/.windsurf/workflows/{item['workflow']}")
        print(f"    {item['reason']}{days_info}")
        if item.get("last_reviewed"):
            print(f"    Letzter Review: {item['last_reviewed']}")

    if args.create_issues:
        create_github_issue(overdue)

    return 1


if __name__ == "__main__":
    sys.exit(main())
