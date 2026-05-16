"""FastAPI entrypoint for the clustering worker."""

from __future__ import annotations

import logging

import structlog
from fastapi import Depends, FastAPI, Header, HTTPException, status

from .clustering import cluster_keywords
from .deps import get_settings, get_supabase
from .schemas import ClusterRequest, ClusterResponse, HealthResponse


logging.basicConfig(level=logging.INFO)
structlog.configure(
    processors=[
        structlog.contextvars.merge_contextvars,
        structlog.processors.add_log_level,
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.JSONRenderer(),
    ]
)
log = structlog.get_logger()


app = FastAPI(
    title="SEO-Tools Clustering Worker",
    version="0.1.0",
    description=(
        "Internal microservice that runs HDBSCAN on keyword embeddings stored "
        "in Supabase pgvector, returning clusters with canonical head terms "
        "and intra-cluster role assignments."
    ),
)


def _check_auth(authorization: str | None) -> None:
    settings = get_settings()
    if not settings.worker_auth_token:
        return
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="missing bearer token",
        )
    if authorization.removeprefix("Bearer ").strip() != settings.worker_auth_token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="invalid bearer token",
        )


@app.get("/health", response_model=HealthResponse, tags=["meta"])
def health() -> HealthResponse:
    return HealthResponse()


@app.post(
    "/cluster",
    response_model=ClusterResponse,
    tags=["clustering"],
    summary="Cluster a set of keyword classifications via HDBSCAN.",
)
def cluster(
    body: ClusterRequest,
    authorization: str | None = Header(default=None),
) -> ClusterResponse:
    _check_auth(authorization)

    log.info(
        "cluster_request_received",
        client_id=str(body.client_id),
        pipeline_run_id=str(body.pipeline_run_id),
        input_count=len(body.keyword_classification_ids),
    )

    try:
        supabase = get_supabase()
    except Exception as exc:
        log.error("supabase_init_failed", error=str(exc), exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"Supabase client init failed: {exc}",
        )

    result = cluster_keywords(
        supabase=supabase,
        client_id=body.client_id,
        pipeline_run_id=body.pipeline_run_id,
        keyword_classification_ids=body.keyword_classification_ids,
        min_cluster_size_override=body.min_cluster_size_override,
    )

    log.info(
        "cluster_response",
        client_id=str(body.client_id),
        pipeline_run_id=str(body.pipeline_run_id),
        clusters=len(result.clusters),
        unclustered=result.unclustered_count,
    )

    return result
