// lib/widgets/recall_assistant/recall_assistant_overlay.dart
//
// Root overlay for the recall assistant. Mounted in MaterialApp.builder so
// it floats above every screen. Owns:
//   • the dim backdrop (rgba(0,0,0,0.35) — NO BackdropFilter, Cue invariant)
//   • bottom-right card positioning (LayoutBuilder, never MediaQuery)
//   • the persistent "Ask Cue" button (hidden when suppressed or open)
//   • global Cmd/Ctrl+K + Escape interception via HardwareKeyboard
//   • app-wide activity pings (pointer) feeding the idle clock
//
// SEAM: depends on the controller + card + button only. No Supabase.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'recall_assistant_button.dart';
import 'recall_assistant_card.dart';
import 'recall_assistant_controller.dart';

class RecallAssistantOverlay extends StatefulWidget {
  final RecallAssistantController controller;
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  const RecallAssistantOverlay({
    super.key,
    required this.controller,
    required this.navigatorKey,
    required this.child,
  });

  @override
  State<RecallAssistantOverlay> createState() => _RecallAssistantOverlayState();
}

class _RecallAssistantOverlayState extends State<RecallAssistantOverlay> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  // Global key intercept. Runs before the focus-based Shortcuts system, so
  // returning true here PREVENTS app_layout's CallbackShortcuts ⌘K (which
  // opens the Cue Study full-activity popup) from also firing — recall wins
  // Cmd+K. We only consume when not suppressed (auth screens fall through).
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final c = widget.controller;
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    final meta = pressed.contains(LogicalKeyboardKey.metaLeft) ||
        pressed.contains(LogicalKeyboardKey.metaRight) ||
        pressed.contains(LogicalKeyboardKey.meta);
    final ctrl = pressed.contains(LogicalKeyboardKey.controlLeft) ||
        pressed.contains(LogicalKeyboardKey.controlRight) ||
        pressed.contains(LogicalKeyboardKey.control);
    final shift = pressed.contains(LogicalKeyboardKey.shiftLeft) ||
        pressed.contains(LogicalKeyboardKey.shiftRight) ||
        pressed.contains(LogicalKeyboardKey.shift);

    // Plain Cmd/Ctrl+K → recall. Cmd/Ctrl+SHIFT+K is Cue Study's shortcut
    // (app_layout::_CueHoldShortcuts); the `!shift` guard lets it pass
    // through instead of being swallowed by this global handler.
    if (event.logicalKey == LogicalKeyboardKey.keyK && (meta || ctrl) && !shift) {
      if (c.suppressed) return false;
      c.toggle();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape && c.isOpen) {
      c.close();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => c.markActivity(),
      child: AnimatedBuilder(
        animation: c,
        builder: (context, _) {
          return Stack(
            children: [
              widget.child,

              // Persistent "Ask Cue" button — hidden when suppressed or open.
              if (!c.suppressed && !c.isOpen)
                Positioned(
                  right: 24,
                  bottom: 24,
                  child: RecallAssistantButton(onTap: c.toggle),
                ),

              // Open card + dim backdrop.
              if (c.isOpen) ..._openCard(c),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _openCard(RecallAssistantController c) {
    return [
      // Dim backdrop — tap to close. NO BackdropFilter.
      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: c.close,
          child: const ColoredBox(color: Color(0x59000000)), // black @ 0.35
        ),
      ),
      // Card, bottom-right, sized via LayoutBuilder (never MediaQuery).
      Positioned(
        right: 24,
        bottom: 24,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxW = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : 560.0;
            final maxH = constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : 520.0;
            final cardWidth = maxW - 48 < 560.0 ? maxW - 48 : 560.0;
            final cardMaxHeight = maxH - 48 < 520.0 ? maxH - 48 : 520.0;
            return ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: cardWidth.clamp(280.0, 560.0),
                maxHeight: cardMaxHeight.clamp(160.0, 520.0),
              ),
              child: RecallAssistantCard(
                controller: c,
                navigatorKey: widget.navigatorKey,
              ),
            );
          },
        ),
      ),
    ];
  }
}
