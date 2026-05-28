# Skill: flutter-layout
> **Flutter repo.** Layout, responsiveness, and the structural UI invariants for `C:\projects\cue`.
## When to use
Triggered by any width-responsive UI, layout files (`app_layout.dart`, scaffolds, sidebars), new screens, the goal-ladder / chart surfaces, or responsive breakpoint logic.
## The invariants
### F1. LayoutBuilder, never MediaQuery for width-responsive UI
`MediaQuery.of(context).size.width` reflects the window, not the widget's available space. With a persistent sidebar, MediaQuery lies. Use `LayoutBuilder` and switch on `constraints.maxWidth`. MediaQuery is acceptable only for device pixel ratio, text scale, system padding, and `disableAnimations`. Seeing `MediaQuery.of(context).size` in a layout decision is a bug.
### F2. Desktop-first, persistent sidebar
Cue is a clinician tool; primary form factor is desktop browser with a persistent sidebar via `app_layout.dart`. Mobile-web is functional but secondary. The five sidebar entries (Today, Clients, Practice, Narrator, Settings) are siblings, not parents/children — each answers a different mental model. **Today is protected:** highest-frequency surface, single-purpose (greeting, today's sessions, week pulse), never enriched with cross-cutting features.
### F3. Width caps are deliberate and must not be unified
- AppLayout content cap: **1040px** (Today, Clients, Assessing, Inbox, Settings).
- Chart screen: its own system — outer **1024** + per-sliver **680**.
- Do NOT unify these. The chart's prose-dense column needs the narrower inner cap. Profile two-column workspace at ≥1024: chart-side left, AskCuePanel persistent-right at 460px.
### F4. Route discipline
- Top-level routes (Today, Clients, Assessing, Inbox, Settings) suppress the back arrow (`automaticallyImplyLeading: false`). Sub-routes (chart, session detail, reasoning) keep it.
- Always reference `AppRoutes` constants; never hardcode path strings inline. (`AppRoutes.inbox` is currently a `'/today'` fallback — flip in one line when Inbox ships.)
### F5. Motion gates through kReduceMotion
All motion routes through `kReduceMotion(context)` in `lib/animation/cue_motion.dart`. `MediaQuery.disableAnimations = true` snaps entrances to final state, drops hover transforms (keeps color shifts), forces `glanceAngle = 0`. Motion lives where the user benefits, not on every interaction — navigation stays default `MaterialPageRoute`; no custom theatre on page transitions. The canonical compose pattern is in `today_brief_card.dart`. Detailed motion spec lives in the design spine (see `design-system`).
### F6. Auth-null guard
Any widget reading `user` handles the null case explicitly — never crashes. Cue has a known gap here (no `onAuthStateChange` subscription; mid-session token expiry silently breaks until reload) tracked in the reliability backlog. Until that lands, guard every auth read.
### F7. The STG spine principle
STGs are the **spine** of the patient detail view; everything else (notes, Narrator, AAC state) hangs off them. Critical clinical info lives in the same spatial location every time — like an evaluation bar or an altimeter. Don't scatter it.
## Note on the proxy boundary (cross-repo)
Flutter calls the Anthropic proxy via plain `http.post` to Render — **NOT** `functions.invoke()` (resolved JWT ES256/HS256 mismatch; reintroducing `functions.invoke()` reopens the bug). Proxy-side rules live in the proxy repo's `ai-integration` / `prompt-discipline`; this is the Flutter-side reminder.
## Anti-rationalizations
| Excuse | Counter |
|---|---|
| "MediaQuery is one line shorter." | It lies when the sidebar is open. LayoutBuilder. |
| "I'll unify the width caps, cleaner." | The chart's inner 680 cap is deliberate for prose density. Don't unify. |
| "functions.invoke() is the standard Supabase way." | It reopens the JWT mismatch. Plain http.post to Render. |
| "Today could use a little search box." | Today is protected and single-purpose. Search lives in Practice. |
| "I'll add the auth-null guard later." | Later is a crash mid-session. Guard now. |
## Evidence of compliance
- Zero `MediaQuery.of(context).size` in width-responsive logic.
- Visual check at 1024 / 1280 / 1440 px.
- Routes via `AppRoutes` constants; top-level routes suppress back arrow.
- New auth-reading widgets handle null explicitly.
