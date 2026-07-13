"""main.py and every src/ module import each other unqualified (e.g.
`from pipeline.public_events import ...`), which only resolves when src/ is
on sys.path — the same layout the GitHub Actions cron jobs get for free by
running `python src/main.py` from the repo root. Tests import src/ modules
directly rather than running main.py as a script, so they need this shim.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent / "src"))
