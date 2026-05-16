// lib/widgets/cue_hold/cue_hold.dart
//
// Phase 4.1.3 — main Cue Hold widget. Watches [cueHoldController] and
// renders the surface appropriate to the current state.
//
// State → surface mapping:
//   idle / compact / thinking / listening  →  CueHoldPill
//   whisper                                 →  CueHoldWhisper
//   expanded                                →  CueHoldExpanded
//   multi                                   →  CueHoldMulti
//   fullActivity                            →  routes to existing CuePopup
//                                              (rendered by the host screen,
//                                              not by this widget)
//
// The host (AppLayout) places this widget as a Positioned child at the
// top-right of every screen's outer Stack. AnimatedSize handles the
// pill-to-expanded-surface morph; AnimatedSwitcher cross-fades between
// pill-shaped states.

import 'package:flutter/material.dart';

import 'cue_hold_expanded.dart';
import 'cue_hold_multi.dart';
import 'cue_hold_pill.dart';
import 'cue_hold_state.dart';
import 'cue_hold_whisper.dart';

class CueHold extends StatelessWidget {
  /// When true, the layout switches to mobile-friendly width (used by
  /// the EXPANDED chat surface). Caller (AppLayout) computes this from
  /// LayoutBuilder.
  final bool isMobile;

  const CueHold({super.key, this.isMobile = false});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: cueHoldController,
      builder: (context, _) {
        final c = cueHoldController;
        // Phase 4.1.4 — the Hold widget itself only renders pill-shape
        // states (and MULTI/WHISPER). EXPANDED chat and FULL ACTIVITY
        // are rendered by AppLayout as separate Positioned overlays so
        // the topbar's three-zone layout stays intact. While the Hold
        // is in expanded / fullActivity, render the previous pill state
        // here as a visual anchor — except when a query is in flight
        // (thinkingInExpanded), in which case the pill flips to THINKING
        // so the SLP sees the in-flight indicator both at the top AND
        // inside the chat body.
        if (c.state == CueHoldState.fullActivity ||
            c.state == CueHoldState.expanded) {
          if (c.state == CueHoldState.expanded && c.thinkingInExpanded) {
            return _renderState(context, CueHoldState.thinking, c);
          }
          return _renderState(
            context,
            c.previousState ?? CueHoldState.idle,
            c,
          );
        }
        return _renderState(context, c.state, c);
      },
    );
  }

  Widget _renderState(
    BuildContext context,
    CueHoldState state,
    CueHoldController c,
  ) {
    switch (state) {
      case CueHoldState.expanded:
        return CueHoldExpanded(controller: c, isMobile: isMobile);
      case CueHoldState.whisper:
        return CueHoldWhisper(
          text: c.whisperText,
          onTap: () => _onPillTap(c),
          onLongPress: c.toFullActivity,
          onMicTap: () => _onMicTap(context),
        );
      case CueHoldState.multi:
        return CueHoldMulti(
          primary: c.previousState ?? CueHoldState.idle,
          primaryLabel: c.contextLabel,
          secondary: c.secondaryState ?? CueHoldState.thinking,
          secondaryLabel: c.secondaryLabel,
          onTapPrimary: () => _onPillTap(c),
          onTapSecondary: () => _onPillTap(c),
          onLongPressAny: c.toFullActivity,
          onMicTapPrimary: () => _onMicTap(context),
        );
      case CueHoldState.idle:
      case CueHoldState.compact:
      case CueHoldState.thinking:
      case CueHoldState.listening:
      default:
        return CueHoldPill(
          state: state,
          label: c.contextLabel,
          onTap: () => _onPillTap(c),
          onLongPress: c.toFullActivity,
          onMicTap: () => _onMicTap(context),
        );
    }
  }

  void _onPillTap(CueHoldController c) {
    // Phase 4.1.5 B — iOS Dynamic Island tap-to-toggle. Tapping the
    // pill while the chat is already expanded collapses it back to the
    // prior pill state (same path as the minimize button).
    if (c.state == CueHoldState.expanded) {
      c.minimizeExpanded();
      return;
    }
    final clientId = c.clientId;
    final clientName = c.clientName;
    if (clientId.isEmpty) {
      // No client context yet — open client-less expanded chat anyway,
      // using empty anchors.
      c.expand(clientId: '', clientName: '');
      return;
    }
    c.expand(
      clientId: clientId,
      clientName: clientName,
      stgId: c.stgAnchorId,
      ltgId: c.ltgAnchorId,
    );
  }

  /// Phase 4.1.4 — mic icon is visually present but not wired to real
  /// voice capture until Phase 4.1.5. Tap shows a SnackBar instead of
  /// transitioning to LISTENING. The LISTENING state is still reachable
  /// via the dev shortcut ⌘⇧L for visual testing.
  void _onMicTap(BuildContext context) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Voice capture — coming in Phase 4.1.5'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}
