#!/usr/bin/env python3
"""
pip-upgrade.py — Safely upgrade all outdated pip packages
with full debug logging in a single log file.

Conflict strategy:
  1. Skip packages owned by pacman (/usr/lib/) or listed in exclude file.
  2. Try upgrading the package alone.
  3. On conflict, roll back to original version and report.
     Conflicting packages must be resolved manually.
"""

import subprocess
import sys
import logging
import re
from datetime import datetime
from pathlib import Path


# ── Constants ──────────────────────────────────────────────────────────────────

# Exclude file — one package name per line, # for comments.
EXCLUDE_FILE = Path.home() / ".config" / "pip" / "upgrade-exclude.txt"

# Packages installed here are pacman/sudo-pip owned — never touch.
PACMAN_SITE = "/usr/lib/python"


# ── Log Setup ──────────────────────────────────────────────────────────────────

LOG_DIR = Path.home() / ".log" / "pip"
LOG_DIR.mkdir(parents=True, exist_ok=True)
LOG_FILE = LOG_DIR / f"pip-upgrade_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log"

logger = logging.getLogger("pip-upgrade")
logger.setLevel(logging.DEBUG)

file_handler = logging.FileHandler(LOG_FILE)
file_handler.setLevel(logging.DEBUG)
file_handler.setFormatter(logging.Formatter(
    "%(asctime)s [%(levelname)-8s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S"
))

console_handler = logging.StreamHandler(sys.stdout)
console_handler.setLevel(logging.INFO)
console_handler.setFormatter(logging.Formatter("%(message)s"))

logger.addHandler(file_handler)
logger.addHandler(console_handler)


# ── Exclusion / System Helpers ─────────────────────────────────────────────────

def load_excludes() -> set[str]:
    """Load package names from exclude file. Returns empty set if file missing."""
    if not EXCLUDE_FILE.exists():
        return set()
    excluded = set()
    for line in EXCLUDE_FILE.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            excluded.add(line.lower())
    return excluded


def is_system_package(package: str) -> bool:
    """Return True if the package is installed in /usr/lib/ (pacman/sudo pip owned)."""
    result = subprocess.run(
        [sys.executable, "-m", "pip", "show", package],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    for line in result.stdout.splitlines():
        if line.startswith("Location:") and PACMAN_SITE in line:
            return True
    return False


# ── Helpers ────────────────────────────────────────────────────────────────────

def run_pip(*args) -> tuple[int, str]:
    """Run a pip command, stream DEBUG lines to log, return (exit_code, output)."""
    cmd = [sys.executable, "-m", "pip", *args]
    logger.debug(f"Running: {' '.join(cmd)}")

    result = subprocess.run(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True
    )

    for line in result.stdout.splitlines():
        line = line.strip()
        if line:
            logger.debug(f"[pip] {line}")

    return result.returncode, result.stdout


def get_outdated(excludes: set[str]) -> tuple[list[tuple[str, str, str]], list[str], list[str]]:
    """
    Return (packages, skipped_excluded, skipped_system).
    Prints a live spinner while pip queries PyPI.
    """
    print("  querying PyPI", end="", flush=True)

    cmd = [sys.executable, "-m", "pip", "list", "--outdated", "--format=columns"]
    logger.debug(f"Running: {' '.join(cmd)}")

    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )

    spinner = ["|", "/", "─", "\\"]
    spin_i = 0
    lines = []

    for raw_line in proc.stdout:
        print(f"\r  querying PyPI {spinner[spin_i % len(spinner)]}", end="", flush=True)
        spin_i += 1
        stripped = raw_line.strip()
        if stripped:
            logger.debug(f"[pip] {stripped}")
            lines.append(stripped)

    proc.wait()
    print("\r" + " " * 40 + "\r", end="", flush=True)

    packages = []
    skipped_excluded = []
    skipped_system = []

    for line in lines[2:]:  # skip header rows
        parts = line.split()
        if len(parts) < 3:
            continue
        name, current, latest = parts[0], parts[1], parts[2]

        if name.lower() in excludes:
            skipped_excluded.append(name)
            logger.debug(f"Skipping {name} — in exclude list")
            continue

        if is_system_package(name):
            skipped_system.append(name)
            logger.debug(f"Skipping {name} — system/pacman owned (/usr/lib/)")
            continue

        packages.append((name, current, latest))

    return packages, skipped_excluded, skipped_system


def has_conflict(output: str) -> bool:
    return "ERROR: pip's dependency resolver" in output


def extract_broken(output: str) -> list[str]:
    """Extract package names pip reports as broken by a conflicting install."""
    return list({
        m.group(1)
        for line in output.splitlines()
        if "requires" in line
        for m in [re.search(r"^(\S+)", line)]
        if m
    })


