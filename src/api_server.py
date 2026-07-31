"""HTTP entry point for the Groq-backed confidence classifier, exposed as a
standalone service (Cloud Run, or any container host) that the TypeScript
crisisClassifier Cloud Function calls via GROQ_PROCESSOR_URL. Also serves
GET /underreported-topics, the read side of pipeline.underreported_topics
(the daily cron job writes to Supabase; this just reads it back as JSON) --
grouped into the same service rather than a second deployment, since this
is already the one part of this Python codebase meant to run as an
always-on HTTP service.

This is separate from main.py, which is the batch/cron ingestion pipeline
(GitHub Actions, no persistent process).

Run locally with:
    uvicorn api_server:app --reload --port 8080
"""

from __future__ import annotations

import logging
import os

from fastapi import FastAPI, Header, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from pydantic import BaseModel, field_validator
from slowapi import Limiter
from slowapi.errors import RateLimitExceeded
from slowapi.middleware import SlowAPIMiddleware
from slowapi.util import get_remote_address
from starlette.exceptions import HTTPException as StarletteHTTPException
from starlette.responses import JSONResponse

from ai_processor.groq_processor import process_confidence_classification
from database.supabase_client import fetch_underreported_topic_points, fetch_underreported_topics
from models.schemas import ConfidenceClassificationSchema
from pipeline.underreported_topics import state_centroid
from secrets_check import check_required_env_vars
from validation import clean_text_field

logger = logging.getLogger("newsup.api_server")

check_required_env_vars()

# Optional shared-secret check. Unset by default (fine for local dev / an
# already-private Cloud Run service behind IAM); set API_SHARED_SECRET in
# production if this endpoint is ever exposed without another auth layer in
# front of it, and pass the same value as a GROQ_PROCESSOR_API_KEY env var
# on the Firebase Functions side (see crisisClassifier.ts).
_API_SHARED_SECRET = os.environ.get("API_SHARED_SECRET")

app = FastAPI(title="newsup-classifier")

# Per-IP rate limiting (slowapi/limits). Each route below opts in with its
# own @limiter.limit(...) so limits stay per-endpoint rather than global.
limiter = Limiter(key_func=get_remote_address)
app.state.limiter = limiter
app.add_middleware(SlowAPIMiddleware)


@app.exception_handler(RateLimitExceeded)
def rate_limit_handler(request: Request, exc: RateLimitExceeded) -> JSONResponse:
    return JSONResponse(status_code=429, content={"detail": "Rate limit exceeded, try again later"})


@app.exception_handler(RequestValidationError)
def validation_exception_handler(request: Request, exc: RequestValidationError) -> JSONResponse:
    logger.warning("Validation error on %s", request.url.path)
    return JSONResponse(status_code=400, content={"detail": "Invalid request"})


@app.exception_handler(StarletteHTTPException)
def http_exception_handler(request: Request, exc: StarletteHTTPException) -> JSONResponse:
    # Preserve intentional, already-generic error responses raised by our own
    # route handlers (e.g. the 401 below); collapse anything else to a
    # generic message per status class so internal details never leak.
    if exc.status_code >= 500:
        logger.exception("Unhandled server error on %s", request.url.path)
        return JSONResponse(status_code=500, content={"detail": "Something went wrong"})
    if isinstance(exc.detail, str):
        return JSONResponse(status_code=exc.status_code, content={"detail": exc.detail})
    return JSONResponse(status_code=exc.status_code, content={"detail": "Invalid request"})


@app.exception_handler(Exception)
def unhandled_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    logger.exception("Unhandled error on %s", request.url.path)
    return JSONResponse(status_code=500, content={"detail": "Something went wrong"})


class ClassifyRequest(BaseModel):
    title: str
    url: str = ""
    summary: str = ""
    content: str = ""

    @field_validator("title", "summary", "content")
    @classmethod
    def _clean_text(cls, value: str, info) -> str:
        return clean_text_field(value, field_name=info.field_name)


@app.post("/classify", response_model=ConfidenceClassificationSchema)
@limiter.limit("10/minute")
def classify(
    request: Request,
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


@app.get("/underreported-topics")
@limiter.limit("30/minute")
def underreported_topics(request: Request, limit: int = 50, chart_days: int = 14) -> list[dict]:
    """Structured JSON for the Underreported Topics feature — ordered by
    gap_score descending. Each topic includes its recent daily trend
    (chart_data) and, when its matched niche items named a state, map pins
    (map_data) resolved via STATE_CENTROIDS. Every number here was computed
    by pipeline.underreported_topics from real fetched counts, not guessed —
    see that module's docstring.
    """
    topics = fetch_underreported_topics(limit=limit)
    response = []
    for topic in topics:
        points = fetch_underreported_topic_points(topic["id"], limit=chart_days)
        latest = points[-1] if points else {}
        states = latest.get("states") or []

        response.append(
            {
                "topic_slug": topic["topic_slug"],
                "title": topic["title"],
                "data_source": topic.get("data_source"),
                "gap_score": topic.get("current_gap_score"),
                "niche_count": topic.get("current_niche_count"),
                "mainstream_count": topic.get("current_mainstream_count"),
                "last_computed_at": topic.get("last_computed_at"),
                "narrative_summary": topic.get("latest_narrative_summary"),
                "genz_summary": topic.get("latest_narrative_genz_summary"),
                "example_niche_sources": latest.get("example_niche_sources") or [],
                "example_mainstream_sources": latest.get("example_mainstream_sources") or [],
                "chart_data": [
                    {
                        "date": p["recorded_date"],
                        "niche_count": p["niche_count"],
                        "mainstream_count": p["mainstream_count"],
                        "hindi_mainstream_count": p["hindi_mainstream_count"],
                        "tamil_mainstream_count": p["tamil_mainstream_count"],
                        "gap_score": p["gap_score"],
                    }
                    for p in points
                ],
                "map_data": [
                    {"state": state, "lat": centroid[0], "lon": centroid[1]}
                    for state in states
                    if (centroid := state_centroid(state)) is not None
                ],
            }
        )
    return response
