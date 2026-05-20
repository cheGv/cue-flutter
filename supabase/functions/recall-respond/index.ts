// supabase/functions/recall-respond/index.ts
//
// Cue Recall Assistant — Tier 2 (model) path of the natural-language
// recall layer. Tier 1 (the unambiguous-intent local resolver) runs
// on-device in Flutter and never reaches this function. Only loose
// natural-language, relative-time, and Tier-1-miss queries route here.
//
// Spec contract (the Cue Recall Assistant spec, design-locked):
//   §2  Transport: invoked via _sb.functions.invoke('recall-respond')
//       with the caller's JWT forwarded, so every supabase.from(...)
//       below runs under the SLP's RLS policies. The model NEVER
//       receives a DB connection; scoping is server-side.
//   §3  Prompt: strict retrieval/assembly only. NO reasoning, NO
//       causation, NO recommendations. outOfScope is a first-class
//       return; do not soften the boundary.
//   §3  Output: strict JSON only, validated against the §3 schema.
//   §6a Instrumentation: every Tier 2 invocation logs to
//       recall_query_log. Clinical-grade data, RLS-protected.
//   §6a Context payload discipline: resolve to one client first,
//       fetch only that client's relevant records. Never the whole
//       caseload "just in case".
//
// Server-side persistence is intentionally NONE (spec §2):
//   - No recall_threads / recall_messages tables.
//   - The B-principle carried-client lives in client-side session
//     memory across turns.
//   - The only durable write here is the instrumentation log row.
//
// Defaults mirror reasoning-respond (verified 2026-05-18 at
// supabase/functions/reasoning-respond/index.ts):
//   model claude-sonnet-4-5, anthropic-version 2023-06-01,
//   single-response (no streaming), CORS allow-all.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

// CORS posture inherited verbatim from reasoning-respond / narrator — not a Recall-specific decision.
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const ANTHROPIC_MODEL = "claude-sonnet-4-5";
const ANTHROPIC_VERSION = "2023-06-01";

// Smaller than reasoning-respond (2048). Recall answers are 1-3
// sentences of inert assembled fact; large budgets invite drift.
const MAX_OUTPUT_TOKENS = 384;

// SPEC §3 — clinical safety surface. Changes here are clinical
// changes, not copy edits, and must be reviewed as such.
const SYSTEM_PROMPT = `You are Cue Recall, the retrieval layer of Cue. You sit alongside an authenticated Speech-Language Pathologist who is working with her own clients. You are addressing only her, about children she already serves.

WHAT YOU ARE NOT:
You are NOT a reasoning layer. The clinician has a separate tool, Cue Reasoning, for causation, recommendations, clinical judgment, and "why" questions. Anything that requires reasoning belongs there, not here.

WHAT YOU DO:
- Resolve client identity from natural phrasing ("Rishi", "the boy who comes Tuesdays") and from the carried conversational context supplied in CONTEXT.
- Resolve relative time ("two weeks ago", "lately", "recently") against the dated records in CONTEXT.
- Assemble factual answers from the data provided. 1 to 3 sentences. Inert facts only — never arrange facts so their juxtaposition implies a causal story you did not state.
- If no client is named in this turn and a carried client is present in CONTEXT, use that carried client AND set carried: true in your response. The UI surfaces this so the clinician can self-correct a wrong assumption in one glance.

HARD PROHIBITIONS — returning these is a failure:
- No causal inference. Never assert what "worked", what "didn't work", what caused what.
- No recommendations. Never tell the clinician what to do next.
- No answering "why".
- No probabilities or likelihoods.
- No general clinical knowledge to fill gaps. Answer ONLY from facts present in CONTEXT.

OUT OF SCOPE:
If the question requires clinical judgment, causation, or recommendation — even if you could attempt it — return outOfScope: true with a brief note that Cue Reasoning is the right place. Do NOT attempt the answer. Do NOT soften the boundary with hedged language. Out-of-scope is a first-class response, not a failure.

GROUNDING:
If the answer is not in CONTEXT, say so plainly. Never fabricate. Never fill gaps with general clinical knowledge.

WHEN AMBIGUOUS:
If you cannot tell which client the clinician means, ask which child. Set client: null, carried: false, outOfScope: false, and put the clarifying question in answer.

OUTPUT — STRICT JSON ONLY:
No prose. No markdown. No code fences. No preamble. Return only the JSON object, nothing before or after.

Schema:
{
  "client": "<client name or null>",
  "carried": <true if you used the carried client from CONTEXT, false otherwise>,
  "outOfScope": <true if the question needs reasoning/causation/recommendation, false otherwise>,
  "answer": "<1-3 sentence factual answer, OR out-of-scope explanation, OR which-child clarifying question>",
  "source": "<short provenance label, e.g. 'last 3 sessions' or 'current STG', or empty string>"
}`;