# ── Upgrade Logic ──────────────────────────────────────────────────────────────

def upgrade_package(package: str, current_version: str) -> str:
    """
    Upgrade a package. Returns one of:
    'ok' | 'conflict' | 'failed' | 'rollback_failed'
    """
    logger.debug(f"{'─' * 50}")
    logger.debug(f"Upgrading {package} (current: {current_version})")

    exit_code, output = run_pip(
        "install", "--break-system-packages", "--upgrade", "-v", package
    )

    if exit_code != 0:
        logger.warning(f"  pip exited {exit_code} for {package}")
        return "failed"

    if has_conflict(output):
        broken = extract_broken(output)
        logger.debug(f"Conflict in {package} — broken: {broken}")
        logger.info(f"  ⚠️  Conflict — rolling back to {current_version} (breaks: {', '.join(broken)})")

        rb_code, rb_output = run_pip(
            "install", "--break-system-packages", "-v", f"{package}=={current_version}"
        )

        if rb_code == 0 and ("Successfully installed" in rb_output or "already satisfied" in rb_output.lower()):
            return "conflict"
        else:
            logger.debug(f"Rollback failed for {package}")
            return "rollback_failed"

    return "ok"


# ── Main ───────────────────────────────────────────────────────────────────────

def main():
    logger.info(f"🕐 Started : {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    logger.info(f"📄 Log file: {LOG_FILE}")
    logger.info("")

    # Load exclusions
    excludes = load_excludes()
    if excludes:
        logger.info(f"🚫 Exclude list ({len(excludes)}): {', '.join(sorted(excludes))}")
        logger.info("")

    logger.info("🔍 Checking for outdated packages...")
    packages, skipped_excluded, skipped_system = get_outdated(excludes)

    if skipped_system:
        logger.info(f"  🏛️  Skipped (system/pacman): {', '.join(skipped_system)}")
    if skipped_excluded:
        logger.info(f"  🚫 Skipped (excluded)      : {', '.join(skipped_excluded)}")
    if skipped_system or skipped_excluded:
        logger.info("")

    if not packages:
        logger.info("✅ All packages are up to date.")
        return 0

    # Column widths
    name_w = max(max(len(n) for n, *_ in packages), 7)
    cur_w  = max(max(len(c) for _, c, *_ in packages), 7)

    logger.info(f"📦 {len(packages)} package(s) to upgrade:\n")
    logger.info(f"   {'Package':<{name_w}}  {'Current':>{cur_w}}  {'Latest'}")
    logger.info(f"   {'─' * name_w}  {'─' * cur_w}  {'─' * 10}")
    for name, cur, latest in packages:
        logger.info(f"   {name:<{name_w}}  {cur:>{cur_w}}  {latest}")
    logger.info("")

    results = {"ok": [], "conflict": [], "failed": [], "rollback_failed": []}
    total_skipped = len(skipped_excluded) + len(skipped_system)

    for name, current_version, latest_version in packages:
        logger.info(f"⬆️  {name}  {current_version} → {latest_version}")
        status = upgrade_package(name, current_version)
        results[status].append(name)

        icons  = {"ok": "✅", "conflict": "↩️ ", "failed": "❌", "rollback_failed": "💥"}
        labels = {"ok": "upgraded", "conflict": "rolled back", "failed": "failed", "rollback_failed": "rollback failed"}
        logger.info(f"  {icons[status]} {labels[status]}")

    # ── Summary ────────────────────────────────────────────────────────────────
    logger.info("")
    logger.info("━" * 42)
    logger.info("📋 Summary")
    logger.info("━" * 42)
    logger.info(f"  🔢 Total     : {len(packages) + total_skipped}")
    logger.info(f"  ⏭️  Skipped   : {total_skipped}")
    logger.info(f"  ✅ Upgraded  : {len(results['ok'])}")
    logger.info(f"  ↩️  Conflicts : {len(results['conflict'])}")
    logger.info(f"  ❌ Failed    : {len(results['failed'])}")
    logger.info(f"  💥 Rb Failed : {len(results['rollback_failed'])}")

    for label, pkgs in results.items():
        if pkgs and label != "ok":
            logger.info(f"\n  {label.upper()}:")
            for p in pkgs:
                logger.info(f"    • {p}")

    logger.info("━" * 42)
    logger.info(f"🕐 Finished : {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    logger.info(f"📄 Log file : {LOG_FILE}")

    return 0 if not results["failed"] and not results["rollback_failed"] else 1


if __name__ == "__main__":
    sys.exit(main())