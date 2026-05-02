# Phase 4.A — Assessment as Engagement Mode
## Architectural Decisions Record (pre-spec)

**Created:** 2026-05-02 (during Phase 4.0 V1 build)
**Status:** Decisions locked; full master spec deferred until Phase 4.0 V1 completes.

## Core architectural premise

Assessment is a parallel engagement type to therapy, not a phase within therapy.

A child arrives via referral for a one-time comprehensive evaluation. Parents pay ~₹2,000-3,000. The deliverable is a comprehensive assessment report. The family decides post-report whether to continue with this SLP, with another SLP, or not pursue therapy.

Assessment is the SLP's front door for new clients. Cue's job is to make the SLP's assessment-day labor radically easier and the resulting report dramatically better than what she could produce alone in the time available.

## Locked decisions

### Engagement architecture
- Same `clients` table with `engagement_type` flag: `assessment_only` vs `therapy`.
- Conversion from assessment to therapy is a state change on the existing client record.
- On conversion, the assessment report stays as a historical artifact attached to the client. Cue produces the therapy starting kit at conversion: goals, structured baseline, recommendations seed.
- Sidebar gets a new "Assessing" nav item alongside Clients. Today screen mixes both engagement types by time of day.

### Assessment workflow
1. Referral arrives → SLP creates assessment case
2. Standard intake (Layer 01 as built) — no separate lighter form
3. Single visit usually (60-90 min); 1-3 visits possible
4. Parent is the primary information source — case history conversation is the largest single capture channel
5. SLP uses domain-shaped capture surfaces during the visit
6. SLP runs named instruments (REELS, CELF, etc.) within domain surfaces — Cue tracks instrument metadata, not copyrighted scoring
7. Diagnostic synthesis surface: Cue presents captured evidence, SLP makes the diagnostic call
8. Cue composes world-class assessment report
9. SLP edits, attests, exports/shares with family
10. Engagement closes OR converts to therapy

### Capture surfaces
- Domain-shaped, not battery-locked. Domains: speech (articulation, phonology, motor speech, fluency, voice, resonance), receptive language, expressive language, pragmatic/social, cognitive/pre-academic, oromotor, hearing screening notes, feeding (if relevant)
- Each domain surface has named-instrument hooks (instrument-menu pattern per §13.9) plus free-form observation capture
- Parent interview is centrally placed and significantly extended from the therapy Layer 03 version
- Speech sample / live entry surface from Phase 4.0.4 reused within the speech domain

### Diagnostic synthesis
- V1: Evidence aggregation only. Cue surfaces all captured data structured for diagnostic reasoning. SLP types/selects diagnosis. Cue does NOT suggest diagnoses.
- V2+: Cue may surface diagnostic considerations as a clinical-decision-support feature. Requires validation work and probably CDSCO Class B SaMD work. Out of V1 scope.

### The report
- The report is the centerpiece of the assessment engagement, not a side artifact
- Editorial register at highest fidelity — Playfair italic, sentence case, affirmative language, no pronoun defaults
- Structure leads with the child as a person (humane framing), clinical findings follow
- Recommendations are specific and actionable, not generic
- Diagnostic statement is precise and humble (ICD-11 codes where applicable, severity grounded in captured measurements)
- Includes a "what this means" section in plainer language for the family
- Dual function: clinical document AND family-facing document
- Cue's job is to enable the SLP to produce this in 30 minutes instead of 3 hours

### Audio/video capture
- V1: Notes only. No audio, no video.
- V1.x: Audio recording with playback-assisted re-counting (consent capture, browser MediaRecorder API, Supabase Storage)
- V1.y: Whisper transcription of recorded audio for searchable assessment record
- V2+: Possibly video, but storage and bandwidth costs likely don't justify clinical value-add

### Parent communication
- V1: No direct parent messaging from Cue. SLP shares the report manually.
- Future phase (Phase 4.B or later): WhatsApp Business API integration for SLP-authorized templated messages to parents. Requires consent capture, message audit, message templates with SLP review/approval, "Cue on behalf of [SLP/clinic]" framing.
- Parent contact infrastructure (structured contact data, consent state) is groundwork that lands in V1 even though messaging itself doesn't.

### Conversion to therapy
- Assessment data carries forward as the new therapy client's baseline (read directly from assessment captures, no re-entry)
- Diagnosis becomes the client's primary diagnosis
- Recommendations become the seed for goal generation
- Generate Plan reads from assessment captures + recommendations to produce initial therapy goals
- Assessment report stays attached as historical artifact in the converted client's chart

### Client space-file architecture
- The unified client chart needs reshaping to cleanly hold both layers when conversion happens:
  - Historical layer: the original assessment captures + the assessment report (read-only artifact)
  - Live layer: ongoing therapy state (sessions, goals, progress)
- Architectural cleanup deferred to dedicated session within Phase 4.A or Phase 4.B

## Out of scope for Phase 4.A V1

- Audio/video capture (V1.x)
- Parent messaging from Cue (separate phase)
- Diagnostic suggestion by Cue (V2+)
- Multi-population assessment (V1 ships developmental stuttering domain coverage; other populations follow)
- Assessment report templating customization (V1 ships one report shape; clinic-specific templates later)
- Insurance/medico-legal documentation features

## Sequencing

Phase 4.A waits its turn. Phase 4.0 V1 (developmental stuttering therapy) completes first:
- Currently in flight: 4.0.7 (Layer 04 pre-therapy planning)
- Then: 4.0.8 Layer 05, 4.0.9 Layer 06, 4.0.10 progress report composer, 4.0.11 polish, 4.0.12 V1 close
- Then: Phase 4.A master spec written, Phase 4.A V1 build begins

## Strategic framing

Assessment is the wedge. Many SLPs first encounter Cue when they need to produce one assessment report. If Cue makes that one report better than they could write alone, they will use Cue for everything else they do. Phase 4.A is therefore not a "feature add" — it's the front door of Cue's clinical product story.
