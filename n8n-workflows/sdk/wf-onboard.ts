import { workflow, node, trigger, sticky, ifElse, splitInBatches, nextBatch, expr } from '@n8n/workflow-sdk';

const stickyNote = sticky(
  '## WF-ONBOARD — Client Onboarding\n\n' +
  '**Trigger:** POST /webhook/wf-onboard-start\n' +
  '**Payload:** { client_url, client_name, competitors[], seed_keywords[] }\n\n' +
  '**Flow:** Crawl sitemap → extract pages → LLM site analysis → Slack questionnaire (HITL) → cross-validation → Supabase writes → completion Slack\n\n' +
  '**Outputs:** clients, niches, pipeline_runs, api_cost_log\n\n' +
  '**Next workflows:** WF-00 (page inventory), WF-01 (CSV ingest)',
  [],
  { color: 7, width: 500, height: 300 }
);

const webhookTrigger = trigger({
  type: 'n8n-nodes-base.webhook',
  version: 2.1,
  config: {
    name: 'Webhook_Trigger',
    parameters: {
      httpMethod: 'POST',
      path: 'wf-onboard-start',
      responseMode: 'responseNode'
    },
    position: [240, 300]
  },
  output: [{ body: { client_url: 'https://example.com', client_name: 'Acme Corp', competitors: [], seed_keywords: [] } }]
});

const validatePayload = node({
  type: 'n8n-nodes-base.code',
  version: 2,
  config: {
    name: 'Validate_Payload',
    parameters: {
      mode: 'runOnceForAllItems',
      jsCode:
        'const body = $input.first().json.body || $input.first().json;\n' +
        'if (!body.client_url) throw new Error("Missing required field: client_url");\n' +
        'if (!body.client_name) throw new Error("Missing required field: client_name");\n' +
        'const normUrl = body.client_url.replace(/\\/+$/, "");\n' +
        'return [{ json: {\n' +
        '  client_url: normUrl,\n' +
        '  client_name: body.client_name,\n' +
        '  competitors: Array.isArray(body.competitors) ? body.competitors : [],\n' +
        '  seed_keywords: Array.isArray(body.seed_keywords) ? body.seed_keywords : [],\n' +
        '  started_at: new Date().toISOString()\n' +
        '} }];'
    },
    position: [480, 300]
  },
  output: [{ client_url: 'https://example.com', client_name: 'Acme Corp', competitors: [], seed_keywords: [], started_at: '2026-01-01T00:00:00Z' }]
});

const createPipelineRun = node({
  type: 'n8n-nodes-base.httpRequest',
  version: 4.4,
  config: {
    name: 'Create_Pipeline_Run',
    parameters: {
      method: 'POST',
      url: expr('{{ $env.SUPABASE_URL }}/rest/v1/pipeline_runs'),
      authentication: 'genericCredentialType',
      genericAuthType: 'httpHeaderAuth',
      sendHeaders: true,
      specifyHeaders: 'keypair',
      headerParameters: { parameters: [
        { name: 'apikey', value: expr('{{ $env.SUPABASE_SERVICE_ROLE_KEY }}') },
        { name: 'Content-Type', value: 'application/json' },
        { name: 'Prefer', value: 'return=representation' }
      ]},
      sendBody: true,
      specifyBody: 'json',
      jsonBody: expr('{ "kind": "onboard", "status": "running", "triggered_by": "{{ $json.client_name }}", "started_at": "{{ $json.started_at }}" }')
    },
    credentials: { httpHeaderAuth: { id: 'placeholder', name: 'Supabase_SEOTools' } },
    position: [720, 300]
  },
  output: [{ id: 'run-uuid-123', kind: 'onboard', status: 'running' }]
});

const mergeRunId = node({
  type: 'n8n-nodes-base.code',
  version: 2,
  config: {
    name: 'Merge_Run_ID',
    parameters: {
      mode: 'runOnceForAllItems',
      jsCode:
        'const run = $input.first().json;\n' +
        'const prev = $("Validate_Payload").first().json;\n' +
        'return [{ json: { ...prev, pipeline_run_id: Array.isArray(run) ? run[0]?.id : run?.id } }];'
    },
    position: [960, 300]
  },
  output: [{ client_url: 'https://example.com', client_name: 'Acme Corp', pipeline_run_id: 'run-uuid-123', competitors: [], seed_keywords: [] }]
});

