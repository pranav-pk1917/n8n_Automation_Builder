# ROADMAP

Living document for Phase 2+ work, deferred improvements, and ideas surfaced during planning. **Anything in this file is NOT in Phase 1's scope** — Phase 1 (the keyword cleaning + clustering pipeline) is documented in `architecture.md`.

Format: each item has a category, a one-line description, the rationale, and rough effort sizing.

Effort scale: **S** (1-3 days), **M** (1-2 weeks), **L** (3-6 weeks), **XL** (months).

---

## Phase 2 — Content brief + draft generation

The next pipeline after keyword clusters are approved.

| Item | Description | Why | Effort |
|---|---|---|---|
| **Brief generator (per cluster)** | LLM produces a content brief: target keyword, LSI variants from cluster, intent type, recommended H1/H2/H3, suggested word count, internal links, target page URL, schema markup type, PAA questions to answer. | The brief is the contract between research and writing. Quality here determines draft quality. | M |
| **Information-gain scoring** | Before writing, fetch top-10 SERP results, embed them, measure "info density gap" the new draft must fill. Brief surfaces this gap. | Avoid producing "mass-AI rehash" content that loses to existing top-10. | M |
| **Draft writer (first pass)** | LLM-generated first draft using brief + client brand voice + client first-party data snippets. Output to Google Docs or Notion for editor review. | Speed up content production while preserving editorial control. | M |
| **HCS (Helpful Content System) safety scorer** | Pre-publish heuristic + LLM check: does the draft show experience signals, original POV, first-party data, author authority? Score 0-100 with specific issues. | Google's HCS penalizes "made for SEO" content. We must score above threshold before publishing. | S |
| **Schema markup auto-generator** | Per content type (article / how-to / FAQ / pricing / comparison): generate the correct JSON-LD schema block for the draft. | Required for SERP feature eligibility (PAA, featured snippet, AI Overviews citation). | S |
| **Author/E-E-A-T schema** | Auto-attach `Person` + `Organization` schema. Pull author bio + credentials + LinkedIn from a per-author config table. | Hard moat against generic AI content. Authors with real credentials win. | S |
| **Q&A block injector** | LLM finds 5 most-likely-asked questions for the topic and produces 40-60 word direct answers formatted for AI Overview ingestion. | GEO-specific optimization for ChatGPT / Perplexity / Gemini citation. | S |
| **Image generation + alt-text** | Generate hero + section images with the brand-aligned model (Imagen / DALL-E / Recraft). Auto-write alt text with target keyword variation. | Images contribute to E-E-A-T + image-pack SERP. | M |
| **WordPress publish + revalidate trigger** | When draft is approved, push to headless WP via WPGraphQL mutation; call client's Next.js `/api/revalidate` to refresh ISR cache. | Closes the loop from research -> published page. | S |
| **Internal linking graph** | Auto-suggest internal links from new article to existing pages based on cluster relationships + anchor text variation. | Hub-and-spoke architecture compounds topical authority. | M |
| **Programmatic SEO pages (Phase 2.5)** | For (pillar x niche) combinations with sufficient search volume, generate templated landing pages: `/services/{pillar}/{niche}` with unique per-niche data. | Captures the long tail of (service x industry) keyword space efficiently. | L |
| **Performance marketing landing pages (Phase 2.5)** | When a paid campaign launches, auto-generate a matching landing page with ad-message-match copy and conversion-optimized structure. | Already in user's stated workflow; integrates with paid acquisition. | M |

---

## Phase 3 — Distribution + amplification

Multi-channel distribution that ties social posts back to the published asset, with gray-hat amplification tactics that compound branded search.

