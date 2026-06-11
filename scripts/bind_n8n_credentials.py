#!/usr/bin/env python3
"""
Bind n8n credentials to unbound httpRequest nodes across the 4 active pipelines.

Strategy:
- For every unbound httpRequest node in WF-01/02/03/04, set:
    parameters.authentication = "predefinedCredentialType"
    parameters.nodeCredentialType = <the matching credential type>
    node.credentials = {<credType>: {"id": "...", "name": "..."}}
  and remove parameters.genericAuthType (only relevant for genericCredentialType).
- For Supabase nodes, the inline headerParameters are kept as a backstop (Option B is
  still feasible), but we also bind a real native credential (Option A hybrid).
- For non-Supabase nodes (OpenRouter, Slack, SerpAPI, PythonWorker), the binding is REQUIRED
  because those nodes have no inline auth headers.

Mapping (per node, by URL pattern):
  *supabase.co*  -> supabaseApi    / Supabase_SEOTools
  *openrouter*   -> httpHeaderAuth / OpenRouter_SEOTools
  *railway*      -> httpHeaderAuth / PythonWorker_SEOTools
  *serpapi*      -> serpApi        / SerpAPI account
  *slack*        -> slackApi       / Slack_SEOTools
"""

import json
import urllib.request

N8N_BASE = "https://n8n-webley-u35816.vm.elestio.app"
API_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJhN2MwNDJlNS05ZTI4LTQ3ZmYtOTdmNC0xYmYyNzI3MWIyOTgiLCJpc3MiOiJuOG4iLCJhdWQiOiJwdWJsaWMtYXBpIiwianRpIjoiMTFjMGM0ZGEtOGE2YS00YmI3LWIxMWYtYzRjOWM5ZmYxZWE5IiwiaWF0IjoxNzgwOTE3OTIzfQ.848l_qw3z-vvsOzOObhTGvlB_vsOqIyLJwuoXmTFz2M"

WORKFLOWS = {
    "NZRfZgYZ6h1ofCNQ": "WF-01-Ingest",
    "ZUR8Vu7ezlrrO1lR": "WF-02-Tiered-Filter",
    "wKRfHyJ0h97PwKrA": "WF-03-Cluster",
    "ixMXJFl4GWWZvw83": "WF-04-ICP-Score",
}

CRED_IDS = {
    "supabaseApi":   "W9frCd9ul7qHSQZ4",
    "httpHeaderAuth_openrouter": "liUaKhvaxVE2UFz2",
    "httpHeaderAuth_python":     "0Q3P80L2YPleecil",
    "slackApi":      "X7ERUdX74r2khkbc",
    "serpApi":       "TCnJblOKqcbhVHB8",
}
CRED_NAMES = {
    "supabaseApi":   "Supabase_SEOTools",
    "httpHeaderAuth_openrouter": "OpenRouter_SEOTools",
    "httpHeaderAuth_python":     "PythonWorker_SEOTools",
    "slackApi":      "Slack_SEOTools",
    "serpApi":       "SerpAPI account",
}

# Fields to strip from the workflow payload (server-only, read-only, or unsupported)
STRIP_FIELDS = {
    "id", "versionId", "activeVersionId", "active", "createdAt", "updatedAt",
    "shared", "tags", "pinData", "triggerCount", "versionCounter", "activeVersion",
    "nodeGroups", "isArchived", "meta", "staticData",
}


def classify(url: str) -> str:
    if not url:
        return None
    u = url.lower()
    if "supabase" in u:
        return "supabaseApi"
    if "openrouter" in u:
        return "httpHeaderAuth_openrouter"
    if "railway" in u:
        return "httpHeaderAuth_python"
    if "serpapi" in u:
        return "serpApi"
    if "slack" in u:
        return "slackApi"
    return None


def http_request(url: str, method: str = "GET", body=None):
    headers = {"X-N8N-API-KEY": API_KEY}
    data = None
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(N8N_BASE + url, data=data, method=method, headers=headers)
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode("utf-8"))


def main():
    total_bound = 0
    total_skipped = 0
    total_errors = 0
    for wf_id, wf_name in WORKFLOWS.items():
        print(f"\n=== {wf_name} ({wf_id}) ===")
        wf = http_request(f"/api/v1/workflows/{wf_id}")
        nodes = wf.get("nodes", [])
        patched_nodes = []
        for node in nodes:
            if node.get("type") != "n8n-nodes-base.httpRequest":
                continue
            url = node.get("parameters", {}).get("url", "")
            kind = classify(url)
            if not kind:
                total_skipped += 1
                continue
            params = node.setdefault("parameters", {})
            current_auth = params.get("authentication", "")
            current_nct = params.get("nodeCredentialType", "")
            if current_auth == "predefinedCredentialType" and current_nct == kind:
                # already bound, but ensure credentials object is present
                node.setdefault("credentials", {})
                continue
            params["authentication"] = "predefinedCredentialType"
            params["nodeCredentialType"] = kind
            if "genericAuthType" in params:
                del params["genericAuthType"]
            node["credentials"] = {
                kind: {"id": CRED_IDS[kind], "name": CRED_NAMES[kind]}
            }
            patched_nodes.append((node.get("name"), kind))
        if not patched_nodes:
            print(f"  No unbound nodes needing binding")
            continue
        # Strip server-only fields
        for f in STRIP_FIELDS:
            wf.pop(f, None)
        if wf.get("description") is None:
            wf["description"] = ""
        # minimal settings object (drop availableInMCP)
        wf["settings"] = {"executionOrder": "v1"}
        try:
            result = http_request(f"/api/v1/workflows/{wf_id}", method="PUT", body=wf)
            total_bound += len(patched_nodes)
            for name, kind in patched_nodes:
                print(f"  BOUND  {name} -> {kind}")
            print(f"  PUT OK  (workflowId={result.get('id')})")
        except urllib.error.HTTPError as e:
            total_errors += len(patched_nodes)
            body_text = e.read().decode("utf-8", errors="replace")
            print(f"  PUT FAILED  HTTP {e.code}: {body_text[:500]}")
            for name, kind in patched_nodes:
                print(f"  FAILED  {name} -> {kind}")

    print("\n=== Summary ===")
    print(f"Bound: {total_bound}")
    print(f"Skipped: {total_skipped}")
    print(f"Errors: {total_errors}")


if __name__ == "__main__":
    main()