const fetchSitemap = node({
  type: 'n8n-nodes-base.httpRequest',
  version: 4.4,
  config: {
    name: 'Fetch_Sitemap',
    parameters: {
      method: 'GET',
      url: expr('{{ $json.client_url }}/sitemap.xml'),
      options: { timeout: 15000 }
    },
    position: [1200, 300]
  },
  output: [{ data: '<urlset><url><loc>https://example.com/</loc></url></urlset>' }]
});

const parseSitemap = node({
  type: 'n8n-nodes-base.code',
  version: 2,
  config: {
    name: 'Parse_Sitemap_XML',
    parameters: {
      mode: 'runOnceForAllItems',
      jsCode:
        'const ctx = $("Merge_Run_ID").first().json;\n' +
        'const xml = $input.first().json.data || "";\n' +
        'const locs = (xml.match(/<loc>([^<]+)<\\/loc>/gi) || [])\n' +
        '  .map(m => m.replace(/<\\/?loc>/gi, "").trim())\n' +
        '  .filter(u => u.startsWith("http"));\n' +
        'const scored = locs.map(u => {\n' +
        '  const path = u.replace(/^https?:\\/\\/[^/]+/, "") || "/";\n' +
        '  const depth = (path.match(/\\//g) || []).length;\n' +
        '  const boost = /(services|about|process|case-stud)/i.test(path) ? -2 : 0;\n' +
        '  return { url: u, path, score: depth + boost };\n' +
        '});\n' +
        'scored.sort((a,b) => a.score - b.score);\n' +
        'return scored.slice(0,20).map(p => ({ json: { ...ctx, page_url: p.url, page_path: p.path } }));'
    },
    position: [1440, 300]
  },
  output: [{ page_url: 'https://example.com/', page_path: '/', client_url: 'https://example.com', client_name: 'Acme Corp', pipeline_run_id: 'run-uuid-123' }]
});

const batchPages = splitInBatches({
  version: 3,
  config: {
    name: 'Batch_Pages',
    parameters: { batchSize: 5 },
    position: [1680, 300]
  }
});

const crawlPage = node({
  type: 'n8n-nodes-base.httpRequest',
  version: 4.4,
  config: {
    name: 'Crawl_Page',
    parameters: {
      method: 'GET',
      url: expr('{{ $json.page_url }}'),
      options: { timeout: 10000 }
    },
    position: [1920, 300]
  },
  output: [{ data: '<html><title>Example</title><h1>Home</h1><meta name="description" content="We do things"></html>' }]
});

const extractContent = node({
  type: 'n8n-nodes-base.code',
  version: 2,
  config: {
    name: 'Extract_Page_Content',
    parameters: {
      mode: 'runOnceForAllItems',
      jsCode:
        'return $input.all().map((item) => {\n' +
        '  const ctx = item.json;\n' +
        '  const html = ctx.data || "";\n' +
        '  const title = (html.match(/<title[^>]*>([^<]+)<\\/title>/i) || [])[1]?.trim() || "";\n' +
        '  const h1 = (html.match(/<h1[^>]*>([^<]{0,200})<\\/h1>/i) || [])[1]?.replace(/<[^>]+>/g, "").trim() || "";\n' +
        '  const metaDesc = (html.match(/<meta[^>]+name=[\'"]description[\'"][^>]+content=[\'"]([^\'"]{0,300})[\'"][^>]*>/i) || [])[1]?.trim() || "";\n' +
        '  const visibleText = html.replace(/<style[^>]*>[\\s\\S]*?<\\/style>/gi, "").replace(/<script[^>]*>[\\s\\S]*?<\\/script>/gi, "").replace(/<[^>]+>/g, " ").replace(/\\s+/g, " ").trim().slice(0, 300);\n' +
        '  return { json: { url: ctx.page_url, path: ctx.page_path, title, h1, meta_description: metaDesc, visible_text: visibleText, client_url: ctx.client_url, client_name: ctx.client_name, pipeline_run_id: ctx.pipeline_run_id, competitors: ctx.competitors, seed_keywords: ctx.seed_keywords } };\n' +
        '});'
    },
    position: [2160, 300]
  },
  output: [{ url: 'https://example.com/', title: 'Example', h1: 'Home', meta_description: 'We do things', visible_text: 'Home page content', client_url: 'https://example.com', client_name: 'Acme Corp', pipeline_run_id: 'run-uuid-123', competitors: [], seed_keywords: [] }]
});

