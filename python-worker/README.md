# Clustering worker

Internal microservice that runs HDBSCAN on keyword embeddings stored in Supabase pgvector, returning clusters with canonical head terms and intra-cluster role assignments (`head` / `lsi_variant` / `long_tail_supporting` / `modifier`).

Called by n8n WF-03.

## Endpoints

- `GET  /health` — liveness check.
- `POST /cluster` — body = `ClusterRequest`. Returns `ClusterResponse`.

See `app/schemas.py` for the full payload shape.

## Local run

```bash
python -m venv .venv
source .venv/bin/activate                  # Windows: .venv\Scripts\Activate.ps1
pip install -r requirements.txt
cp ../.env.example .env                    # then fill in SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, WORKER_AUTH_TOKEN
uvicorn app.main:app --reload --port 8080
```

## Docker

```bash
docker build -t seo-tools-cluster-worker .
docker run --rm -p 8080:8080 --env-file .env seo-tools-cluster-worker
```

## Deploy

### Cloud Run

```bash
gcloud builds submit --tag gcr.io/PROJECT/seo-tools-cluster-worker
gcloud run deploy seo-tools-cluster-worker \
    --image gcr.io/PROJECT/seo-tools-cluster-worker \
    --region us-central1 \
    --platform managed \
    --set-env-vars SUPABASE_URL=...,SUPABASE_SERVICE_ROLE_KEY=...,WORKER_AUTH_TOKEN=... \
    --memory 1Gi \
    --cpu 1 \
    --concurrency 4 \
    --timeout 300 \
    --no-allow-unauthenticated
```

### Railway

`railway up` from this directory. Set env vars in the Railway dashboard.

### Fly.io

`fly launch` and edit the generated `fly.toml` to set the Dockerfile path.

## Auth

If `WORKER_AUTH_TOKEN` is set, every `/cluster` request must include `Authorization: Bearer $TOKEN`. n8n stores this token as a credential and attaches it via the HTTP Request node.

## Tuning

- `min_cluster_size` auto = `max(5, sqrt(N / 100))`. Override via request payload.
- `lsi_distance_threshold` = 0.15 (env var: `LSI_DISTANCE_THRESHOLD`). Distance below which a cluster member is considered a semantic equivalent of the head term.
- `long_tail_distance_threshold` = 0.35 (env var: `LONG_TAIL_DISTANCE_THRESHOLD`). Distance below which a member is a long-tail support keyword; beyond this is fringe.

## Memory profile

HDBSCAN on 5,000 768-dim vectors: ~250 MB RSS. The Cloud Run 1 GB instance handles up to ~30k keywords per run comfortably. Larger runs should batch.

## Observability

Structured JSON logs via `structlog`. Cloud Run / Railway will surface them in their respective log viewers. No external metrics emitter in Phase 1 (add Prometheus exporter in Phase 4 if SaaS-ifying).
