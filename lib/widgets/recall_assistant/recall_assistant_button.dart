// lib/widgets/recall_assistant/recall_assistant_button.dart
//
// Persistent "Ask Cue" affordance, fixed bottom-right. Shows the keyboard
// hint (⌘K on macOS, Ctrl K elsewhere). Tap toggles the recall card.
// Pure presentation — no Supabase.

import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class RecallAssistantButton extends StatelessWidget {
  final VoidCallback onTap;
  const RecallAssistantButton({super.key, required this.onTap});

  static const Color _bg = Color(0xFF242422);
  static const Color _border = Color(0x1FFFFFFF);
  static const Color _text = Color(0xE6FFFFFF);
  static const Color _hint = Color(0x66FFFFFF);
  static const Color _amber = Color(0xFFF5C778);

  String get _shortcutHint =>
      defaultTargetPlatform == TargetPlatform.macOS ? '⌘K' : 'Ctrl K';

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _bg,
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      elevation: 4,
      shadowColor: const Color(0x55000000),
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: _border, width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.auto_awesome, size: 15, color: _amber),
              const SizedBox(width: 8),
              Text(
                'Ask Cue',
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _text,
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0x14FFFFFF),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  _shortcutHint,
                  style: GoogleFonts.dmSans(fontSize: 11, color: _hint),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