const aggregatePages = node({
  type: 'n8n-nodes-base.aggregate',
  version: 1,
  config: {
    name: 'Aggregate_Pages',
    parameters: {
      aggregate: 'aggregateAllItemData',
      destinationFieldName: 'pages'
    },
    position: [2400, 300]
  },
  output: [{ pages: [{ url: 'https://example.com/', title: 'Example' }] }]
});

const llmSiteAnalysis = node({
  type: 'n8n-nodes-base.httpRequest',
  version: 4.4,
  config: {
    name: 'LLM_Site_Analysis',
    parameters: {
      method: 'POST',
      url: 'https://openrouter.ai/api/v1/chat/completions',
      authentication: 'genericCredentialType',
      genericAuthType: 'httpHeaderAuth',
      sendBody: true,
      specifyBody: 'json',
      jsonBody: expr(
        '{ "model": "google/gemini-2.0-flash-001", ' +
        '"response_format": { "type": "json_object" }, ' +
        '"temperature": 0.2, "max_tokens": 2048, ' +
        '"messages": [' +
        '{ "role": "system", "content": "You are an expert digital marketing strategist. Analyse crawled pages and return ONLY raw JSON: { proposed_pillars, icp_signals, icp_persona_draft, brand_voice_hints, industries_addressed, competitor_mentions, confidence, notes }." }, ' +
        '{ "role": "user", "content": "Analyse pages from {{ $(\\"Merge_Run_ID\\").first().json.client_url }}. Pages: {{ JSON.stringify($json.pages.slice(0,10).map(p => ({ url: p.url, title: p.title, h1: p.h1, meta_description: p.meta_description, visible_text: p.visible_text }))) }}" }' +
        '] }'
      )
    },
    credentials: { httpHeaderAuth: { id: 'placeholder', name: 'OpenRouter_SEOTools' } },
    position: [2640, 300]
  },
  output: [{ choices: [{ message: { content: '{"proposed_pillars":[],"icp_persona_draft":"","brand_voice_hints":"","industries_addressed":[],"competitor_mentions":[],"confidence":"medium","notes":""}' } }], usage: { prompt_tokens: 500, completion_tokens: 200 } }]
});

const buildSlackCard = node({
  type: 'n8n-nodes-base.code',
  version: 2,
  config: {
    name: 'Build_Slack_Questionnaire',
    parameters: {
      mode: 'runOnceForAllItems',
      jsCode:
        'const ctx = $("Merge_Run_ID").first().json;\n' +
        'const llmRaw = $input.first().json;\n' +
        'let analysis = {};\n' +
        'try { analysis = JSON.parse(llmRaw.choices?.[0]?.message?.content || "{}"); } catch(e) { analysis = { proposed_pillars: [], confidence: "low" }; }\n' +
        'const pillarsText = (analysis.proposed_pillars || []).map(p => p.name + "|" + (p.url_path || "") + "|" + (p.description || "")).join("\\n") || "";\n' +
        'const nicheText = (analysis.industries_addressed || []).join(", ") || "";\n' +
        'const inputTokens = llmRaw.usage?.prompt_tokens || 0;\n' +
        'const outputTokens = llmRaw.usage?.completion_tokens || 0;\n' +
        'return [{ json: {\n' +
        '  pipeline_run_id: ctx.pipeline_run_id,\n' +
        '  client_name: ctx.client_name,\n' +
        '  client_url: ctx.client_url,\n' +
        '  competitors: ctx.competitors,\n' +
        '  seed_keywords: ctx.seed_keywords,\n' +
        '  crawl_analysis: analysis,\n' +
        '  llm_cost: { input_tokens: inputTokens, output_tokens: outputTokens, usd: (inputTokens * 0.000001) + (outputTokens * 0.000002) },\n' +
        '  slack_channel: "C0B43A7QG5P",\n' +
        '  slack_text: "New client onboarding: " + ctx.client_name,\n' +
        '  pillars_prefill: pillarsText,\n' +
        '  icp_prefill: analysis.icp_persona_draft || "",\n' +
        '  brand_voice_prefill: analysis.brand_voice_hints || "",\n' +
        '  niches_prefill: nicheText,\n' +
        '  competitors_prefill: (ctx.competitors || []).join(", ")\n' +
        '} }];'
    },
    position: [2880, 300]
  },
  output: [{ pipeline_run_id: 'run-uuid-123', client_name: 'Acme Corp', client_url: 'https://example.com', slack_channel: 'C0B43A7QG5P', slack_text: 'New client onboarding: Acme Corp', pillars_prefill: '', icp_prefill: '', brand_voice_prefill: '', niches_prefill: '', competitors_prefill: '', crawl_analysis: {}, llm_cost: { usd: 0 } }]
});

