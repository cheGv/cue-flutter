// lib/widgets/cue_hold.dart
//
// Phase 4.1.3 — this file is now a re-export shim for the new modular
// Cue Hold (see lib/widgets/cue_hold/). Existing import sites
// (`import '../widgets/cue_hold.dart'`) continue to resolve to the
// `CueHold` widget; the controller and sub-widgets are also exported
// for callers that need to drive state.

export 'cue_hold/cue_hold.dart' show CueHold;
export 'cue_hold/cue_hold_state.dart'
    show CueHoldController, CueHoldState, CueHoldChatMessage, cueHoldController;