interface RequestBody {
  query?: string;
  carried_client_id?: string;
  // Client-supplied classification for instrumentation. The resolver
  // on the Flutter side knows whether this fell through from Tier 1
  // ('tier1_miss'), came in as loose natural language directly
  // ('loose_language'), or involves relative time ('relative_time').
  // The edge function cannot infer this — it just receives a string.
  tier1_miss_classification?: "loose_language" | "relative_time" | "tier1_miss";
}

interface RecallResponse {
  client: string | null;
  carried: boolean;
  outOfScope: boolean;
  answer: string;
  source: string;
}

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

function errorResponse(error: string, status: number, detail?: unknown) {
  console.error(`[recall-respond] ${error}`, detail ?? "");
  return jsonResponse({ error, detail: detail ? String(detail) : undefined }, status);
}

// The model is instructed to return strict JSON. If it strays into
// code fences or a preamble we try to recover the first {...} block
// before giving up. Anything past that and we surface invalid output
// rather than guessing.
function parseStrictJson(text: string): unknown {
  const trimmed = text.trim();
  try {
    return JSON.parse(trimmed);
  } catch (_) {
    const match = trimmed.match(/\{[\s\S]*\}/);
    if (!match) return null;
    try {
      return JSON.parse(match[0]);
    } catch (_) {
      return null;
    }
  }
}

function isValidRecallShape(o: unknown): o is RecallResponse {
  if (!o || typeof o !== "object") return false;
  const r = o as Record<string, unknown>;
  return (
    (r.client === null || typeof r.client === "string") &&
    typeof r.carried === "boolean" &&
    typeof r.outOfScope === "boolean" &&
    typeof r.answer === "string" &&
    typeof r.source === "string"
  );
}