const sendSlackCard = node({
  type: 'n8n-nodes-base.httpRequest',
  version: 4.4,
  config: {
    name: 'Send_Questionnaire_Card',
    parameters: {
      method: 'POST',
      url: 'https://slack.com/api/chat.postMessage',
      authentication: 'genericCredentialType',
      genericAuthType: 'httpHeaderAuth',
      sendBody: true,
      specifyBody: 'json',
      jsonBody: expr(
        '{ "channel": "{{ $json.slack_channel }}", "text": "{{ $json.slack_text }}", ' +
        '"blocks": [' +
        '{ "type": "header", "text": { "type": "plain_text", "text": "New Client Onboarding: {{ $json.client_name }}" } },' +
        '{ "type": "section", "text": { "type": "mrkdwn", "text": "*Website:* {{ $json.client_url }}" } },' +
        '{ "type": "input", "block_id": "pillars_input", "label": { "type": "plain_text", "text": "Service Pillars (name|url_path|desc, one per line)" }, "element": { "type": "plain_text_input", "action_id": "pillars_value", "multiline": true, "initial_value": "{{ $json.pillars_prefill }}" } },' +
        '{ "type": "input", "block_id": "icp_input", "label": { "type": "plain_text", "text": "ICP Persona" }, "element": { "type": "plain_text_input", "action_id": "icp_value", "multiline": true, "initial_value": "{{ $json.icp_prefill }}" } },' +
        '{ "type": "input", "block_id": "brand_voice_input", "label": { "type": "plain_text", "text": "Brand Voice" }, "element": { "type": "plain_text_input", "action_id": "brand_voice_value", "multiline": true, "initial_value": "{{ $json.brand_voice_prefill }}" } },' +
        '{ "type": "input", "block_id": "niches_input", "label": { "type": "plain_text", "text": "Niches (comma-separated)" }, "element": { "type": "plain_text_input", "action_id": "niches_value", "initial_value": "{{ $json.niches_prefill }}" } },' +
        '{ "type": "input", "block_id": "competitors_input", "label": { "type": "plain_text", "text": "Competitors (comma-separated)" }, "element": { "type": "plain_text_input", "action_id": "competitors_value", "initial_value": "{{ $json.competitors_prefill }}" } },' +
        '{ "type": "input", "block_id": "review_tier_input", "label": { "type": "plain_text", "text": "Review Tier" }, "element": { "type": "static_select", "action_id": "review_tier_value", "initial_option": { "text": { "type": "plain_text", "text": "tier_b_hitl_borderline" }, "value": "tier_b_hitl_borderline" }, "options": [{ "text": { "type": "plain_text", "text": "tier_a_ai_only" }, "value": "tier_a_ai_only" }, { "text": { "type": "plain_text", "text": "tier_b_hitl_borderline" }, "value": "tier_b_hitl_borderline" }, { "text": { "type": "plain_text", "text": "tier_d_hitl_full" }, "value": "tier_d_hitl_full" }] } },' +
        '{ "type": "actions", "elements": [{ "type": "button", "text": { "type": "plain_text", "text": "Submit" }, "style": "primary", "action_id": "submit_questionnaire", "value": "{{ JSON.stringify({ pipeline_run_id: $json.pipeline_run_id, client_name: $json.client_name, client_url: $json.client_url }) }}" }] }' +
        '] }'
      )
    },
    credentials: { httpHeaderAuth: { id: 'placeholder', name: 'Slack_SEOTools' } },
    position: [3120, 300]
  },
  output: [{ ok: true, ts: '1234567890.123456' }]
});

