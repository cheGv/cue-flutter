// supabase/functions/recall-classify/index.ts
//
// Cue Recall Assistant — classification latency probe.
//
// Purpose: measure model-classification latency in ISOLATION. Not a
// resolver. Does NOT fetch DB data, does NOT compose an answer, does
// NOT cite frameworks. It receives a question plus an injected list of
// possible intents and a list of in-scope client names, and returns a
// single tiny JSON object: {intent, client}.
//
// The `intents` list is parameterised (passed in by the caller, not
// hardcoded here) — deliberate, this is the extensible-registry design.
// The function never owns the intent vocabulary; callers do.
//
// Auth + model: mirrors recall-respond verbatim so the measured latency
// is apples-to-apples with the full recall path. Same model, same
// anthropic-version, same JWT-forwarded supabase client + auth.getUser()
// check. The only intentional differences vs. recall-respond:
//   • No DB fetches (clients / sessions / goals).
//   • No instrumentation log write.
//   • MAX_OUTPUT_TOKENS dropped to 64 — the output is a ~40-token JSON
//     object; tight cap also disincentivises the model from drifting
//     into explanatory prose.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// Mirrors recall-respond verbatim — same model + version so latency is
// directly comparable.
const ANTHROPIC_MODEL = "claude-sonnet-4-5";
const ANTHROPIC_VERSION = "2023-06-01";

// 64 is generous for a ~40-token JSON object. Tight cap prevents the
// model from emitting explanatory prose past the JSON close.
const MAX_OUTPUT_TOKENS = 64;

interface RequestBody {
  question?: string;
  clients?: string[];
  intents?: string[];
}

interface ClassifyResponse {
  intent: string;
  client: string | null;
}

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

function errorResponse(error: string, status: number, detail?: unknown) {
  console.error(`[recall-classify] ${error}`, detail ?? "");
  return jsonResponse({ error, detail: detail ? String(detail) : undefined }, status);
}

// The model is instructed to return strict JSON. If it strays into
// code fences or a preamble we try to recover the first {...} block
// before giving up. Same shape as recall-respond's parser.
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

// Validation: the model's `intent` must be in the caller-supplied list.
// We do NOT validate the client name against the clients list — the
// model occasionally surfaces a sensible client identifier the caller
// didn't include (e.g. a nickname). The caller can decide whether to
// honour the response or re-prompt. Intent vocab is the stricter rail.
function isValidShape(o: unknown, intents: string[]): o is ClassifyResponse {
  if (!o || typeof o !== "object") return false;
  const r = o as Record<string, unknown>;
  return (
    typeof r.intent === "string" &&
    intents.includes(r.intent) &&
    (r.client === null || typeof r.client === "string")
  );
}

function buildSystemPrompt(intents: string[], clients: string[]): string {
  const intentsLine = intents.join(", ");
  const clientsLine = clients.length === 0 ? "(none)" : clients.join(", ");
  return `You are the classification stage of the Cue Recall Assistant. You receive a single natural-language question from a Speech-Language Pathologist and you classify it.

You do NOT answer the question. You do NOT compose prose. You do NOT explain your choice. You output a single tiny JSON object and nothing else.

ALLOWED INTENTS (pick exactly one — never invent a new label, never return a label outside this list):
${intentsLine}

CLINICIAN'S CLIENTS (pick exactly one if the question names or clearly implies one of these children; otherwise null — never invent a client not in this list):
${clientsLine}

OUTPUT — STRICT JSON ONLY:
No prose. No markdown. No code fences. No preamble. No trailing explanation. Return only the JSON object, nothing before or after.

Schema:
{
  "intent": "<one of the allowed intents above, verbatim>",
  "client": "<one of the clients above verbatim, or null>"
}`;
}

serve(async (req: Request) => {
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

  const { question, clients, intents } = body ?? {};

  if (!question || typeof question !== "string" || question.trim().length === 0) {
    return errorResponse("missing_question", 400);
  }
  if (
    !Array.isArray(intents) ||
    intents.length === 0 ||
    !intents.every((i) => typeof i === "string" && i.length > 0)
  ) {
    return errorResponse("missing_or_invalid_intents", 400);
  }
  const clientList: string[] =
    Array.isArray(clients) && clients.every((c) => typeof c === "string")
      ? clients
      : [];

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return errorResponse("missing_auth_header", 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")!;

  // JWT-forwarded client. Same pattern as recall-respond — so the
  // measured latency includes the same auth-check overhead. No DB
  // fetches beyond this auth check.
  const supabase = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });

  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData?.user) {
    return errorResponse("unauthorized", 401, userError?.message);
  }

  const anthropicKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (!anthropicKey) {
    return errorResponse(
      "anthropic_key_not_configured",
      500,
      "Set ANTHROPIC_API_KEY in Supabase Edge Function secrets",
    );
  }

  const systemPrompt = buildSystemPrompt(intents, clientList);
  const userMessage = `QUESTION:\n${question.trim()}`;

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
      system: systemPrompt,
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
  if (!isValidShape(parsed, intents)) {
    return errorResponse(
      "invalid_model_output",
      502,
      `Model did not return valid JSON or returned an intent not in the provided list. Raw start: ${rawText.slice(0, 200)}`,
    );
  }

  return jsonResponse(parsed);
});
