// supabase/functions/recall-card/index.ts
//
// Cue Recall Assistant — card-get endpoint (lazy assembly on read).
//
// Architecture (v2, 2026-05-19):
//   • recall_cards table holds the assembled per-client payload as
//     jsonb plus an is_dirty flag.
//   • Triggers on sessions / short_term_goals / long_term_goals mark
//     a client's card dirty on any mutation. Triggers do NOT compute
//     card content.
//   • Card assembly lives in ONE Postgres function:
//     public.assemble_recall_card(client_id uuid) -> jsonb. Both this
//     edge function (lazy, via RPC under the SLP's JWT) and the
//     backfill script (eager, server-side) call that function. They
//     cannot diverge — Postgres is the only serializer in either
//     path.
//   • THIS endpoint's job: gate on the clients pre-check, return the
//     cached card if !is_dirty, else invoke the RPC to assemble fresh
//     and write it back. No assembly logic lives in TypeScript.
//
// Request:  POST { "client_id": "<uuid>" }
// Response: 200 { "source": "cache" | "fresh", "card": {...} }
//
// Auth: JWT-forwarded, verify_jwt: true. The clients pre-check is
// RLS-scoped, so a foreign client_id returns null and we 404 without
// touching sessions / goals. This is also the only barrier on
// production (where sessions RLS is off as of 2026-05-19); on sandbox
// the inner queries via the RPC are RLS-scoped too — defense in depth.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

interface RequestBody {
  client_id?: string;
}

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

function errorResponse(error: string, status: number, detail?: unknown) {
  console.error(`[recall-card] ${error}`, detail ?? "");
  return jsonResponse({ error, detail: detail ? String(detail) : undefined }, status);
}

// Minimal UUID shape check — Postgres will reject malformed UUIDs
// anyway, but failing fast here gives a cleaner 400 than a 500.
function isUuid(s: unknown): s is string {
  return typeof s === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(s);
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

  const clientId = body?.client_id;
  if (!isUuid(clientId)) {
    return errorResponse("missing_or_invalid_client_id", 400);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return errorResponse("missing_auth_header", 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")!;

  // JWT-forwarded client. Every supabase call below runs under the
  // SLP's RLS policies. The clients pre-check + the RPC's inner
  // queries (via SECURITY INVOKER on assemble_recall_card) are all
  // scoped to auth.uid() on sandbox; on production the clients
  // pre-check is the single barrier (sessions RLS off — known debt).
  const supabase = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });

  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData?.user) {
    return errorResponse("unauthorized", 401, userError?.message);
  }
  const user = userData.user;

  // ── Pre-check: does this client belong to the calling clinician?
  //
  // RLS on clients filters this lookup to the SLP's own caseload. A
  // foreign client_id returns null and we 404 without ever invoking
  // the assembler RPC.
  const { data: clientRow } = await supabase
    .from("clients")
    .select("id")
    .eq("id", clientId)
    .maybeSingle();
  if (!clientRow) {
    return errorResponse("client_not_found", 404);
  }

  // ── Cache hit? ───────────────────────────────────────────────────
  const { data: cacheRow } = await supabase
    .from("recall_cards")
    .select("card, is_dirty")
    .eq("client_id", clientId)
    .maybeSingle();

  if (cacheRow && cacheRow.is_dirty === false && cacheRow.card != null) {
    return jsonResponse({ source: "cache", card: cacheRow.card });
  }

  // ── Cache miss / dirty — assemble via the shared SQL function ──
  //
  // public.assemble_recall_card(uuid) is the single source of truth
  // for card content. Same function the backfill calls. Output is
  // byte-identical regardless of which path triggered it; Postgres
  // is the only serializer in the loop.
  const { data: assembled, error: rpcError } = await supabase.rpc(
    "assemble_recall_card",
    { p_client_id: clientId },
  );

  if (rpcError || assembled == null) {
    return errorResponse(
      "assembly_failed",
      502,
      rpcError?.message ?? "assemble_recall_card returned null",
    );
  }

  // ── Write back: store the assembled card, clear dirty ──────────
  //
  // Best-effort. A writeback failure logs and still returns the
  // freshly assembled card; the next read will re-assemble.
  const { error: upsertError } = await supabase
    .from("recall_cards")
    .upsert(
      {
        client_id: clientId,
        user_id: user.id,
        card: assembled,
        is_dirty: false,
        updated_at: new Date().toISOString(),
      },
      { onConflict: "client_id" },
    );
  if (upsertError) {
    console.error("[recall-card] writeback failed", upsertError);
  }

  return jsonResponse({ source: "fresh", card: assembled });
});