const waitForQuestionnaire = trigger({
  type: 'n8n-nodes-base.webhook',
  version: 2.1,
  config: {
    name: 'Wait_For_Questionnaire',
    parameters: {
      httpMethod: 'POST',
      path: 'wf-onboard-questionnaire-response',
      responseMode: 'responseNode'
    },
    position: [3360, 300]
  },
  output: [{ body: { payload: '{"actions":[{"value":"{}","action_id":"submit_questionnaire"}],"view":{"state":{"values":{}}}}' } }]
});

const parseQuestionnaire = node({
  type: 'n8n-nodes-base.code',
  version: 2,
  config: {
    name: 'Parse_Questionnaire_Response',
    parameters: {
      mode: 'runOnceForAllItems',
      jsCode:
        'const body = $input.first().json.body || $input.first().json;\n' +
        'const payload = typeof body.payload === "string" ? JSON.parse(body.payload) : body.payload || body;\n' +
        'const values = payload?.view?.state?.values || {};\n' +
        'const get = (blockId, actionId) => {\n' +
        '  const block = values[blockId];\n' +
        '  if (!block) return null;\n' +
        '  const action = block[actionId];\n' +
        '  return action?.value || action?.selected_option?.value || null;\n' +
        '};\n' +
        'let ctxMeta = {};\n' +
        'try { ctxMeta = JSON.parse(payload?.actions?.[0]?.value || "{}"); } catch(e) {}\n' +
        'const niches = (get("niches_input", "niches_value") || "").split(",").map(n => n.trim()).filter(Boolean);\n' +
        'const competitors = (get("competitors_input", "competitors_value") || "").split(",").map(c => c.trim()).filter(Boolean);\n' +
        'const pillarsRaw = get("pillars_input", "pillars_value") || "";\n' +
        'const pillars = pillarsRaw.split("\\n").filter(Boolean).map(line => {\n' +
        '  const [name, url_path, ...descParts] = line.split("|");\n' +
        '  return { name: name?.trim(), url_path: url_path?.trim() || null, description: descParts.join("|").trim() };\n' +
        '}).filter(p => p.name);\n' +
        'return [{ json: {\n' +
        '  pipeline_run_id: ctxMeta.pipeline_run_id,\n' +
        '  client_name: ctxMeta.client_name,\n' +
        '  client_url: ctxMeta.client_url,\n' +
        '  questionnaire: {\n' +
        '    service_pillars: pillars,\n' +
        '    icp_persona: get("icp_input", "icp_value") || "",\n' +
        '    brand_voice: get("brand_voice_input", "brand_voice_value") || "",\n' +
        '    niches,\n' +
        '    competitors,\n' +
        '    review_tier: get("review_tier_input", "review_tier_value") || "tier_b_hitl_borderline"\n' +
        '  }\n' +
        '} }];'
    },
    position: [3600, 300]
  },
  output: [{ pipeline_run_id: 'run-uuid-123', client_name: 'Acme Corp', client_url: 'https://example.com', questionnaire: { service_pillars: [], niches: [], competitors: [], icp_persona: '', brand_voice: '', review_tier: 'tier_b_hitl_borderline' } }]
});

