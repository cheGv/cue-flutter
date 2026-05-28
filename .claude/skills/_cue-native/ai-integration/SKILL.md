# Skill: ai-integration
## When to use
Triggered when the task involves:
- Calling the Anthropic API (any model, any endpoint)
- Writing or modifying system prompts
- Narrator (Whisper STT + GPT-4o-mini SOAP) flow
- Any feature that generates clinical text, vocabulary, goals, or suggestions
- Structured output that lands in the database
- Voice features or voice cloning
- The vision-for-AAC pipeline
## The invariants
### A1. All Anthropic API calls go through the Render proxy
Never call `api.anthropic.com` directly from the Flutter client or from a user's browser.
- Proxy URL: `https://cue-ai-proxy.onrender.com`
- The proxy holds the API key in its environment variables.
- Client code calls the proxy; the proxy calls Anthropic.
- This protects the API key, allows rate limiting, and centralizes logging.
### A2. The anti-fabrication system prompt is the immutable preamble
Every clinical-content generation call prepends the anti-fabrication system prompt. It is loaded from a versioned file, never inlined as a string in a feature module.
- Path convention: `lib/ai/prompts/anti_fabrication.txt` (or equivalent in proxy).
- The preamble is appended to feature-specific instructions, not replaced by them.
- A feature cannot opt out of the preamble. If a use case seems to require fabrication tolerance, the use case is wrong — discuss with Guru.
### A3. System prompts live in versioned files
- No multi-line prompts as string literals in Dart or proxy code.
- Each prompt lives in its own file with a version comment at the top.
- Changes to a prompt are reviewed like code changes, with the diff visible.
### A4. Structured output for anything that touches the DB
If the LLM response will be parsed and persisted, use a JSON-mode / structured-output schema.
- Free-text LLM responses parsed via regex or string-matching are forbidden for DB-bound data.
- The schema is the contract. Schema lives in a versioned file alongside the prompt.
- Schema validation happens at the proxy boundary, not in the client.
### A5. "Insufficient information" must round-trip
When the model returns a structured "insufficient information" response (see `clinical-invariants` I4), it must:
- Be representable in the schema (a dedicated field or a null + reason).
- Surface to the clinician as an explicit "not enough info to suggest" state.
- NEVER be silently converted to empty string, null, or fabricated default downstream.
- Have an explicit test proving it round-trips intact.
### A6. PHI de-identification before prompting
See `_imported/security-and-secrets`. Concretely for AI calls:
- Patient names, identifiable photos, addresses, contact info are stripped before the prompt.
- Replace with stable opaque identifiers (`P_a3f2`) inside the prompt.
- The proxy is responsible for de-identification — clients send raw data, proxy strips and forwards.
- Re-identification happens client-side after the LLM response returns.
### A7. Voice features wait for Anthropic's 3rd-party voice API
The reflective voice companion feature is parked until Anthropic ships voice. Do not build it on a different vendor's stack — the entire AI surface stays on Anthropic for trust and integration reasons.
## Anti-rationalizations
| Excuse                                                            | Counter |
|-------------------------------------------------------------------|---------|
| "Direct API call is faster, no extra hop"                         | The extra hop is the security boundary. No exceptions. |
| "I'll inline this prompt, it's just a short one"                  | Inline prompts become un-version-controlled drift. File or nothing. |
| "Free-text response is fine, I'll parse it"                       | Parse fails on the day a clinical decision rides on it. Structured output, always. |
| "If the model can't help, I'll just show an empty result"         | Empty result = silent fabrication of "nothing wrong." Surface the insufficient-info state explicitly. |
| "Patient name in the prompt is fine, it's just for context"       | PHI in prompts is a DPDP violation. De-identify or don't send. |
| "Let me try a different voice provider in the meantime"           | Vendor sprawl breaks the trust narrative. Wait for Anthropic voice. |
| "The system prompt is huge, splitting it into files is overhead"  | The overhead is one-time. The drift cost is permanent. Split. |
## Evidence of compliance
Before considering an AI-integration change complete, produce:
- Confirmation the call routes through the Render proxy (network log or code reference).
- Confirmation the anti-fabrication preamble is applied (system prompt log).
- The versioned prompt file path and the structured-output schema file path.
- For structured output: schema validation test with valid and invalid responses.
- For "insufficient information" paths: a test where the model is given deliberately thin input and the response surfaces as an explicit state, not silently null.
- For PHI-touching prompts: a test that no patient name, address, or identifier appears in the forwarded prompt body.