| Item | Description | Why | Effort |
|---|---|---|---|
| **LinkedIn post + pinned comment** | When new article publishes, generate LinkedIn post with hook + summary + insight; auto-post; pin a comment with the article link. Use Webley's own account first. | LinkedIn comment-pinning is the highest-ROI gray-hat amplification in 2026. | M |
| **Multi-account LinkedIn orchestration** | Coordinate posts across multiple Webley team accounts (CEO, head of marketing, senior consultants) with staggered timing + different angles. | Network effect lift on engagement signals; protects against algorithmic suppression of single-account spam patterns. Must respect platform ToS and use real human accounts. | L |
| **Reddit seeding (niche subs only)** | Identify 3-5 niche subreddits per cluster topic where Webley team members are already established contributors. Post AMA/discussion seeds with article link via OP-pinned comment in niche subs (general subs auto-remove). | Direct traffic from decision-makers; branded search uplift; modest backlink value. | M |
| **Quora long-form answers** | For each new article, generate a Quora answer to 3-5 high-traffic related questions with link back. Note: Quora links are nofollow but traffic still converts. | Direct traffic + brand awareness, even with nofollow. | M |
| **HARO / Featured.com automation** | Daily check of HARO/Featured.com queries; LLM drafts responses pulling from Webley's first-party data + case studies for editor review. | High-DA backlinks from journalist citations. Real moat. | L |
| **Twitter/X thread auto-generation** | Convert article into a 6-10 tweet thread with hook tweet + image preview + bio link. | Discoverability + relationship-building with industry peers. | S |
| **Web 2.0 property cross-linking** | Auto-publish summarized versions to Medium / Substack / dev.to that cross-link back to canonical article. | "Branded entity stacking" — these properties rank well on long-tail and signal entity authority. | M |
| **Comment-marketing on competitor content** | Track competitor articles ranking for our target keywords; auto-draft (human-reviewed) thoughtful comments that add value + link only when relevant. | Real value-add, modest traffic, brand visibility. | M |
| **Email outreach for link building** | Identify high-DA sites covering our topic; auto-draft personalized outreach for editor review. | Tier-1 backlinks. Manual but critical for competitive niches. | M |

---

## Phase 4 — Monitoring + optimization

Once content is live, the system must monitor and refresh.

| Item | Description | Why | Effort |
|---|---|---|---|
| **Google Search Console (GSC) integration** | Daily pull of impressions/clicks/CTR/position per page; write to `gsc_metrics` table. Decay detection: pages losing >30% impressions in 30 days auto-queue for refresh. | Most content decays. Refresh windows of 6-18 months are normal. Need automated decay alerts. | M |
| **SERP volatility monitor** | Track ranking position daily for top-N target keywords; alert on >10-position drops. Cross-correlate with Google update timing. | Catch algorithm-update casualties before they bleed traffic for weeks. | M |
| **Competitor content monitor** | Crawl competitor blogs weekly; LLM diff against last crawl; alert when a competitor publishes new content on a topic we already rank for. | Defense — respond before they steal share. | M |
| **Content refresh prioritizer** | Multi-factor scoring on which pages should be refreshed first: GSC decay + competitor pressure + recency of last refresh + commercial value of ranking position. | Refresh effort is finite; prioritize what matters. | M |
| **A/B testing for titles + meta descriptions** | Programmatic title/meta variations with GSC CTR tracking. | CTR improvement compounds over base ranking. | M |
| **GA4 / conversion-correlated keyword analysis** | Join keyword landing pages with GA4 conversion events. Identify keywords that ACTUALLY produce leads, not just traffic. Feed back into keyword prioritization. | Closes the loop on the conversion-first thesis. | M |
| **Real-time SERP feature tracker** | Monitor whether each target keyword currently shows: featured snippet / PAA / AI Overview / video pack / image pack. Surface SERP-feature-specific content opportunities. | Content templates and on-page structure differ by SERP-feature target. | M |
| **Topical authority score per cluster** | Composite metric: % of cluster keywords ranking top 10 + internal link density + first-party data presence + GSC impression share. | Diagnostic for which topics are mature vs underbuilt. | S |
| **Backlink monitoring** | Track new + lost backlinks per page weekly. Alert on high-DA acquisitions and high-DA losses. | Outreach effectiveness signal; lost-link reclaim opportunities. | S |

---

## Phase 5+ — Platform / SaaS-ification

If/when Webley sells this capability as a productized service.

| Item | Description | Why | Effort |
|---|---|---|---|
| **Client-facing dashboard** | Next.js app at `app.webleymedia.com` (or inside the existing portal) showing the client their keyword clusters, briefs, drafts, published content, GSC trends, and pipeline status. | Premium-tier transparency play. Justifies higher retainer. | L |
| **In-app HITL review UI** | Replace Slack/Telegram HITL with a purpose-built review queue inside the dashboard. Same n8n webhook contract; only the UI changes. | Better UX than chat-based review; reduces interruption. | M |
| **Per-client API key vault (BYOK)** | Premium clients bring their own OpenRouter / SerpAPI keys; system uses them via `clients.config.api_keys jsonb`. Direct-provider keys (Gemini, OpenAI, Anthropic) can also be plugged in by configuring a per-client OpenRouter alternative. | Cost pass-through model for high-volume clients. | S |
| **Multi-language support** | Language detection on raw_keywords; route non-English to multilingual embeddings + translated LLM prompts. | Required for clients targeting non-English markets. | M |
| **White-label mode** | Other agencies use the platform under their own brand. Multi-org-per-tenant. | SaaS revenue stream. | XL |
| **Client questionnaire builder** | The intern can build/edit the onboarding questionnaire per client industry without code. | Faster onboarding for niche-specific clients (e.g., healthcare needs HIPAA questions, e-commerce needs platform questions). | M |
| **AI fine-tune on Webley's editorial corpus** | If/when budget allows, fine-tune a small LLM on Webley's best-performing articles to internalize voice + structure preferences. | Voice consistency at scale; reduces editor revision time. | L |