const llmCrossValidate = node({
  type: 'n8n-nodes-base.httpRequest',
  version: 4.4,
  config: {
    name: 'LLM_CrossValidate',
    parameters: {
      method: 'POST',
      url: 'https://openrouter.ai/api/v1/chat/completions',
      authentication: 'genericCredentialType',
      genericAuthType: 'httpHeaderAuth',
      sendBody: true,
      specifyBody: 'json',
      jsonBody: expr(
        '{ "model": "google/gemini-2.0-flash-001", ' +
        '"response_format": { "type": "json_object" }, ' +
        '"temperature": 0.1, "max_tokens": 1024, ' +
        '"messages": [' +
        '{ "role": "system", "content": "You are a quality-control agent. Find meaningful inconsistencies between the questionnaire and site crawl data. Return ONLY raw JSON: { has_flags, flags: [{ field, severity, issue, suggested_resolution }], summary }" }, ' +
        '{ "role": "user", "content": "Questionnaire: {{ JSON.stringify($json.questionnaire) }}" }' +
        '] }'
      )
    },
    credentials: { httpHeaderAuth: { id: 'placeholder', name: 'OpenRouter_SEOTools' } },
    position: [3840, 300]
  },
  output: [{ choices: [{ message: { content: '{"has_flags":false,"flags":[],"summary":"No issues found."}' } }], usage: { prompt_tokens: 300, completion_tokens: 100 } }]
});

const parseCrossVal = node({
  type: 'n8n-nodes-base.code',
  version: 2,
  config: {
    name: 'Parse_CrossVal_Response',
    parameters: {
      mode: 'runOnceForAllItems',
      jsCode:
        'const ctx = $("Parse_Questionnaire_Response").first().json;\n' +
        'const llmRaw = $input.first().json;\n' +
        'let validation = {};\n' +
        'try { validation = JSON.parse(llmRaw.choices?.[0]?.message?.content || "{}"); } catch(e) { validation = { has_flags: false, flags: [], summary: "Parse error" }; }\n' +
        'const inputTokens = llmRaw.usage?.prompt_tokens || 0;\n' +
        'const outputTokens = llmRaw.usage?.completion_tokens || 0;\n' +
        'return [{ json: { ...ctx, validation, has_flags: validation.has_flags === true, llm_cost_crossval: { usd: (inputTokens * 0.000001) + (outputTokens * 0.000002) } } }];'
    },
    position: [4080, 300]
  },
  output: [{ pipeline_run_id: 'run-uuid-123', has_flags: false, validation: { has_flags: false, flags: [], summary: 'OK' }, questionnaire: { service_pillars: [], niches: [], competitors: [] } }]
});

const ifHasFlags = ifElse({
  version: 2.3,
  config: {
    name: 'IF_Has_Flags',
    parameters: {
      conditions: {
        combinator: 'and',
        options: { caseSensitive: true, leftValue: '', typeValidation: 'strict', version: 1 },
        conditions: [{ leftValue: expr('{{ $json.has_flags }}'), rightValue: true, operator: { type: 'boolean', operation: 'equals' } }]
      }
    },
    position: [4320, 300]
  }
});

const sendFlagCard = node({
  type: 'n8n-nodes-base.httpRequest',
  version: 4.4,
  config: {
    name: 'Send_Flag_Review_Card',
    parameters: {
      method: 'POST',
      url: 'https://slack.com/api/chat.postMessage',
      authentication: 'genericCredentialType',
      genericAuthType: 'httpHeaderAuth',
      sendBody: true,
      specifyBody: 'json',
      jsonBody: expr(
        '{ "channel": "C0B43A7QG5P", ' +
        '"text": "Onboarding flags for {{ $json.client_name }}", ' +
        '"blocks": [' +
        '{ "type": "header", "text": { "type": "plain_text", "text": "Onboarding Flags: {{ $json.client_name }}" } }, ' +
        '{ "type": "section", "text": { "type": "mrkdwn", "text": "{{ $json.validation.summary }}" } }, ' +
        '{ "type": "actions", "elements": [{ "type": "button", "text": { "type": "plain_text", "text": "Acknowledge" }, "style": "primary", "action_id": "acknowledge_flags", "value": "{{ JSON.stringify({ pipeline_run_id: $json.pipeline_run_id, client_name: $json.client_name, client_url: $json.client_url }) }}" }] }' +
        '] }'
      )
    },
    credentials: { httpHeaderAuth: { id: 'placeholder', name: 'Slack_SEOTools' } },
    position: [4560, 180]
  },
  output: [{ ok: true }]
});

