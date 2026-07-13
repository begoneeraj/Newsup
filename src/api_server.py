"""HTTP entry point for the Groq-backed confidence classifier, exposed as a
standalone service (Cloud Run, or any container host) that the TypeScript
crisisClassifier Cloud Function calls via GROQ_PROCESSOR_URL.

This is separate from main.py, which is the batch/cron ingestion pipeline
(GitHub Actions, no persistent process). api_server.py is the one part of
this Python codebase meant to run as an always-on HTTP service.

Run locally with:
    uvicorn api_server:app --reload --port 8080
"""

from __future__ import annotations

import logging
import os

from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel

from ai_processor.groq_processor import process_confidence_classification
from models.schemas import ConfidenceClassificationSchema

logger = logging.getLogger("newsup.api_server")

# Optional shared-secret check. Unset by default (fine for local dev / an
# already-private Cloud Run service behind IAM); set API_SHARED_SECRET in
# production if this endpoint is ever exposed without another auth layer in
# front of it, and pass the same value as a GROQ_PROCESSOR_API_KEY env var
# on the Firebase Functions side (see crisisClassifier.ts).
_API_SHARED_SECRET = os.environ.get("API_SHARED_SECRET")

app = FastAPI(title="newsup-classifier")


class ClassifyRequest(BaseModel):
    title: str
    url: str = ""
    summary: str = ""
    content: str = ""


@app.post("/classify", response_model=ConfidenceClassificationSchema)
def classify(
    body: ClassifyRequest,
    x_api_key: str | None = Header(default=None),
) -> ConfidenceClassificationSchema:
    if _API_SHARED_SECRET and x_api_key != _API_SHARED_SECRET:
        raise HTTPException(status_code=401, detail="Invalid or missing X-API-Key")

    result = process_confidence_classification(
        title=body.title,
        summary=body.summary,
        content=body.content,
    )

    logger.info(
        "Classified article url=%s confidence=%d label=%s",
        body.url,
        result.confidence,
        result.label,
    )

    return result


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}
