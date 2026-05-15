"""HDBSCAN clustering + canonical head + LSI role assignment.

Reads embeddings from Supabase, runs HDBSCAN, and assigns intra-cluster roles
following the conventions in docs/adr/0001-three-axis-taxonomy.md.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Any
from uuid import UUID

import hdbscan
import numpy as np
import structlog
from supabase import Client

from .deps import get_settings
from .schemas import (
    ClusterMember,
    ClusterMemberRole,
    ClusterPayload,
    ClusterResponse,
)

log = structlog.get_logger()


# ---------------------------------------------------------------------------
# Data fetched from Supabase
# ---------------------------------------------------------------------------


@dataclass(slots=True)
class _KeywordRow:
    id: UUID
    keyword: str
    embedding: np.ndarray
    volume: int
    kd: float | None


def _fetch_keyword_rows(
    supabase: Client,
    keyword_classification_ids: list[UUID],
) -> list[_KeywordRow]:
    """Fetch embeddings + keyword text + volume/kd for the given classifications."""

    if not keyword_classification_ids:
        return []

    ids = [str(x) for x in keyword_classification_ids]

    # Pull classifications with their embeddings
    classifications_resp = (
        supabase.table("keyword_classifications")
        .select("id, raw_keyword_id, embedding")
        .in_("id", ids)
        .execute()
    )
    classifications: list[dict[str, Any]] = classifications_resp.data or []

    if not classifications:
        return []

    raw_keyword_ids = [str(c["raw_keyword_id"]) for c in classifications]

    raw_resp = (
        supabase.table("raw_keywords")
        .select("id, keyword, volume, kd")
        .in_("id", raw_keyword_ids)
        .execute()
    )
    raw_by_id = {row["id"]: row for row in (raw_resp.data or [])}

    out: list[_KeywordRow] = []
    for c in classifications:
        emb = c.get("embedding")
        if not emb:
            continue
        raw = raw_by_id.get(c["raw_keyword_id"])
        if raw is None:
            continue
        try:
            vec = _parse_pgvector(emb)
        except Exception as e:
            log.warning("could_not_parse_embedding", id=c["id"], error=str(e))
            continue

        out.append(
            _KeywordRow(
                id=UUID(c["id"]),
                keyword=raw["keyword"],
                embedding=vec,
                volume=int(raw.get("volume") or 0),
                kd=float(raw["kd"]) if raw.get("kd") is not None else None,
            )
        )

    return out


def _parse_pgvector(value: Any) -> np.ndarray:
    """pgvector returns embeddings as either lists (preferred) or '[1,2,3]' strings."""
    if isinstance(value, list):
        return np.asarray(value, dtype=np.float32)
    if isinstance(value, str):
        cleaned = value.strip().lstrip("[").rstrip("]")
        return np.asarray([float(x) for x in cleaned.split(",")], dtype=np.float32)
    raise ValueError(f"unsupported embedding shape: {type(value)}")


# ---------------------------------------------------------------------------
# Role assignment
# ---------------------------------------------------------------------------


def _assign_role(
    keyword: str,
    head_keyword: str,
    distance_from_centroid: float,
    distance_to_head_text_overlap: float,
    lsi_threshold: float,
    long_tail_threshold: float,
) -> ClusterMemberRole:
    """Assign a role to a non-head member.

    - lsi_variant: very close to head term AND substantial token overlap
      (e.g., "healthcare seo agency" vs "seo agency for healthcare").
    - modifier: includes location/qualifier additions (e.g., "in mumbai").
    - long_tail_supporting: distinct but related (longer or more specific).
    - long_tail_supporting is the default fallback.
    """

    # Locality/qualifier signal => modifier
    qualifier_tokens = {
        "in", "near", "for", "with", "without", "vs",
        "best", "top", "cheap", "affordable", "premium",
    }
    head_tokens = set(head_keyword.lower().split())
    keyword_tokens = set(keyword.lower().split())
    extra_tokens = keyword_tokens - head_tokens
    if extra_tokens and extra_tokens.issubset(qualifier_tokens):
        return "modifier"

    if distance_from_centroid < lsi_threshold and distance_to_head_text_overlap >= 0.7:
        return "lsi_variant"

    if distance_from_centroid < long_tail_threshold:
        return "long_tail_supporting"

    return "long_tail_supporting"


def _token_overlap(a: str, b: str) -> float:
    """Jaccard overlap of token sets."""
    ta = set(a.lower().split())
    tb = set(b.lower().split())
    if not ta or not tb:
        return 0.0
    return len(ta & tb) / len(ta | tb)


# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------


def cluster_keywords(
    supabase: Client,
    client_id: UUID,
    pipeline_run_id: UUID,
    keyword_classification_ids: list[UUID],
    min_cluster_size_override: int | None = None,
) -> ClusterResponse:
    settings = get_settings()
    rows = _fetch_keyword_rows(supabase, keyword_classification_ids)

    if len(rows) < settings.min_cluster_size_floor:
        log.info("not_enough_keywords_to_cluster", count=len(rows))
        return ClusterResponse(
            client_id=client_id,
            pipeline_run_id=pipeline_run_id,
            clusters=[],
            unclustered_count=len(rows),
            parameters={"reason": "below_floor"},
        )

    # Compute a sensible min_cluster_size: max(floor, sqrt(N/100))
    auto_min = max(
        settings.min_cluster_size_floor,
        int(math.sqrt(len(rows) / 100.0)) or settings.min_cluster_size_floor,
    )
    min_cluster_size = min_cluster_size_override or auto_min

    embeddings = np.stack([r.embedding for r in rows]).astype(np.float64)

    clusterer = hdbscan.HDBSCAN(
        metric="euclidean",  # cosine via normalization below would also work; HDBSCAN officially recommends euclidean
        min_cluster_size=min_cluster_size,
        min_samples=None,  # let HDBSCAN choose
        cluster_selection_method="eom",
    )

    # L2-normalize so euclidean distance approximates cosine distance
    norms = np.linalg.norm(embeddings, axis=1, keepdims=True)
    norms[norms == 0] = 1.0
    embeddings_normed = embeddings / norms

    labels = clusterer.fit_predict(embeddings_normed)

    clusters_out: list[ClusterPayload] = []
    unclustered_count = 0

    unique_labels = sorted(set(int(x) for x in labels))
    for label in unique_labels:
        if label == -1:
            unclustered_count = int((labels == -1).sum())
            continue

        member_indices = [i for i, lbl in enumerate(labels) if lbl == label]
        member_rows = [rows[i] for i in member_indices]
        member_vecs = embeddings_normed[member_indices]

        # Centroid + distance per member
        centroid = member_vecs.mean(axis=0)
        centroid /= max(np.linalg.norm(centroid), 1e-9)
        distances = np.linalg.norm(member_vecs - centroid, axis=1)

        # Canonical head: highest volume + lowest KD + lowest centroid distance,
        # composite score with simple weights.
        def head_score(idx_in_member: int) -> float:
            r = member_rows[idx_in_member]
            d = float(distances[idx_in_member])
            volume_term = math.log1p(r.volume) * 1.0
            kd_term = (r.kd or 50.0) * 0.05
            distance_term = d * 5.0
            return volume_term - kd_term - distance_term

        head_local_idx = max(range(len(member_rows)), key=head_score)
        head_row = member_rows[head_local_idx]
        head_distance = float(distances[head_local_idx])

        members_out: list[ClusterMember] = []
        for i, r in enumerate(member_rows):
            d = float(distances[i])
            if i == head_local_idx:
                role: ClusterMemberRole = "head"
            else:
                overlap = _token_overlap(r.keyword, head_row.keyword)
                role = _assign_role(
                    keyword=r.keyword,
                    head_keyword=head_row.keyword,
                    distance_from_centroid=d,
                    distance_to_head_text_overlap=overlap,
                    lsi_threshold=settings.lsi_distance_threshold,
                    long_tail_threshold=settings.long_tail_distance_threshold,
                )
            members_out.append(
                ClusterMember(
                    keyword_classification_id=r.id,
                    keyword=r.keyword,
                    volume=r.volume,
                    kd=r.kd,
                    role=role,
                    distance_from_centroid=d,
                )
            )

        total_volume = int(sum((r.volume or 0) for r in member_rows))
        kds = [r.kd for r in member_rows if r.kd is not None]
        avg_kd = float(np.mean(kds)) if kds else None

        clusters_out.append(
            ClusterPayload(
                canonical_head_term=head_row.keyword,
                members=members_out,
                keyword_count=len(member_rows),
                total_volume=total_volume,
                avg_kd=avg_kd,
            )
        )

    return ClusterResponse(
        client_id=client_id,
        pipeline_run_id=pipeline_run_id,
        clusters=clusters_out,
        unclustered_count=unclustered_count,
        parameters={
            "algorithm": "hdbscan",
            "min_cluster_size": min_cluster_size,
            "min_cluster_size_floor": settings.min_cluster_size_floor,
            "input_count": len(rows),
            "cluster_count": len(clusters_out),
            "lsi_threshold": settings.lsi_distance_threshold,
            "long_tail_threshold": settings.long_tail_distance_threshold,
        },
    )
