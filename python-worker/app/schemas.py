"""Pydantic request and response models for the worker."""

from __future__ import annotations

from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field


# ---------------------------------------------------------------------------
# Clustering request: n8n passes the pipeline run + classification IDs to cluster
# ---------------------------------------------------------------------------


class ClusterRequest(BaseModel):
    client_id: UUID
    pipeline_run_id: UUID
    keyword_classification_ids: list[UUID] = Field(
        ...,
        description=(
            "Keyword classification rows whose embeddings should be clustered. "
            "Worker reads embeddings from Supabase via service role."
        ),
    )
    min_cluster_size_override: int | None = Field(
        None,
        description="Override the auto-computed min_cluster_size. Useful for testing.",
    )


# ---------------------------------------------------------------------------
# Clustering response
# ---------------------------------------------------------------------------


ClusterMemberRole = Literal["head", "lsi_variant", "long_tail_supporting", "modifier"]


class ClusterMember(BaseModel):
    keyword_classification_id: UUID
    keyword: str
    volume: int | None = None
    kd: float | None = None
    role: ClusterMemberRole
    distance_from_centroid: float


class ClusterPayload(BaseModel):
    canonical_head_term: str
    members: list[ClusterMember]
    keyword_count: int
    total_volume: int
    avg_kd: float | None


class ClusterResponse(BaseModel):
    client_id: UUID
    pipeline_run_id: UUID
    clusters: list[ClusterPayload]
    unclustered_count: int = Field(
        0,
        description="HDBSCAN noise points that did not join any cluster.",
    )
    parameters: dict = Field(
        default_factory=dict,
        description="Algorithm parameters actually used for this run.",
    )


# ---------------------------------------------------------------------------
# Health
# ---------------------------------------------------------------------------


class HealthResponse(BaseModel):
    ok: bool = True
    version: str = "0.1.0"