const waitFlagAck = trigger({
  type: 'n8n-nodes-base.webhook',
  version: 2.1,
  config: {
    name: 'Wait_Flag_Ack',
    parameters: {
      httpMethod: 'POST',
      path: 'wf-onboard-flag-response',
      responseMode: 'responseNode'
    },
    position: [4800, 180]
  },
  output: [{ body: { payload: '{"actions":[{"value":"{}","action_id":"acknowledge_flags"}]}' } }]
});

const parseAck = node({
  type: 'n8n-nodes-base.code',
  version: 2,
  config: {
    name: 'Parse_Flag_Ack',
    parameters: {
      mode: 'runOnceForAllItems',
      jsCode:
        'const body = $input.first().json.body || $input.first().json;\n' +
        'const payload = typeof body.payload === "string" ? JSON.parse(body.payload) : body.payload || body;\n' +
        'let ctxMeta = {};\n' +
        'try { ctxMeta = JSON.parse(payload?.actions?.[0]?.value || "{}"); } catch(e) {}\n' +
        'const crossValCtx = $("Parse_CrossVal_Response").first().json;\n' +
        'return [{ json: { ...crossValCtx, ...ctxMeta } }];'
    },
    position: [5040, 180]
  },
  output: [{ pipeline_run_id: 'run-uuid-123', client_name: 'Acme Corp', client_url: 'https://example.com', questionnaire: { service_pillars: [], niches: [], competitors: [] } }]
});

const writeClient = node({
  type: 'n8n-nodes-base.httpRequest',
  version: 4.4,
  config: {
    name: 'Write_Client',
    parameters: {
      method: 'POST',
      url: expr('{{ $env.SUPABASE_URL }}/rest/v1/clients'),
      authentication: 'genericCredentialType',
      genericAuthType: 'httpHeaderAuth',
      sendHeaders: true,
      specifyHeaders: 'keypair',
      headerParameters: { parameters: [
        { name: 'apikey', value: expr('{{ $env.SUPABASE_SERVICE_ROLE_KEY }}') },
        { name: 'Content-Type', value: 'application/json' },
        { name: 'Prefer', value: 'return=representation' }
      ]},
      sendBody: true,
      specifyBody: 'json',
      jsonBody: expr(
        '{ "name": "{{ $json.client_name }}", ' +
        '"canonical_domain": "{{ $json.client_url.replace(/^https?:\\/\\//, \\"\\").replace(/\\/.*/, \\"\\") }}", ' +
        '"onboarding_status": "active", ' +
        '"config": {{ JSON.stringify({ service_pillars: $json.questionnaire.service_pillars, icp_persona: $json.questionnaire.icp_persona, brand_voice: $json.questionnaire.brand_voice, review_tier: $json.questionnaire.review_tier || "tier_b_hitl_borderline", monthly_api_budget_usd: 50, expected_runs_per_month: 4, per_run_cost_ceiling_pct: 150, navigational_competitor_strategy: "allow_comparison_only", hitl_channels: ["slack"], hitl_routing: { borderline: "slack", high_severity: ["slack"], taxonomy_suggestions: "slack", cost_ceiling: ["slack"], quality_drift: ["slack"], onboarding_review: "slack" }, negative_overrides: [], positive_overrides: [] }) }} }'
      )
    },
    credentials: { httpHeaderAuth: { id: 'placeholder', name: 'Supabase_SEOTools' } },
    position: [4560, 420]
  },
  output: [{ id: 'client-uuid-123', name: 'Acme Corp', onboarding_status: 'active' }]
});

const writeNiches = node({
  type: 'n8n-nodes-base.httpRequest',
  version: 4.4,
  config: {
    name: 'Write_Niches',
    parameters: {
      method: 'POST',
      url: expr('{{ $env.SUPABASE_URL }}/rest/v1/niches'),
      authentication: 'genericCredentialType',
      genericAuthType: 'httpHeaderAuth',
      sendHeaders: true,
      specifyHeaders: 'keypair',
      headerParameters: { parameters: [
        { name: 'apikey', value: expr('{{ $env.SUPABASE_SERVICE_ROLE_KEY }}') },
        { name: 'Content-Type', value: 'application/json' }
      ]},
      sendBody: true,
      specifyBody: 'json',
      jsonBody: expr('{{ $("Parse_Questionnaire_Response").first().json.questionnaire.niches.map(n => ({ client_id: ($json[0]?.id || $json.id), name: n, source: "onboarding_declared" })) }}')
    },
    credentials: { httpHeaderAuth: { id: 'placeholder', name: 'Supabase_SEOTools' } },
    position: [4800, 420]
  },
  output: [{}]
});