---

## Improvement ideas (cross-phase, opportunistic)

| Item | Description | Why | Effort |
|---|---|---|---|
| **`llms.txt` generator** | Auto-generate and maintain `llms.txt` at the site root listing canonical pages + descriptions for LLM crawlers. | Emerging standard for AI-search discoverability. Cheap to implement. | S |
| **Cluster split detection** | Quality audit job: detect when HDBSCAN merged two distinct topics into one cluster; auto-propose split. | Cluster quality drift over time as more keywords are added. | S |
| **Cluster merge detection** | Detect when two clusters are converging in meaning; propose merge. | Avoid serving multiple thin pages for the same intent. | S |
| **Vector store migration plan** | If pgvector hits scale limits (>10M embeddings), prepare migration to Pinecone / Weaviate. | Risk mitigation; document the threshold and the migration path. | S (plan), L (execute) |
| **Cost forecasting** | Per-client monthly cost projections based on recent runs + planned content volume; alert at projected overrun. | Prevents end-of-month budget surprises. | S |
| **Gold-example marketplace** | When agency takes on a client in a vertical we've served before, suggest copying that vertical's gold_examples as a starting set. | Faster onboarding; institutional knowledge reuse. | S |
| **Cross-client benchmark anonymized** | "Healthcare clients see 23% rejection rate at Tier 0 on average; this client is at 8% — suspiciously low, review negative_terms coverage." | Diagnostic; catches misconfigured tenants. | M |
| **Auto-translate seed keywords** | For multilingual markets, auto-translate seed keywords using LLM with locale awareness. | Reduces onboarding time for international clients. | S |
| **YouTube SEO sub-pipeline** | Extend the keyword pipeline to also propose YouTube video topics + descriptions + chapter structure. | Video SERP is increasingly important; same keyword research applies. | M |
| **TikTok / short-form research** | Different keyword logic (hooks vs longtail). Separate sub-pipeline. | If clients want short-form. | M |
| **Competitor pricing scraper** | Track competitor pricing pages; alert on changes. Influences Webley's positioning content. | Competitive intelligence. | S |
| **Tone-of-voice consistency scorer** | LLM scores drafts against client's brand voice samples; flags deviations before editor review. | Reduces edit cycles. | S |

---

## Risks + threats to revisit

- **Search engine paradigm shift:** if Google's AI Overviews stop linking out (zero-click), classic SEO ROI craters. Mitigation: GEO + LinkedIn + Reddit + direct relationship channels become primary; SEO becomes secondary. Watch this metric closely.
- **LLM provider price changes:** if the active `DEFAULT_LLM_MODEL` (e.g. `google/gemini-2.0-flash-001`) doubles in price, the cost matrix shifts. Mitigation: ADR 0005's OpenRouter + role-based env-var pattern -- switching to a cheaper alternative is a one-line `.env` edit, no code change.
- **Algorithm penalty risk on gray-hat tactics:** multi-account social orchestration must use real, human-active accounts. Pure automation = ToS violation = account bans. Document rules clearly in the SOP.
- **Embedding model deprecation:** embedding models change names every 6-12 months across providers. Re-embedding 100M vectors is expensive. Mitigation: ADR 0005 documents the operational swap runbook (re-embed via `scripts/one-off/reembed_with_new_model.py` when first needed) and the `api_cost_log.model` column preserves the slug active at the time of each embed, so heterogeneous historical embeddings are auditable. Re-embed only when justified by a quality or cost delta.
- **Data privacy on client data:** as we onboard more clients, their seed keywords + first-party data + GSC data must NEVER cross-pollinate. RLS is layer 1; consider per-client schemas at scale.

---

## How this document evolves

- When we ship a Phase, move its items into a "Shipped" section at the bottom (or archive).
- When a new improvement idea surfaces during a build session, add it here under the appropriate phase or category before continuing.
- Effort estimates are rough — refine them when we actually scope the item.
- Items with cross-references to ADRs should link to the ADR.

Last updated: Phase 1 planning complete; build in progress.
