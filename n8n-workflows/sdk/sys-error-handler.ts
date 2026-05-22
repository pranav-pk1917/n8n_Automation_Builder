import { workflow, node, trigger, sticky, ifElse, newCredential, expr } from '@n8n/workflow-sdk';

/**
 * SYS-Error-Handler — global error workflow for the SEO-Tools n8n stack.
 *
 * Bound via Workflow Settings → Error Workflow on every Phase-1 workflow
 * (WF-ONBOARD, WF-00, WF-01, WF-02, WF-03, WF-04, WF-05). Triggered by n8n's
 * Error Trigger node when a bound workflow throws an uncaught exception.
 *
 * Live workflow:  https://n8n-webley-u35816.vm.elestio.app/workflow/a1pfnQHRkmPBWJDv
 * Companion doc:  SEO-Tools/n8n-workflows/Manual-Review/prd/phase-2-update-spec.md §3.1
 * Export JSON:    SEO-Tools/n8n-workflows/exports/sys-error-handler.json
 *
 * Flow:
 *   Error Trigger
 *     → Extract Error Context (best-effort pipeline_run_id recovery)
 *     → IF Can Patch Run
 *         onTrue:  PATCH pipeline_runs.status='failed'
 *                  → IF Is Onboarding
 *                      onTrue:  PATCH onboarding_sessions.status='failed' → Post Ops Alert
 *                      onFalse: Post Ops Alert
 *         onFalse: Post Ops Alert (run id not recoverable; still notify Slack)
 *
 * Env vars used:  SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, SLACK_OPS_CHANNEL
 * Credentials:    Supabase_SEOTools (HTTP Header Auth), Slack_SEOTools (HTTP Header Auth)
 */

const stickyNote = sticky(
  '## SYS-Error-Handler — Global Error Workflow\n\n' +
  '**Trigger:** n8n Error Trigger (bound via Workflow Settings → Error Workflow on every Phase-1 workflow)\n\n' +
  '**Flow:** Extract context → IF pipeline_run_id recoverable → PATCH pipeline_runs.status=failed → IF onboarding → PATCH onboarding_sessions.status=failed → Slack ops alert (always).\n\n' +
  '**Env vars used:** SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, SLACK_OPS_CHANNEL\n\n' +
  '**Source:** SEO-Tools/n8n-workflows/sdk/sys-error-handler.ts',
  [],
  { color: 5, width: 460, height: 320 }
);

const errorTriggerNode = trigger({
  type: 'n8n-nodes-base.errorTrigger',
  version: 1,
  config: { name: 'Error Trigger', parameters: {}, position: [0, 200] },
  output: [{
    execution: {
      id: 'exec-123',
      url: 'https://n8n-webley-u35816.vm.elestio.app/execution/exec-123',
      error: { message: 'Sample error', stack: 'Error: Sample error', node: { name: 'SomeNode' }, name: 'TypeError' },
      mode: 'webhook'
    },
    workflow: { id: 'wf-id', name: 'WF-XX' }
  }]
});

