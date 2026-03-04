#!/usr/bin/env python3
"""
check_workflow_drift.py — Drift-Detection für cross-repo Windsurf-Workflows.

Prüft ob alle Workflows mit scope: cross-repo in allen Repos identisch sind.
Meldet Abweichungen mit MD5-Hash-Differenz und betroffenen Repos.

Usage:
    python3 check_workflow_drift.py
    python3 check_workflow_drift.py --fix   # Kopiert Master-Version in alle Repos
    python3 check_workflow_drift.py --verbose

Exit codes:
    0 = kein Drift
    1 = Drift gefunden
    2 = Konfigurationsfehler
"""
import argparse
import hashlib
import pathlib
import re
import shutil
import sys

GITHUB_DIR = pathlib.Path("/home/dehnert/github")
MASTER_REPO = "bfagent"

CROSS_REPO_WORKFLOWS = [
    "sync-repos.md",
    "adr-create.md",
    "pr-review.md",
]


def get_frontmatter_scope(path: pathlib.Path) -> str | None:
    """Liest den scope-Wert aus dem YAML-Frontmatter."""
    try:
        content = path.read_text(encoding="utf-8")
        if not content.startswith("---"):
            return None
        fm_text = content.split("---")[1]
        m = re.search(r"^scope:\s*(.+)$", fm_text, re.MULTILINE)
        if m:
            return m.group(1).strip()
    except Exception:
        pass
    return None


def md5(path: pathlib.Path) -> str:
    return hashlib.md5(path.read_bytes()).hexdigest()


def get_repos() -> list[pathlib.Path]:
    return sorted([
        d for d in GITHUB_DIR.iterdir()
        if d.is_dir() and not d.name.startswith(".")
    ])


def check_drift(verbose: bool = False, fix: bool = False) -> int:
    repos = get_repos()
    total_drift = 0

    for workflow_name in CROSS_REPO_WORKFLOWS:
        master_path = GITHUB_DIR / MASTER_REPO / ".windsurf" / "workflows" / workflow_name

        if not master_path.exists():
            print(f"⚠️  MASTER FEHLT: {MASTER_REPO}/.windsurf/workflows/{workflow_name}")
            continue

        master_scope = get_frontmatter_scope(master_path)
        if master_scope != "cross-repo":
            if verbose:
                print(f"ℹ️  {workflow_name}: scope={master_scope} (kein cross-repo, übersprungen)")
            continue

        master_hash = md5(master_path)
        drifted = []
        missing = []
        ok = []

        for repo in repos:
            if repo.name == MASTER_REPO:
                continue
            wf_path = repo / ".windsurf" / "workflows" / workflow_name
            if not wf_path.exists():
                missing.append(repo.name)
            elif md5(wf_path) != master_hash:
                drifted.append((repo.name, md5(wf_path)))
            else:
                ok.append(repo.name)

        if not drifted and not missing:
            if verbose:
                print(f"✅ {workflow_name}: {len(ok)} Repos identisch")
            continue

        total_drift += len(drifted) + len(missing)
        print(f"\n🔴 DRIFT: {workflow_name}")
        print(f"   Master: {MASTER_REPO} ({master_hash[:8]})")

        for repo_name, repo_hash in drifted:
            print(f"   ≠ {repo_name} ({repo_hash[:8]})")
            if fix:
                dst = GITHUB_DIR / repo_name / ".windsurf" / "workflows" / workflow_name
                dst.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(master_path, dst)
                print(f"     → FIXED: Master-Version kopiert")

        for repo_name in missing:
            print(f"   ✗ {repo_name} (fehlt)")
            if fix:
                dst = GITHUB_DIR / repo_name / ".windsurf" / "workflows" / workflow_name
                dst.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(master_path, dst)
                print(f"     → FIXED: Datei angelegt")

    if total_drift == 0:
        print(f"✅ Kein Drift gefunden in {len(CROSS_REPO_WORKFLOWS)} cross-repo Workflows.")
        return 0
    else:
        print(f"\n{'FIXED' if fix else 'GESAMT'}: {total_drift} Abweichungen in {len(CROSS_REPO_WORKFLOWS)} Workflows.")
        if not fix:
            print("Tipp: --fix um Master-Version in alle Repos zu kopieren.")
        return 0 if fix else 1


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fix", action="store_true", help="Master-Version in alle Repos kopieren")
    parser.add_argument("--verbose", action="store_true", help="Auch OK-Status anzeigen")
    args = parser.parse_args()
    sys.exit(check_drift(verbose=args.verbose, fix=args.fix))
