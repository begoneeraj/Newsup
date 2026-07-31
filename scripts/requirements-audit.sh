#!/usr/bin/env bash
# Audits requirements.txt for known vulnerabilities via pip-audit, then gates
# on severity (see scripts/audit_severity_gate.py's header for why that's a
# separate step: pip-audit's own JSON report carries no severity field, so
# HIGH/CRITICAL-only gating needs an extra OSV lookup pip-audit doesn't do).
#
# Usage: scripts/requirements-audit.sh
# Exit code: 0 if no HIGH/CRITICAL vulnerabilities found, 1 otherwise.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

pip install --quiet pip-audit cvss

echo "Running pip-audit against requirements.txt..."
# pip-audit itself exits 1 when it finds ANY known vulnerability -- that's
# expected here (this isn't the final gate, severity is), so don't let `set
# -e` kill the script on that exit code.
set +e
python -m pip_audit -r requirements.txt --vulnerability-service osv --format json --output audit_report.json
pip_audit_status=$?
set -e

if [ ! -s audit_report.json ]; then
    echo "pip-audit produced no report (unexpected failure, status=$pip_audit_status)." >&2
    exit 1
fi

python scripts/audit_severity_gate.py audit_report.json
