"""One-time import: parse an election manifesto (or budget document) PDF
into discrete govt_promises rows (Stage A of the Government Promises
Tracker evidence-trail expansion — see supabase/migrations/0013_...sql and
ai_processor.groq_processor.process_manifesto_promises).

Not scheduled — run manually once per manifesto/document you want to seed:

    python src/backfill_manifesto_promises.py path/to/manifesto.pdf \\
        --party "Some Party" --election-year 2029

Chunks by page (a manifesto page is short enough to fit one Groq call
comfortably) rather than a fixed character window, so a promise's
surrounding context on the page it appears on isn't split across chunks.
Upserts via the existing upsert_govt_promise (slug-based, same as the
per-article pipeline), so re-running this against the same PDF is safe —
matching project_slug rows are updated in place, not duplicated.
"""

from __future__ import annotations

import argparse
import logging

import pdfplumber

from ai_processor.groq_processor import process_manifesto_promises
from database.supabase_client import upsert_govt_promise

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("newsup.backfill_manifesto")


def _extract_page_chunks(pdf_path: str) -> list[str]:
    chunks: list[str] = []
    with pdfplumber.open(pdf_path) as pdf:
        for page in pdf.pages:
            text = (page.extract_text() or "").strip()
            if text:
                chunks.append(text)
    return chunks


def backfill_manifesto_promises(pdf_path: str, party: str, election_year: int) -> None:
    chunks = _extract_page_chunks(pdf_path)
    logger.info("Extracted %d text pages from %s", len(chunks), pdf_path)

    total_promises = 0
    for i, chunk in enumerate(chunks):
        promises = process_manifesto_promises(party, chunk)
        for promise in promises:
            data = promise.model_dump(mode="json")
            data["party"] = party
            data["election_year"] = election_year
            data["promise_source"] = "election_manifesto"
            upsert_govt_promise(data)
            total_promises += 1
            logger.info("Upserted manifesto promise: %s", promise.project_name)
        logger.info("Page %d/%d: %d promise(s) extracted", i + 1, len(chunks), len(promises))

    logger.info("Manifesto backfill complete: %d promises from %s (%s, %d)", total_promises, pdf_path, party, election_year)


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="One-time manifesto/budget-document promise backfill")
    parser.add_argument("pdf_path", help="Path to the manifesto or budget document PDF")
    parser.add_argument("--party", required=True, help="Party name (used as announcing_body and party)")
    parser.add_argument("--election-year", required=True, type=int, help="Election year this manifesto is for")
    return parser.parse_args()


if __name__ == "__main__":
    args = _parse_args()
    backfill_manifesto_promises(args.pdf_path, args.party, args.election_year)
