Phase B Chart Redesign — Complete

Locked design philosophy: contextual collaborator without voice.
The chart anticipates clinical state and arranges accordingly. Never speaks.
Voice lives only in invoked recall surface (Cmd+K / Ctrl+K).

Locked visual register: cream paper light + matching dark.
Reading Room typography (Playfair italic editorial register + sans for density).
Sienna primary. Semantic colors (progress/plan_revised/holding) encode session outcome and appear only where outcome is shown — trajectory ticks, trajectory legend, and session-row outcome dots. They appear nowhere else in Cue.

Locked language discipline: no setback / regression / failure / deficit anywhere in Cue's user-facing strings, AI-generated content, or system prompts. The third session outcome is "holding." Encoded server-side in proxy system prompts and Dart-side in enums, repositories, and widgets. This applies to all future surfaces.

Locked architecture:
- Goal spine on top — LTG anchor → STGs with one in focus → evidence ladder beneath in-focus STG (roman-numeral tier chips, author-year citations, external links)
- Sparkline inside in-focus STG card scoped to that STG's micro-trajectory
- Trajectory + session-history paired layer below — trajectory ticks (one row per domain) above expandable session rows with outcome dots; ticks scroll-anchor and expand the matching session
- Substrate as adjacent reference, accessible via link (mount location open for refinement)
- Next Session intent from each session seeds the Plan today's session chip via sessions.next_session_focus → client_chart_state.last_next_session_focus → SessionPlanningScreen seedFocus
- Recall scoped to client via recallAssistantController.setFocusedClient pattern; pattern is extensible to other scopes (goal, session) for future surfaces
- Action chip resolver derives primary chip from client_chart_state — Author LTG when ltg_count is 0, Document last session when undocumented_session_count > 0, else Plan today's session
- Planned/draft sessions filtered from chart counts and reads via client_chart_state view filter and SessionsRepository.loadForClient(includePlanned: false default)

Open items deferred:
- Proxy deploy (user's gate) — git -C C:\dev\cue\proxy push origin main from local commit bf2cd4b
- Schedule integration (Phase C feature, requires appointments table)
- ~15 inline .from('sessions') call sites (opportunistic cleanup as surfaces are touched)
- 18 pre-existing lints in untouched files (separate sweep)
- Two-week substrate lived-usage period (Phase A discipline still owed)

Reference visuals: chat history May 22–23, 2026.
Reference code: lib/widgets/chart/, lib/screens/client_profile_screen.dart, lib/screens/session_planning_screen.dart, lib/screens/client_sessions_screen.dart, lib/services/chart_narrator_service.dart, lib/services/session_headline_service.dart, lib/repositories/client_chart_state_repository.dart, lib/repositories/citations_repository.dart, lib/repositories/stg_metrics_repository.dart, lib/utils/chart_navigation.dart, lib/utils/stg_numbering.dart, lib/utils/sparkline_readout.dart.
Reference proxy: C:\dev\cue\proxy\server.js commit bf2cd4b (POST /chart-narrator, POST /session-headline; server-side system prompts).
Reference migrations applied to sandbox uuqhusmgoiaxdvtgbmwh: add_session_outcome, create_stg_session_metrics, create_citations, create_client_chart_state_view, add_sessions_planned_focus, filter_planned_from_chart_state, add_sessions_ai_headline.
