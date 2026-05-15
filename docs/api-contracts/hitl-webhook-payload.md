# HITL webhook payload contract

This is the **normalized contract** for human-in-the-loop interactions. Slack interactive cards, Telegram inline keyboards, and (in Phase 2) the in-app review dashboard all produce the same payload shape and POST to the same n8n webhook endpoint.

This decoupling means the UI can change without touching pipeline logic.

---

## Endpoint

```
POST {n8n_webhook_base}/hitl-decision
Content-Type: application/json
Authorization: Bearer {N8N_HITL_TOKEN}
```

---

## Request payload (channel -> n8n)

```jsonc
{
  "event_type": "hitl_decision",                  // "hitl_decision" | "cost_ceiling_decision" | "taxonomy_proposal_decision" | "drift_acknowledgment"
  "channel": "slack",                             // "slack" | "telegram" | "dashboard"
  "channel_message_id": "1234567890.123456",      // Slack ts, Telegram update_id, or dashboard event id
  "client_id": "<uuid>",                          // tenant the decision applies to
  "pipeline_run_id": "<uuid>",                    // run the decision belongs to (may be null for global events)
  "subject_type": "keyword",                      // "keyword" | "cluster" | "competitor_brand" | "pillar_assignment" | "niche_proposal" | "theme_proposal" | "config_value" | "cost_ceiling_breach" | "quality_drift"
  "subject_id": "<uuid>",                         // FK into the relevant table
  "decision": "approve",                          // "approve" | "reject" | "escalate" | "skip" | "extend_ceiling_by" | "abort_run"
  "decision_metadata": {                          // optional, decision-type-specific
    "extend_ceiling_by_usd": 10.0,                // for cost_ceiling decisions
    "new_pillar_name": "data-engineering",        // for taxonomy_proposal acceptance
    "reroute_to": "<uuid>"                        // for "reroute" decisions
  },
  "decided_by": {
    "channel_user_id": "U12345",                  // Slack user ID, Telegram user ID, or dashboard user ID
    "display_name": "Pranav",
    "role": "owner"                               // role from client_members.role
  },
  "notes": "Comparison content — keeping per strategy.",  // optional free text
  "submitted_at": "2026-05-14T18:32:11.000Z"
}
```

### Required fields

`event_type`, `channel`, `client_id`, `subject_type`, `subject_id`, `decision`, `decided_by.channel_user_id`, `submitted_at`.

### Validation rules

- `decision` must be valid for the given `subject_type` (e.g., `extend_ceiling_by` is only valid when `subject_type = cost_ceiling_breach`).
- `client_id` must exist; `decided_by.channel_user_id` must map to a `client_members.auth_user_id` for that client.
- Timestamp within ±5 minutes of server time (replay protection).
- Idempotency: `(channel, channel_message_id)` must be unique. Duplicate POSTs return 200 with the prior result.

---

## n8n response (n8n -> channel)

```jsonc
{
  "ok": true,
  "decision_id": "<uuid>",                        // FK into human_reviews
  "outbound_effects": [                           // what the decision triggered
    {
      "type": "keyword_classification_updated",
      "subject_id": "<uuid>",
      "new_status": "passed"
    },
    {
      "type": "cross_validation_event_created",
      "event_id": "<uuid>",
      "severity": "high"
    }
  ],
  "follow_up_required": false                     // true if AI second-pass flagged a disagreement that escalates
}
```

On validation failure:

```jsonc
{
  "ok": false,
  "error": {
    "code": "invalid_decision_for_subject_type",
    "message": "decision=extend_ceiling_by is not valid for subject_type=keyword"
  }
}
```

---

## Outbound HITL card payload (n8n -> channel)

For the channel-rendering side, n8n sends a normalized card descriptor and the per-channel adapter (Slack / Telegram / dashboard) renders it appropriately.

```jsonc
{
  "card_id": "<uuid>",                            // unique per card; channel_message_id maps back to this
  "client_id": "<uuid>",
  "pipeline_run_id": "<uuid>",
  "subject_type": "keyword",
  "subject_id": "<uuid>",
  "severity": "medium",                            // "low" | "medium" | "high"
  "title": "Review: borderline keyword classification",
  "summary": "AI classified 'best seo agency for healthcare' as commercial_investigation with confidence 0.62.",
  "context_blocks": [
    {
      "label": "AI reasoning",
      "value": "Volume 1,200; KD 38; head term of cluster 'healthcare seo agencies'..."
    },
    {
      "label": "3 nearest gold examples",
      "value": "1. 'best seo agency for finance' (positive)\n2. 'healthcare digital marketing agency' (positive)\n3. 'top seo company' (negative — too generic)"
    },
    {
      "label": "Confidence",
      "value": "0.62"
    }
  ],
  "actions": [
    {"label": "Approve as commercial_investigation", "decision": "approve"},
    {"label": "Reject as out of scope", "decision": "reject"},
    {"label": "Reclassify as transactional", "decision": "reroute", "decision_metadata": {"reroute_to_intent": "transactional"}},
    {"label": "Escalate to senior", "decision": "escalate"}
  ],
  "ttl_seconds": 86400,                            // auto-close if no response in 24h
  "issued_at": "2026-05-14T18:30:00.000Z"
}
```

### Channel adapter rendering

- **Slack:** Block Kit message with `actions` rendered as buttons. Submission triggers Slack's interactive payload, which n8n unwraps and POSTs back to itself with the normalized payload shape above.
- **Telegram:** `sendMessage` with `reply_markup.inline_keyboard` — one button per action. Callback data encodes `card_id` + `decision`. Telegram's `callback_query` is unwrapped by n8n.
- **Dashboard (Phase 2):** card rendered in `/admin/keyword-review`; button clicks POST directly to the normalized endpoint.

---

## Severity-driven routing

How an outbound card is routed to channels is determined by `clients.config.hitl_routing`:

```jsonc
{
  "hitl_routing": {
    "borderline":            "slack",                       // single channel
    "high_severity":         ["slack", "telegram"],         // mirrored to both
    "taxonomy_suggestions":  "slack",
    "cost_ceiling":          ["slack", "telegram"],
    "quality_drift":         ["slack", "telegram"],
    "onboarding_review":     "slack"
  }
}
```

If a routing target is unset, fallback to `clients.config.hitl_channels[0]`.

---

## Idempotency and retries

- Channel adapters MUST set `(channel, channel_message_id)` deterministically per card.
- If the same decision is submitted twice (e.g., button double-tap), n8n returns the prior `decision_id` and `outbound_effects` — no state change.
- If n8n's response is lost in flight, the channel adapter MAY re-POST with the same idempotency key.

---

## Future: in-app dashboard (Phase 2)

The dashboard will:
- Read `human_reviews` + `cross_validation_events` + active cards directly from Supabase (RLS-enforced).
- POST decisions to the same `/hitl-decision` endpoint.
- Render the same `context_blocks` and `actions` from the card descriptor.
- Add features Slack/Telegram can't: rich diff views, side-by-side gold example comparison, bulk approval with filters.
