"""Reads a pip-audit JSON report and decides whether the run should fail.

Why this exists: pip-audit's own JSON output (see requirements-audit.sh)
carries no severity field at all -- just id/aliases/fix_versions/description
-- so "fail only on HIGH/CRITICAL" can't be done from that file alone. This
script fills the gap by looking each finding's id up against the OSV API
(https://api.osv.dev/v1/vulns/{id}), which does publish a CVSS vector for
vulnerabilities that have one, and buckets severity from that vector using
the `cvss` package.

Not every advisory carries a CVSS score (many PyPI-sourced PYSEC entries
don't). Rather than silently drop those, they're printed in their own
"UNRATED" section so a human still sees them, but they don't fail the build
by themselves -- only a confirmed HIGH/CRITICAL CVSS score does. This is a
judgment call (see requirements-audit.sh's header comment); flip
FAIL_ON_UNRATED below if you'd rather fail closed on anything unrated.
"""

from __future__ import annotations

import json
import sys
import urllib.error
import urllib.request

FAIL_ON_UNRATED = False

OSV_URL = "https://api.osv.dev/v1/vulns/{id}"
REQUEST_TIMEOUT_SECONDS = 10


def _fetch_severity_vector(vuln_id: str) -> str | None:
    try:
        with urllib.request.urlopen(OSV_URL.format(id=vuln_id), timeout=REQUEST_TIMEOUT_SECONDS) as resp:
            data = json.load(resp)
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
        print(f"  warning: couldn't fetch severity for {vuln_id} from OSV ({exc}); treating as unrated", file=sys.stderr)
        return None

    for entry in data.get("severity") or []:
        if entry.get("type", "").startswith("CVSS"):
            return entry["score"]
    return None


def _bucket_from_vector(vector: str) -> str | None:
    from cvss import CVSS2, CVSS3, CVSS4  # local import: only needed when a vector is present

    try:
        if vector.startswith("CVSS:4"):
            score = CVSS4(vector)
        elif vector.startswith("CVSS:3"):
            score = CVSS3(vector)
        else:
            score = CVSS2(vector)
        return score.severities()[0].upper()
    except Exception as exc:  # cvss raises its own error types per version
        print(f"  warning: couldn't parse CVSS vector {vector!r} ({exc}); treating as unrated", file=sys.stderr)
        return None


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: audit_severity_gate.py <pip-audit-json-report>", file=sys.stderr)
        return 2

    with open(sys.argv[1], encoding="utf-8") as f:
        report = json.load(f)

    severity_cache: dict[str, str | None] = {}
    buckets: dict[str, list[tuple[str, str, str]]] = {
        "CRITICAL": [], "HIGH": [], "MEDIUM": [], "LOW": [], "NONE": [], "UNRATED": [],
    }

    for dependency in report.get("dependencies", []):
        pkg = dependency["name"]
        pkg_version = dependency["version"]
        for vuln in dependency.get("vulns", []):
            vuln_id = vuln["id"]
            if vuln_id not in severity_cache:
                vector = _fetch_severity_vector(vuln_id)
                severity_cache[vuln_id] = _bucket_from_vector(vector) if vector else None
            bucket = severity_cache[vuln_id] or "UNRATED"
            buckets.setdefault(bucket, []).append((pkg, pkg_version, vuln_id))

    blocking_buckets = ["CRITICAL", "HIGH"] + (["UNRATED"] if FAIL_ON_UNRATED else [])
    found_blocking = False

    for bucket in ["CRITICAL", "HIGH", "MEDIUM", "LOW", "NONE", "UNRATED"]:
        findings = buckets.get(bucket, [])
        if not findings:
            continue
        print(f"\n{bucket} ({len(findings)}):")
        for pkg, pkg_version, vuln_id in findings:
            print(f"  - {pkg} {pkg_version}: {vuln_id}")
        if bucket in blocking_buckets:
            found_blocking = True

    if found_blocking:
        print("\nFAIL: HIGH or CRITICAL severity vulnerabilities found (see above).", file=sys.stderr)
        return 1

    print("\nOK: no HIGH/CRITICAL severity vulnerabilities found.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