const extractErrorContext = node({
  type: 'n8n-nodes-base.code',
  version: 2,
  config: {
    name: 'Extract Error Context',
    parameters: {
      mode: 'runOnceForAllItems',
      language: 'javaScript',
      jsCode:
        "const it = $input.first().json;\n" +
        "const exec = it.execution || {};\n" +
        "const wf = it.workflow || {};\n" +
        "const err = exec.error || {};\n" +
        "const rawStack = (err.stack || err.message || 'unknown error').toString();\n" +
        "const errorMessage = rawStack.length > 1800 ? rawStack.slice(0, 1800) + '...<truncated>' : rawStack;\n" +
        "const failingNode = err.node && err.node.name ? err.node.name : null;\n" +
        "const findPipelineRunId = () => {\n" +
        "  const data = exec.data && exec.data.resultData && exec.data.resultData.runData;\n" +
        "  if (data && typeof data === 'object') {\n" +
        "    for (const nodeName of Object.keys(data)) {\n" +
        "      const runs = data[nodeName];\n" +
        "      if (!Array.isArray(runs)) continue;\n" +
        "      for (const r of runs) {\n" +
        "        const items = r && r.data && r.data.main && r.data.main[0];\n" +
        "        if (!Array.isArray(items)) continue;\n" +
        "        for (const item of items) {\n" +
        "          const j = item && item.json;\n" +
        "          if (j && j.pipeline_run_id) return j.pipeline_run_id;\n" +
        "          if (j && j.body && j.body.pipeline_run_id) return j.body.pipeline_run_id;\n" +
        "        }\n" +
        "      }\n" +
        "    }\n" +
        "  }\n" +
        "  return null;\n" +
        "};\n" +
        "const pipelineRunId = findPipelineRunId();\n" +
        "const workflowName = wf.name || 'unknown';\n" +
        "const isOnboard = /onboard/i.test(workflowName);\n" +
        "return [{ json: {\n" +
        "  pipeline_run_id: pipelineRunId,\n" +
        "  workflow_id: wf.id || null,\n" +
        "  workflow_name: workflowName,\n" +
        "  execution_id: exec.id || null,\n" +
        "  execution_url: exec.url || null,\n" +
        "  failing_node: failingNode,\n" +
        "  error_message: errorMessage,\n" +
        "  error_class: (err.name || 'Error').toString(),\n" +
        "  is_onboard: isOnboard,\n" +
        "  failed_at: new Date().toISOString(),\n" +
        "  can_patch_run: pipelineRunId !== null\n" +
        "} }];"
    },
    position: [240, 200]
  },
  output: [{
    pipeline_run_id: 'run-uuid-123',
    workflow_name: 'WF-02 Tiered Keyword Filter',
    execution_url: 'https://n8n-webley-u35816.vm.elestio.app/execution/exec-123',
    failing_node: 'Score_Tier1',
    error_message: 'TypeError: Cannot read properties of undefined',
    error_class: 'TypeError',
    is_onboard: false,
    failed_at: '2026-05-22T00:00:00.000Z',
    can_patch_run: true
  }]
});

const ifCanPatchRun = ifElse({
  version: 2.3,
  config: {
    name: 'IF Can Patch Run',
    parameters: {
      conditions: {
        combinator: 'and',
        options: { caseSensitive: true, leftValue: '', typeValidation: 'strict' },
        conditions: [{
          id: 'can-patch',
          leftValue: expr('{{ $json.can_patch_run }}'),
          rightValue: true,
          operator: { type: 'boolean', operation: 'equals' }
        }]
      },
      options: {}
    },
    position: [480, 200]
  }
});

const patchPipelineRun = node({
  type: 'n8n-nodes-base.httpRequest',
  version: 4.4,
  config: {
    name: 'Patch Pipeline Run',
    parameters: {
      method: 'PATCH',
      url: expr('{{ $env.SUPABASE_URL }}/rest/v1/pipeline_runs?id=eq.{{ $json.pipeline_run_id }}'),
      authentication: 'genericCredentialType',
      genericAuthType: 'httpHeaderAuth',
      sendHeaders: true,
      specifyHeaders: 'keypair',
      headerParameters: { parameters: [
        { name: 'apikey', value: expr('{{ $env.SUPABASE_SERVICE_ROLE_KEY }}') },
        { name: 'Authorization', value: expr('Bearer {{ $env.SUPABASE_SERVICE_ROLE_KEY }}') },
        { name: 'Content-Type', value: 'application/json' },
        { name: 'Prefer', value: 'return=minimal' }
      ]},
      sendBody: true,
      contentType: 'json',
      specifyBody: 'json',
      jsonBody: expr("{{ JSON.stringify({ status: 'failed', finished_at: $json.failed_at, output_summary: { failed_workflow: $json.workflow_name, failing_node: $json.failing_node, error_class: $json.error_class, error_message: $json.error_message, execution_url: $json.execution_url } }) }}"),
      options: { timeout: 15000 }
    },
    credentials: { httpHeaderAuth: newCredential('Supabase_SEOTools') },
    position: [720, 120]
  },
  output: [{}]
});