const completePipelineRun = node({
  type: 'n8n-nodes-base.httpRequest',
  version: 4.4,
  config: {
    name: 'Complete_Pipeline_Run',
    parameters: {
      method: 'PATCH',
      url: expr('{{ $env.SUPABASE_URL }}/rest/v1/pipeline_runs?id=eq.{{ $("Parse_Questionnaire_Response").first().json.pipeline_run_id }}'),
      authentication: 'genericCredentialType',
      genericAuthType: 'httpHeaderAuth',
      sendHeaders: true,
      specifyHeaders: 'keypair',
      headerParameters: { parameters: [
        { name: 'apikey', value: expr('{{ $env.SUPABASE_SERVICE_ROLE_KEY }}') },
        { name: 'Content-Type', value: 'application/json' }
      ]},
      sendBody: true,
      specifyBody: 'json',
      jsonBody: expr('{ "status": "completed", "finished_at": "{{ new Date().toISOString() }}" }')
    },
    credentials: { httpHeaderAuth: { id: 'placeholder', name: 'Supabase_SEOTools' } },
    position: [5040, 420]
  },
  output: [{}]
});

const sendCompletion = node({
  type: 'n8n-nodes-base.httpRequest',
  version: 4.4,
  config: {
    name: 'Send_Completion_Notification',
    parameters: {
      method: 'POST',
      url: 'https://slack.com/api/chat.postMessage',
      authentication: 'genericCredentialType',
      genericAuthType: 'httpHeaderAuth',
      sendBody: true,
      specifyBody: 'json',
      jsonBody: expr(
        '{ "channel": "C0B43A7QG5P", ' +
        '"text": "Client onboarded successfully", ' +
        '"blocks": [' +
        '{ "type": "header", "text": { "type": "plain_text", "text": "Client Onboarded" } }, ' +
        '{ "type": "section", "text": { "type": "mrkdwn", "text": "*Client:* {{ $("Parse_Questionnaire_Response").first().json.client_name }}\\n*Domain:* {{ $("Parse_Questionnaire_Response").first().json.client_url }}\\n\\nNext: Run WF-00 (page inventory) and WF-01 (CSV ingest) for this client." } }' +
        '] }'
      )
    },
    credentials: { httpHeaderAuth: { id: 'placeholder', name: 'Slack_SEOTools' } },
    position: [5280, 420]
  },
  output: [{ ok: true }]
});

const respondOk = node({
  type: 'n8n-nodes-base.respondToWebhook',
  version: 1.5,
  config: {
    name: 'Respond_OK',
    parameters: {
      respondWith: 'json',
      responseBody: { ok: true }
    },
    position: [5520, 420]
  }
});

export default workflow('wf-onboard', 'WF-ONBOARD')
  .add(stickyNote)
  .add(webhookTrigger)
  .to(validatePayload)
  .to(createPipelineRun)
  .to(mergeRunId)
  .to(fetchSitemap)
  .to(parseSitemap)
  .to(batchPages
    .onEachBatch(crawlPage.to(extractContent).to(nextBatch(batchPages)))
    .onDone(aggregatePages
      .to(llmSiteAnalysis)
      .to(buildSlackCard)
      .to(sendSlackCard)
    )
  )
  .add(waitForQuestionnaire)
  .to(parseQuestionnaire)
  .to(llmCrossValidate)
  .to(parseCrossVal)
  .to(ifHasFlags
    .onTrue(sendFlagCard.to(waitFlagAck).to(parseAck).to(writeClient))
    .onFalse(writeClient)
  )
  .add(writeClient)
  .to(writeNiches)
  .to(completePipelineRun)
  .to(sendCompletion)
  .to(respondOk);
