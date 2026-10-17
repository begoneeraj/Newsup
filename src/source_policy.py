"""Deployment allowlist; access to a feed is not evidence of publication rights.

Development retains current sources. A production run must explicitly name
each rights-reviewed source in NEWS_SOURCE_ALLOWLIST (comma separated).
This records an operator decision; it is not a legal licence checker.
"""
import logging
import os

logger = logging.getLogger(__name__)

def source_allowed(name: str) -> bool:
    if os.environ.get('NEWS_DEPLOYMENT_MODE', 'development').lower() != 'production':
        return True
    approved = {part.strip() for part in os.environ.get('NEWS_SOURCE_ALLOWLIST', '').split(',') if part.strip()}
    allowed = name in approved
    if not allowed:
        logger.warning('Source %s skipped: not in the production rights-review allowlist', name)
    return allowed