const ifIsOnboarding = ifElse({
  version: 2.3,
  config: {
    name: 'IF Is Onboarding',
    parameters: {
      conditions: {
        combinator: 'and',
        options: { caseSensitive: true, leftValue: '', typeValidation: 'strict' },
        conditions: [{
          id: 'is-onboard',
          leftValue: expr("{{ $('Extract Error Context').item.json.is_onboard }}"),
          rightValue: true,
          operator: { type: 'boolean', operation: 'equals' }
        }]
      },
      options: {}
    },
    position: [960, 120]
  }
});

const patchOnboardingSession = node({
  type: 'n8n-nodes-base.httpRequest',
  version: 4.4,
  config: {
    name: 'Patch Onboarding Session',
    parameters: {
      method: 'PATCH',
      url: expr("{{ $env.SUPABASE_URL }}/rest/v1/onboarding_sessions?pipeline_run_id=eq.{{ $('Extract Error Context').item.json.pipeline_run_id }}"),
      authentication: 'genericCredentialType',
      genericAuthType: 'httpHeaderAuth',
      sendHeaders: true,
      specifyHeaders: 'keypair',
      headerParameters: { parameters: [
        { name: 'apikey', value: expr('{{ $env.SUPABASE_SERVICE_ROLE_KEY }}') },
        { name: 'Authorization', value: expr('Bearer {{ $env.SUPABASE_SERVICE_ROLE_KEY }}') },
        { name: 'Content-Type', value: 'application/json' },
        { name: 'Prefer', value: 'return=minimal' }
      ]},
      sendBody: true,
      contentType: 'json',
      specifyBody: 'json',
      jsonBody: expr("{{ JSON.stringify({ status: 'failed', updated_at: $('Extract Error Context').item.json.failed_at }) }}"),
      options: { timeout: 15000 }
    },
    credentials: { httpHeaderAuth: newCredential('Supabase_SEOTools') },
    position: [1200, 40]
  },
  output: [{}]
});

const postOpsAlert = node({
  type: 'n8n-nodes-base.httpRequest',
  version: 4.4,
  config: {
    name: 'Post Ops Alert',
    parameters: {
      method: 'POST',
      url: 'https://slack.com/api/chat.postMessage',
      authentication: 'genericCredentialType',
      genericAuthType: 'httpHeaderAuth',
      sendHeaders: true,
      specifyHeaders: 'keypair',
      headerParameters: { parameters: [
        { name: 'Content-Type', value: 'application/json; charset=utf-8' }
      ]},
      sendBody: true,
      contentType: 'json',
      specifyBody: 'json',
      jsonBody: expr("{{ JSON.stringify({ channel: $env.SLACK_OPS_CHANNEL, text: 'n8n workflow failed: ' + $('Extract Error Context').item.json.workflow_name, blocks: [ { type: 'header', text: { type: 'plain_text', text: 'Workflow failed: ' + $('Extract Error Context').item.json.workflow_name } }, { type: 'section', fields: [ { type: 'mrkdwn', text: '*Failing node:*\\n' + ($('Extract Error Context').item.json.failing_node || '(unknown)') }, { type: 'mrkdwn', text: '*Error class:*\\n' + $('Extract Error Context').item.json.error_class }, { type: 'mrkdwn', text: '*Pipeline run id:*\\n' + ($('Extract Error Context').item.json.pipeline_run_id || '(not recoverable)') }, { type: 'mrkdwn', text: '*Failed at:*\\n' + $('Extract Error Context').item.json.failed_at } ] }, { type: 'section', text: { type: 'mrkdwn', text: '```' + $('Extract Error Context').item.json.error_message + '```' } } ] }) }}"),
      options: { timeout: 10000 }
    },
    credentials: { httpHeaderAuth: newCredential('Slack_SEOTools') },
    position: [1440, 200]
  },
  output: [{ ok: true }]
});

export default workflow('sys-error-handler', 'SYS-Error-Handler')
  .add(stickyNote)
  .add(errorTriggerNode)
  .to(extractErrorContext)
  .to(ifCanPatchRun
    .onTrue(patchPipelineRun.to(ifIsOnboarding
      .onTrue(patchOnboardingSession.to(postOpsAlert))
      .onFalse(postOpsAlert)
    ))
    .onFalse(postOpsAlert)
  );
