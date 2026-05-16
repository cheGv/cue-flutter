// supabase/functions/reasoning-respond/index.ts
// Phase 4.0.7.20c v2 — Cue Reasoning V1 edge function.
//
// v1 had column name mismatches against the actual schema:
//   - long_term_goals has goal_text, NOT target_behavior
//   - short_term_goals FK is long_term_goal_id, NOT ltg_id
//   - short_term_goals has context (not condition), and
//     mastery_criterion (jsonb) + target_accuracy + time_bound_sessions
//     (not a single criterion field)
//   - clients does not have age_years or clinical_lens
//
// v2 corrects all queries to the actual live schema.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const ANTHROPIC_MODEL = "claude-sonnet-4-5";
const MAX_OUTPUT_TOKENS = 2048;

const SYSTEM_PROMPT_BASE = `You are Cue Reasoning, a clinical reasoning partner for RCI- and ASHA-credentialed Speech-Language Pathologists. You sit alongside an SLP while she is *constructing* a therapy goal — a long-term goal (LTG) or short-term goal (STG) — and help her articulate the clinical defense for it.

WHO YOU ARE:
- A reasoning partner, not an answer-giver. The SLP is doing the thinking. You offer EBP-grounded prompts, framework alignment checks, operationalization stress-tests, and rationale articulation she can edit.
- Grounded ONLY in the framework library provided in this conversation. Cite frameworks by their short_code in [framework: short_code] format. Never invent frameworks or citations.
- Indian clinical English register. Direct. Specific. No filler. No "great question!" preambles.

WHO YOU ARE NOT:
- Cue Study (which lives on the client profile, retrospective and exploratory case-level chat). Cue Reasoning is prospective, constructive, scoped to one goal in active construction.
- A goal-writer. The SLP writes. You stress-test, ground in evidence, and offer revisions.

THREE QUERY PATTERNS YOU HANDLE WELL:

1. CHOICE DEFENSE — "Why am I picking [goal A] over [goal B]?"
   Pull relevant frameworks from the library. Apply them to the client's profile. Articulate the clinical case for the choice. End with: what evidence would change this choice?

2. STG OPERATIONALIZATION — "Does my STG actually measure what I think it measures?" / "Is this defensible against 80%/3-session standards?"
   Check the STG against framework criteria. Flag ambiguities (what does "spontaneously" mean operationally? what counts as an "opportunity"?). Offer tightened phrasing in a SUGGESTED REVISION block. Cite the framework that informs the operationalization.

3. FRAMEWORK ALIGNMENT — "What framework should I be reasoning from?" / "Is this consistent with [Framework X]?"
   Surface relevant frameworks from the library based on client profile and goal direction. Map developmental/clinical stage to framework stage. Suggest goal directions consistent with the framework. Or critique current alignment.

CITATION DISCIPLINE:
- Cite frameworks by short_code: [framework: lidcombe], [framework: ndbi-impact]
- For specific empirical claims, include author-year: (Onslow, 2003), (Schreibman et al., 2015)
- If you don't have evidence in the framework library for a claim: say "I don't have framework evidence for that — would [X] approach be relevant to consider?" Don't invent.
- Stick to frameworks present in the library. If the SLP names a framework not in the library, acknowledge: "That's not currently in the framework library I'm grounded in. I can reason about it from general clinical knowledge but I won't cite it as if I have its evidence base."

OUTPUT FORMAT:

Plain prose, conversational, 100-300 words unless the SLP asks for more depth. No markdown headers. No bullet lists unless responding to a request that genuinely requires a list.

When you suggest a specific revision to the SLP's goal text, format it cleanly:

SUGGESTED REVISION:
"<the revised goal text in quotes>"

This lets the SLP click "Apply" to inject your suggestion into the goal field. Make sure the revision stands as a complete, defensible goal statement.

When you cite a framework, write your reasoning so it stands up as clinical defense — the SLP may click "Cite this in goal rationale" and your text becomes the goal's evidence_rationale.

ALWAYS wrap framework citations in [framework: short_code] format — even when you mention them in flowing prose. Example: "This aligns with [framework: lidcombe], where parents deliver verbal contingencies." The Flutter UI parses these brackets to render clickable citation chips.

VOICE:
- Direct. Specific over general.
- Match the SLP's expertise level. If she names a framework, treat her as knowing it. If she's exploring, scaffold gently.
- Disagree when warranted. If her STG is poorly operationalized, say so directly with the fix.
- When you don't know, say so. "I don't see [X] in the framework library you've selected" beats inventing.

CONSTRAINTS:
- The SLP is the clinician. You are the reasoning partner. Never override her clinical judgment — present evidence and let her decide.
- Don't pathologize. Use neurodiversity-affirming, strengths-based language by default.
- For pediatric clients, never frame children as "broken" or "deficit-laden." For adult clients, never strip identity. The framework library includes affirming approaches (stuttering-affirming, gender-affirming voice, LPAA) — surface them when relevant.
- Indian context: many SLPs work multilingually. Honor code-switching and dialect-vs-disorder distinctions. The framework library includes Dynamic Assessment and Processing-Dependent Measures for multilingual learners — use them when relevant.
`;

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

