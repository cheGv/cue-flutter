// supabase/functions/narrator/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const SYSTEM_PROMPT = `You are Cue, a clinical documentation assistant for Pediatric Speech-Language Pathologists (SLPs) trained in AIISH methodology.

Your task: Convert a raw session transcript into a structured clinical note.

CRITICAL: Respond ONLY with a single valid JSON object. No markdown. No backticks. No preamble. No explanation.

Required JSON schema:
{
  "soap_note": {
    "subjective": "caregiver/child reports, presenting concerns, behavioral observations",
    "objective": "measurable clinical findings: accuracy rates, trials, prompting levels",
    "assessment": "clinical interpretation, progress toward goals, response to intervention",
    "plan": "next session targets, home program recommendations, frequency adjustments"
  },
  "parent_summary": "a warm, jargon-free 2-3 sentence explanation of today's session for a parent"
}

If no meaningful clinical content, return:
{ "soap_note": null, "parent_summary": null, "error": "no_speech_detected" }

Always use neurodiversity-affirming, strengths-based language.`;

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const openaiKey = Deno.env.get("OPENAI_API_KEY");
    if (!openaiKey) throw new Error("OPENAI_API_KEY not configured");

    const audioBytes = await req.arrayBuffer();
    if (!audioBytes.byteLength) {
      return new Response(JSON.stringify({ error: "no_audio_data" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400,
      });
    }

    const formData = new FormData();
    formData.append("file", new Blob([audioBytes], { type: "audio/webm" }), "session.webm");
    formData.append("model", "whisper-1");
    formData.append("language", "en");

    const whisperRes = await fetch("https://api.openai.com/v1/audio/transcriptions", {
      method: "POST",
      headers: { Authorization: `Bearer ${openaiKey}` },
      body: formData,
    });

    if (!whisperRes.ok) throw new Error(`Whisper error: ${await whisperRes.text()}`);

    const whisperData = await whisperRes.json();
    const transcript: string = whisperData.text?.trim() ?? "";

    if (!transcript || transcript.length < 10) {
      return new Response(
        JSON.stringify({ transcript: "", soap_note: null, parent_summary: null, error: "no_speech_detected" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 }
      );
    }

    const gptRes = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: { Authorization: `Bearer ${openaiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        model: "gpt-4o-mini",
        response_format: { type: "json_object" },
        temperature: 0.2,
        max_tokens: 1200,
        messages: [
          { role: "system", content: SYSTEM_PROMPT },
          { role: "user", content: `Session transcript:\n\n${transcript}` },
        ],
      }),
    });

    if (!gptRes.ok) throw new Error(`GPT error: ${await gptRes.text()}`);

    const gptData = await gptRes.json();
    const parsed = JSON.parse(gptData.choices?.[0]?.message?.content ?? "{}");

    return new Response(
      JSON.stringify({
        transcript,
        soap_note: parsed.soap_note ?? null,
        parent_summary: parsed.parent_summary ?? null,
        error: parsed.error ?? null,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 }
    );

  } catch (e) {
    console.error("[Narrator] Error:", e);
    return new Response(
      JSON.stringify({ error: "internal_error", message: (e as Error).message }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 500 }
    );
  }
});
