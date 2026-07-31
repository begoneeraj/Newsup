"""Fails fast if required secrets are missing from the environment. Call
check_required_env_vars() as the first thing an entry point does, before any
fetcher/pipeline/API logic runs — see src/main.py's main() and the top of
src/api_server.py.
"""

from __future__ import annotations

import os

REQUIRED_ENV_VARS = [
    "GROQ_API_KEY",
    "SUPABASE_URL",
    "SUPABASE_SERVICE_KEY",
    "NEWSDATA_API_KEY",
    "MEDIASTACK_API_KEY",
]


def check_required_env_vars() -> None:
    missing = [name for name in REQUIRED_ENV_VARS if not os.environ.get(name)]
    if missing:
        raise RuntimeError(
            "Missing required environment variable(s): "
            f"{', '.join(missing)}. Set them in your .env file (see "
            ".env.example) before starting the pipeline."
        )


if __name__ == "__main__":
    check_required_env_vars()
