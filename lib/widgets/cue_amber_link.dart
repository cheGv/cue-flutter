// lib/widgets/cue_amber_link.dart
//
// Phase 3.2 shared widget: amber inline text-link. Factored out of
// today_screen.dart so the Clients attention block and any future
// surface can use the exact same affordance.
//
// Visual register: 13px / w500 / CueColors.amber. No underline, no
// trailing arrow — Cue's voice colour does the affordance work.

import 'package:flutter/material.dart';
import '../theme/cue_theme.dart';
import '../theme/cue_typography.dart';

class CueAmberLink extends StatelessWidget {
  final String       label;
  final VoidCallback onTap;
  final FontWeight   weight;

  const CueAmberLink({
    super.key,
    required this.label,
    required this.onTap,
    this.weight = FontWeight.w500,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: CueType.custom(
          fontSize: 13,
          weight:   weight,
          color:    CueColors.amber,
        ),
      ),
    );
  }
}