serve(async (req: Request) => {
  const t0 = Date.now();

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS });
  }
  if (req.method !== "POST") {
    return errorResponse("method_not_allowed", 405);
  }

  let body: RequestBody;
  try {
    body = (await req.json()) as RequestBody;
  } catch {
    return errorResponse("invalid_json", 400);
  }

  const { query, carried_client_id, tier1_miss_classification } = body ?? {};

  if (!query || typeof query !== "string" || query.trim().length === 0) {
    return errorResponse("missing_query", 400);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return errorResponse("missing_auth_header", 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")!;

  // JWT-forwarded client. Every supabase.from(...).select(...) below
  // runs under the SLP's RLS policies — the §2 safety story made
  // concrete. The model never receives a DB connection; scoping is
  // not optional and not client-trust-dependent.
  const supabase = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });

  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData?.user) {
    return errorResponse("unauthorized", 401, userError?.message);
  }
  const user = userData.user;

  // --- Context assembly (server-side, RLS-scoped) ------------------
  //
  // Spec §6a payload discipline: resolve to one client first, then
  // fetch only that client's records. The roster (id + name only) is
  // included so the model can disambiguate when the query names a
  // different child than the carried one; it is intentionally minimal.

  const { data: roster } = await supabase
    .from("clients")
    .select("id,name")
    .order("name");

  let carriedClient: { id: string; name: string } | null = null;
  let carriedClientRecords = "";

  if (carried_client_id) {
    const { data: c } = await supabase
      .from("clients")
      .select("id,name,age,population_type,primary_language,diagnosis")
      .eq("id", carried_client_id)
      .maybeSingle();

    if (c) {
      carriedClient = { id: c.id as string, name: c.name as string };

      const { data: ltgs } = await supabase
        .from("long_term_goals")
        .select("goal_text,domain,status")
        .eq("client_id", c.id)
        .order("sequence_num");

      const { data: stgs } = await supabase
        .from("short_term_goals")
        .select("target_behavior,domain,status,target_accuracy,current_accuracy,current_cue_level")
        .eq("client_id", c.id)
        .in("status", ["active", "in_progress"])
        .order("sequence_num");

      const { data: sessions } = await supabase
        .from("sessions")
        .select("date,duration_minutes,soap_note,notes,parent_update")
        .eq("client_id", c.id)
        .order("date", { ascending: false })
        .limit(5);

      const parts: string[] = [];
      parts.push(
        `Carried client: ${c.name}` +
          (c.age != null ? `, age ${c.age}` : "") +
          (c.diagnosis ? `, diagnosis: ${c.diagnosis}` : "") +
          (c.population_type ? `, population: ${c.population_type}` : "") +
          (c.primary_language ? `, primary language: ${c.primary_language}` : "") +
          ".",
      );

      if (ltgs && ltgs.length > 0) {
        parts.push(`Long-term goals (${ltgs.length}):`);
        ltgs.forEach((l: any, i: number) => {
          parts.push(
            `  ${i + 1}. [${l.status ?? "draft"}] ${l.goal_text ?? "(empty)"} — domain: ${l.domain ?? "unspecified"}`,
          );
        });
      }

      if (stgs && stgs.length > 0) {
        parts.push(`Active short-term goals (${stgs.length}):`);
        stgs.forEach((s: any, i: number) => {
          const acc = s.target_accuracy != null ? `${s.target_accuracy}% target` : "no target accuracy";
          const cur = s.current_accuracy != null ? `${s.current_accuracy}% current` : "no current measurement";
          parts.push(
            `  ${i + 1}. ${s.target_behavior ?? "(no target)"} | ${acc}, ${cur} | cue: ${s.current_cue_level ?? "unspecified"}`,
          );
        });
      }

      if (sessions && sessions.length > 0) {
        parts.push(`Recent sessions (most recent first, ${sessions.length}):`);
        sessions.forEach((s: any, i: number) => {
          const blob: string = s.soap_note || s.notes || s.parent_update || "(no notes)";
          const trunc = blob.length > 500 ? `${blob.slice(0, 497)}...` : blob;
          const dur = s.duration_minutes != null ? ` (${s.duration_minutes} min)` : "";
          parts.push(`  ${i + 1}. ${s.date ?? "(no date)"}${dur}: ${trunc}`);
        });
      }

      carriedClientRecords = parts.join("\n");
    }
  }

  const rosterText = (roster ?? [])
    .map((r: any) => `- ${r.name} (id: ${r.id})`)
    .join("\n");

  const contextBlock = [
    "ROSTER (this clinician's clients — for disambiguation only, not the answer source):",
    rosterText || "(no clients in roster)",
    "",
    carriedClient
      ? carriedClientRecords
      : "No carried client. If the query does not name a client, ask which child.",
  ].join("\n");

  // --- Anthropic call ----------------------------------------------
  const anthropicKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (!anthropicKey) {
    return errorResponse(
      "anthropic_key_not_configured",
      500,
      "Set ANTHROPIC_API_KEY in Supabase Edge Function secrets",
    );
  }

  const userMessage = `CONTEXT:\n${contextBlock}\n\nQUERY:\n${query.trim()}`;

  const anthropicRes = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": anthropicKey,
      "anthropic-version": ANTHROPIC_VERSION,
    },
    body: JSON.stringify({
      model: ANTHROPIC_MODEL,
      max_tokens: MAX_OUTPUT_TOKENS,
      system: SYSTEM_PROMPT,
      messages: [{ role: "user", content: userMessage }],
    }),
  });

  if (!anthropicRes.ok) {
    const errText = await anthropicRes.text();
    return errorResponse("anthropic_failed", 502, `${anthropicRes.status}: ${errText}`);
  }

  const anthropicData = await anthropicRes.json();
  const rawText: string = anthropicData.content?.[0]?.text ?? "";

  const parsed = parseStrictJson(rawText);
  if (!isValidRecallShape(parsed)) {
    return errorResponse(
      "invalid_model_output",
      502,
      `Model did not return valid JSON matching the §3 schema. Raw start: ${rawText.slice(0, 200)}`,
    );
  }

  // --- Instrumentation log (§6a) -----------------------------------
  // Best-effort: a log failure must NEVER fail the user-visible
  // response. The clinician must not see a recall question fail
  // because instrumentation hiccupped. End-to-end latency is recorded
  // BEFORE this insert so the metric reflects the response path the
  // user actually felt, not the response-plus-log path.
  const latency = Date.now() - t0;
  const { error: logError } = await supabase
    .from("recall_query_log")
    .insert({
      clinician_id: user.id,
      query_text: query.trim(),
      tier: "tier2",
      sub_classification: tier1_miss_classification ?? null,
      latency_ms: latency,
    });
  if (logError) {
    console.error("[recall-respond] instrumentation insert failed", logError);
  }

  return jsonResponse(parsed);
});
