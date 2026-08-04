"""Fails fast if required secrets are missing from the environment. Call
check_required_env_vars() as the first thing an entry point does, before any
fetcher/pipeline/API logic runs — see src/main.py's main() and the top of
src/api_server.py.
"""

from __future__ import annotations

import os
from typing import Iterable

# Needed by every entry point: Groq classification and Supabase storage run
# regardless of which --sources are requested.
REQUIRED_ENV_VARS = [
    "GROQ_API_KEY",
    "SUPABASE_URL",
    "SUPABASE_SERVICE_KEY",
]

# Only needed when the corresponding --sources value is actually requested
# (see main.py's SOURCE_FETCHERS) — e.g. NEWSDATA_API_KEY/MEDIASTACK_API_KEY
# are read exclusively by the "news" source's fetchers, so cron jobs running
# other sources (gov_alerts, youtube, social, reddit) never have them set.
SOURCE_REQUIRED_ENV_VARS = {
    "news": ["NEWSDATA_API_KEY", "MEDIASTACK_API_KEY"],
}


def check_required_env_vars(sources: Iterable[str] = ()) -> None:
    required = list(REQUIRED_ENV_VARS)
    for source in sources:
        required.extend(SOURCE_REQUIRED_ENV_VARS.get(source, []))
    missing = [name for name in required if not os.environ.get(name)]
    if missing:
        raise RuntimeError(
            "Missing required environment variable(s): "
            f"{', '.join(missing)}. Set them in your .env file (see "
            ".env.example) before starting the pipeline."
        )


if __name__ == "__main__":
    check_required_env_vars()