function errorResponse(error: string, status: number, detail?: unknown) {
  console.error(`[reasoning-respond] ${error}`, detail ?? "");
  return jsonResponse({ error, detail: detail ? String(detail) : undefined }, status);
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS });
  }

  if (req.method !== "POST") {
    return errorResponse("method_not_allowed", 405);
  }

  try {
    let body: any;
    try {
      body = await req.json();
    } catch {
      return errorResponse("invalid_json", 400);
    }

    const {
      thread_id,
      client_id,
      ltg_id,
      stg_id,
      user_message,
      domains_active,
    } = body ?? {};

    if (!user_message || typeof user_message !== "string" || user_message.trim().length === 0) {
      return errorResponse("missing_user_message", 400);
    }

    // Phase 4.1.5 — new thread contract: a thread is valid when it
    // carries ANY ONE of (client_id, ltg_id, stg_id). The previous
    // `missing_goal_anchor` check rejected client-anchored Tier 2
    // threads. Reject only when none of the three is present.
    if (!thread_id && !client_id && !ltg_id && !stg_id) {
      return errorResponse(
        "missing_anchor",
        400,
        "new threads require client_id, ltg_id, or stg_id",
      );
    }

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return errorResponse("missing_auth_header", 401);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false },
    });

    const { data: userData, error: userError } = await supabase.auth.getUser();
    if (userError || !userData?.user) {
      return errorResponse("unauthorized", 401, userError?.message);
    }
    const user = userData.user;

    // Resolve or create thread
    let thread: any;
    if (thread_id) {
      const { data, error } = await supabase
        .from("reasoning_threads")
        .select("*")
        .eq("id", thread_id)
        .is("deleted_at", null)
        .maybeSingle();
      if (error) return errorResponse("thread_fetch_failed", 500, error.message);
      if (!data) return errorResponse("thread_not_found", 404);
      thread = data;
    } else {
      const { data, error } = await supabase
        .from("reasoning_threads")
        .insert({
          clinician_id: user.id,
          client_id,
          ltg_id: ltg_id ?? null,
          stg_id: stg_id ?? null,
          domains_active: Array.isArray(domains_active) ? domains_active : [],
        })
        .select("*")
        .single();
      if (error) return errorResponse("thread_create_failed", 500, error.message);
      thread = data;
    }

    // Phase 4.1.5 — anchor type is recorded so the context assembled
    // below differs by tier. stg / ltg paths are byte-for-byte unchanged;
    // 'client' is the new Tier 2 path added below.
    const anchorType: "stg" | "ltg" | "client" = thread.stg_id
      ? "stg"
      : thread.ltg_id
        ? "ltg"
        : "client";

    // Goal context — v2: schema-correct queries
    let goalContextText = "";
    if (thread.ltg_id) {
      const { data: ltg } = await supabase
        .from("long_term_goals")
        .select("goal_text,domain,framework,evidence_rationale,rationale,status,time_frame_weeks,target_date")
        .eq("id", thread.ltg_id)
        .maybeSingle();
      if (ltg) {
        const goalText = ltg.goal_text || "(empty draft)";
        goalContextText += `LTG (${ltg.status ?? "draft"}, domain: ${ltg.domain ?? "unspecified"}):\n${goalText}\n`;
        if (ltg.framework) goalContextText += `Currently anchored to framework: ${ltg.framework}\n`;
        if (ltg.time_frame_weeks) goalContextText += `Time frame: ${ltg.time_frame_weeks} weeks\n`;
        if (ltg.evidence_rationale) goalContextText += `Existing evidence rationale: ${ltg.evidence_rationale}\n`;
        if (ltg.rationale) goalContextText += `Existing rationale: ${ltg.rationale}\n`;
      }
      const { data: stgs } = await supabase
        .from("short_term_goals")
        .select("target_behavior,context,measurable,specific,target_accuracy,mastery_criterion,time_bound_sessions,current_accuracy,initial_cue_level,current_cue_level,framework,status")
        .eq("long_term_goal_id", thread.ltg_id)
        .order("sequence_num");
      if (stgs && stgs.length > 0) {
        goalContextText += `\nSTGs under this LTG:\n`;
        stgs.forEach((stg: any, i: number) => {
          const target = stg.target_behavior ?? "(no target set)";
          const ctx = stg.context || "(no context)";
          const accuracy = stg.target_accuracy != null ? `${stg.target_accuracy}%` : "unspecified";
          const sessions = stg.time_bound_sessions != null ? `over ${stg.time_bound_sessions} sessions` : "";
          const cueLevel = stg.current_cue_level || stg.initial_cue_level || "unspecified";
          goalContextText += `${i + 1}. ${target} | Context: ${ctx} | Criterion: ${accuracy} ${sessions} | Cue level: ${cueLevel} | Framework: ${stg.framework ?? "none"} | Status: ${stg.status ?? "draft"}\n`;
        });
      }
    } else if (thread.stg_id) {
      const { data: stg } = await supabase
        .from("short_term_goals")
        .select("target_behavior,context,measurable,specific,target_accuracy,mastery_criterion,time_bound_sessions,current_accuracy,initial_cue_level,current_cue_level,cue_fade_plan,framework,status")
        .eq("id", thread.stg_id)
        .maybeSingle();
      if (stg) {
        const accuracy = stg.target_accuracy != null ? `${stg.target_accuracy}%` : "unspecified";
        const sessions = stg.time_bound_sessions != null ? `over ${stg.time_bound_sessions} sessions` : "";
        goalContextText += `STG (${stg.status ?? "draft"}):\nTarget: ${stg.target_behavior ?? "(no target set)"}\nContext: ${stg.context || "(none)"}\nCriterion: ${accuracy} ${sessions}\nCue level: ${stg.current_cue_level || stg.initial_cue_level || "unspecified"}\nFramework: ${stg.framework ?? "none"}\n`;
        if (stg.cue_fade_plan) goalContextText += `Cue fade plan: ${stg.cue_fade_plan}\n`;
      }
    } else if (anchorType === "client") {
      // Phase 4.1.5 — Tier 2 (client-anchored) context. Loads active
      // STGs, all LTGs, and the most recent 2 sessions so the model
      // can reason at the case level without a specific goal anchor.
      // Sessions summary uses soap_note → notes → parent_update in
      // priority order; truncate each session blob to ~600 chars so
      // long SOAP notes don't dominate the context window.
      const { data: activeStgs } = await supabase
        .from("short_term_goals")
        .select("id,target_behavior,specific,domain,status")
        .eq("client_id", thread.client_id)
        .in("status", ["active", "in_progress"])
        .order("sequence_num");
      if (activeStgs && activeStgs.length > 0) {
        goalContextText += `Active STGs (${activeStgs.length}):\n`;
        activeStgs.forEach((s: any, i: number) => {
          const body = s.target_behavior ?? s.specific ?? "(no target)";
          goalContextText += `${i + 1}. ${body} | Domain: ${s.domain ?? "unspecified"} | Status: ${s.status}\n`;
        });
        goalContextText += `\n`;
      }
      const { data: ltgs } = await supabase
        .from("long_term_goals")
        .select("id,goal_text,domain,status")
        .eq("client_id", thread.client_id)
        .order("sequence_num");
      if (ltgs && ltgs.length > 0) {
        goalContextText += `Long-term goals (${ltgs.length}):\n`;
        ltgs.forEach((l: any, i: number) => {
          goalContextText += `${i + 1}. ${l.goal_text} | Domain: ${l.domain} | Status: ${l.status}\n`;
        });
        goalContextText += `\n`;
      }
      const { data: recent } = await supabase
        .from("sessions")
        .select("date,duration_minutes,soap_note,notes,parent_update")
        .eq("client_id", thread.client_id)
        .order("date", { ascending: false })
        .limit(2);
      if (recent && recent.length > 0) {
        goalContextText += `Most recent sessions (${recent.length}):\n`;
        recent.forEach((sess: any, i: number) => {
          const raw: string = sess.soap_note || sess.notes || sess.parent_update || "(no notes captured)";
          const trunc = raw.length > 600 ? `${raw.slice(0, 597)}...` : raw;
          const dur = sess.duration_minutes != null ? ` (${sess.duration_minutes} min)` : "";
          goalContextText += `${i + 1}. ${sess.date ?? "(no date)"}${dur}: ${trunc}\n`;
        });
      }
    }

    // Client context — v2: only fields that exist.
    // Phase 4.1.5 — pull age + diagnosis additively so the Tier 2
    // client-anchored prompt has demographic anchors. The stg/ltg
    // paths still get the same name/population/language line they
    // got before (additive fields are simply not surfaced for those
    // paths' system prompt block).
    const { data: client } = await supabase
      .from("clients")
      .select("name,population_type,primary_language,age,diagnosis")
      .eq("id", thread.client_id)
      .maybeSingle();

    let clientContext = "";
    if (client) {
      const parts: (string | null)[] = [
        `Client: ${client.name ?? "(unnamed)"}`,
        client.population_type ? `population: ${client.population_type}` : null,
        client.primary_language ? `primary language: ${client.primary_language}` : null,
      ];
      // Phase 4.1.5 — Tier 2 anchored threads add age + diagnosis to the
      // single-line client header. stg / ltg paths keep their existing
      // shape (the additional fields are only surfaced when anchor_type
      // is 'client').
      if (anchorType === "client") {
        if (client.age != null) parts.push(`age ${client.age}`);
        if (client.diagnosis) parts.push(`diagnosis: ${client.diagnosis}`);
      }
      clientContext = parts.filter(Boolean).join(", ");
    }

    // Frameworks (filtered by domains_active)
    let fwQuery = supabase
      .from("frameworks")
      .select("id,short_code,name,full_name,description,domains,populations,when_to_use,key_authors,evidence_level,approach_type")
      .eq("active", true);
    if (Array.isArray(thread.domains_active) && thread.domains_active.length > 0) {
      fwQuery = fwQuery.overlaps("domains", thread.domains_active);
    }
    const { data: frameworks, error: fwError } = await fwQuery;
    if (fwError) console.error("[reasoning-respond] frameworks fetch error:", fwError);

    const frameworksText = (frameworks ?? [])
      .map((f: any) => {
        const firstAuthor = Array.isArray(f.key_authors) && f.key_authors.length > 0
          ? f.key_authors[0].split(",")[0]
          : "various";
        return `[${f.short_code}] ${f.name}: ${f.description} | Use when: ${f.when_to_use ?? "various"} | Author: ${firstAuthor} | Evidence: ${f.evidence_level ?? "unrated"}`;
      })
      .join("\n");

    // Conversation history
    const { data: history } = await supabase
      .from("reasoning_messages")
      .select("role,content,created_at")
      .eq("thread_id", thread.id)
      .order("created_at", { ascending: true });

    const historyMessages = (history ?? []).map((m: any) => ({
      role: m.role as "user" | "assistant",
      content: m.content,
    }));

    // Persist user message FIRST
    const { error: userMsgError } = await supabase
      .from("reasoning_messages")
      .insert({
        thread_id: thread.id,
        role: "user",
        content: user_message,
      });
    if (userMsgError) {
      return errorResponse("user_message_save_failed", 500, userMsgError.message);
    }

    const domainsLabel = (Array.isArray(thread.domains_active) && thread.domains_active.length > 0)
      ? thread.domains_active.join(", ")
      : "all (no filter set)";

    const systemPrompt = `${SYSTEM_PROMPT_BASE}

CURRENT GOAL CONTEXT:
${clientContext || "(no client context)"}

${goalContextText || "(no goal context yet — SLP may be opening Cue Reasoning before drafting the goal)"}

DOMAINS ACTIVE: ${domainsLabel}

FRAMEWORK LIBRARY (cite ONLY from this list, format: [framework: short_code]):
${frameworksText || "(no frameworks matched the active domains — fall back to general clinical reasoning, do not invent citations)"}
`;

    const anthropicKey = Deno.env.get("ANTHROPIC_API_KEY");
    if (!anthropicKey) {
      return errorResponse(
        "anthropic_key_not_configured",
        500,
        "Set ANTHROPIC_API_KEY in Supabase Edge Function secrets"
      );
    }

    const messages = [
      ...historyMessages,
      { role: "user" as const, content: user_message },
    ];

    const anthropicRes = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": anthropicKey,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: ANTHROPIC_MODEL,
        max_tokens: MAX_OUTPUT_TOKENS,
        system: systemPrompt,
        messages,
      }),
    });

    if (!anthropicRes.ok) {
      const errText = await anthropicRes.text();
      return errorResponse("anthropic_failed", 502, `${anthropicRes.status}: ${errText}`);
    }

    const anthropicData = await anthropicRes.json();
    const assistantText: string = anthropicData.content?.[0]?.text ?? "";
    const tokenUsage = {
      input: anthropicData.usage?.input_tokens ?? 0,
      output: anthropicData.usage?.output_tokens ?? 0,
    };

    const citationMatches = [...assistantText.matchAll(/\[framework:\s*([\w-]+)\s*\]/gi)];
    const citedShortCodes = [...new Set(citationMatches.map((m) => m[1]))];

    const citedFrameworkIds = (frameworks ?? [])
      .filter((f: any) => citedShortCodes.includes(f.short_code))
      .map((f: any) => f.id);

    const revisionMatch = assistantText.match(/SUGGESTED REVISION:\s*"([^"]+)"/);
    const suggestedRevision = revisionMatch ? revisionMatch[1] : null;

    const { data: assistantMsg, error: assistantMsgError } = await supabase
      .from("reasoning_messages")
      .insert({
        thread_id: thread.id,
        role: "assistant",
        content: assistantText,
        framework_ids: citedFrameworkIds,
        citations: citedShortCodes.map((sc) => ({ short_code: sc })),
        token_usage: tokenUsage,
      })
      .select("*")
      .single();

    if (assistantMsgError) {
      console.error("[reasoning-respond] Assistant message save failed:", assistantMsgError);
    }

    if (historyMessages.length === 0 && !thread.title) {
      const trimmed = user_message.trim();
      const derivedTitle = trimmed.length > 60 ? `${trimmed.slice(0, 60)}…` : trimmed;
      await supabase
        .from("reasoning_threads")
        .update({ title: derivedTitle })
        .eq("id", thread.id);
    } else {
      await supabase
        .from("reasoning_threads")
        .update({ updated_at: new Date().toISOString() })
        .eq("id", thread.id);
    }

    const citedFrameworks = (frameworks ?? []).filter((f: any) =>
      citedShortCodes.includes(f.short_code)
    );

    return jsonResponse({
      thread_id: thread.id,
      message: assistantMsg,
      cited_frameworks: citedFrameworks,
      suggested_revision: suggestedRevision,
      token_usage: tokenUsage,
    });
  } catch (e) {
    return errorResponse("internal_error", 500, (e as Error).message);
  }
});
