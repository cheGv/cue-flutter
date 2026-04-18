# Narrator Edge Function

- **Runtime:** Deno (Supabase Edge Functions)
- **Purpose:** Receives raw audio (webm), transcribes via OpenAI Whisper, structures into SOAP note via GPT-4o-mini
- **Auth:** JWT verification disabled (app handles auth via Supabase client)
- **Required secrets:** OPENAI_API_KEY (set in Supabase dashboard → Edge Functions → Secrets)
- **Deploy:** supabase functions deploy narrator --no-verify-jwt

## Architecture
Audio → Flutter Web → Supabase Edge Function → Whisper (STT) → GPT-4o-mini (structure) → JSON response
