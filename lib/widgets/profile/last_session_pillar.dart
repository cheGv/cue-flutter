// lib/widgets/profile/last_session_pillar.dart
//
// Phase 5.3 Round B — Last Session hero pillar. Reads the most-recent
// session record and surfaces its SOAP S content + documentation
// state.
//
// Whisper categories — factual only:
//   • "Documented · attested · ready to share." — when the session
//     is attested (SLP signed off).
//   • "Documentation pending." — when the session has no SOAP body
//     captured yet.
//   • null — neutral state, no whisper.

import 'dart:convert';
import 'package:flutter/material.dart';

import '../../theme/cue_color_scheme.dart';
import '_hero_pillar_frame.dart';

class LastSessionPillar extends StatelessWidget {
  /// Newest-first sessions list. The pillar uses sessions.first when
  /// present.
  final List<Map<String, dynamic>> sessions;

  /// Client's display name — used in the empty-state copy.
  final String clientName;

  /// Optional tap handler — opens CuePopup with last-session-scoped
  /// intent. Round B passes Profile's _toggleCuePopup.
  final VoidCallback? onAskCue;

  const LastSessionPillar({
    super.key,
    required this.sessions,
    required this.clientName,
    this.onAskCue,
  });

  @override
  Widget build(BuildContext context) {
    final cue = CueColorsResolved.of(context);
    if (sessions.isEmpty) {
      return HeroPillarFrame(
        icon:    Icons.history_outlined,
        accent:  cue.blue,
        tag:     'Last session',
        body:    _emptyState(cue),
        footer:  onAskCue == null
            ? null
            : _StartPill(
                label:  'Start first session →',
                onTap:  onAskCue!,
                accent: cue.blue,
              ),
      );
    }

    final last = sessions.first;
    final headline    = _buildHeadline(last);
    final soapQuote   = _extractSoapS(last);
    final whisper     = _attestationWhisper(last);
    final sessionNum  = _sessionNumber(last);
    final dateLabel   = _formatDate(last);

    return HeroPillarFrame(
      icon:    Icons.history_outlined,
      accent:  cue.blue,
      tag:     'Last session',
      count:   sessionNum != null ? '#$sessionNum' : null,
      body:    _body(cue, headline, soapQuote, dateLabel),
      whisper: whisper,
    );
  }

  Widget _emptyState(CueColorsResolved cue) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'No sessions yet.',
          style: TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: const ['system-ui', 'sans-serif'],
            fontSize: 15,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.16,
            color: cue.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'When you log your first session with ${_firstName()}, '
          'Cue surfaces the moments worth remembering here.',
          style: TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: const ['system-ui', 'sans-serif'],
            fontSize: 13,
            height: 1.5,
            color: cue.textBody,
          ),
        ),
      ],
    );
  }

  Widget _body(
    CueColorsResolved cue,
    String headline,
    String? soapQuote,
    String? dateLabel,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          headline,
          style: TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: const ['system-ui', 'sans-serif'],
            fontSize: 15,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.16,
            height: 1.35,
            color: cue.textPrimary,
          ),
        ),
        if (dateLabel != null) ...[
          const SizedBox(height: 4),
          Text(
            dateLabel.toUpperCase(),
            style: TextStyle(
              fontFamily: 'JetBrains Mono',
              fontFamilyFallback: const ['monospace'],
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 9.5 * 0.16,
              color: cue.textMuted,
            ),
          ),
        ],
        if (soapQuote != null) ...[
          const SizedBox(height: 12),
          // SOAP S quote — Iowan italic 13.5 for the "Cue surfacing
          // the SLP's own words" register (Pattern 2 — quoted SLP
          // material renders italic + cited).
          Text(
            '"$soapQuote"',
            style: TextStyle(
              fontFamily: 'Iowan Old Style',
              fontFamilyFallback: const ['Georgia', 'Charter', 'serif'],
              fontSize: 13.5,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w400,
              letterSpacing: -0.07,
              height: 1.45,
              color: cue.textBody,
            ),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }

  // ── Heuristics ──────────────────────────────────────────────────

  String _buildHeadline(Map<String, dynamic> session) {
    final sessionNum = _sessionNumber(session);
    final hasNote = _hasNote(session);
    if (sessionNum == null) {
      return hasNote
          ? 'Last session notes captured.'
          : 'Last session — documentation pending.';
    }
    return hasNote
        ? 'Session $sessionNum notes captured.'
        : 'Session $sessionNum — documentation pending.';
  }

  String? _extractSoapS(Map<String, dynamic> s) {
    final raw = s['soap_note'] as String?;
    if (raw != null && raw.isNotEmpty) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        final subjective = (map['subjective'] as String?) ??
                           (map['S'] as String?) ??
                           (map['s'] as String?) ??
                           '';
        final trimmed = subjective.trim();
        if (trimmed.isNotEmpty) {
          return trimmed.length > 180
              ? '${trimmed.substring(0, 177)}…'
              : trimmed;
        }
      } catch (_) {/* fall through */}
    }
    final notes = (s['notes'] as String?)?.trim();
    if (notes != null && notes.isNotEmpty) {
      return notes.length > 180 ? '${notes.substring(0, 177)}…' : notes;
    }
    return null;
  }

  String? _attestationWhisper(Map<String, dynamic> session) {
    final attested = session['clinician_attested'] == true ||
                     (session['attested_at'] as String?)?.isNotEmpty == true;
    final hasNote = _hasNote(session);
    if (attested) {
      return 'Documented · attested · ready to share.';
    }
    if (!hasNote) {
      return 'Documentation pending for this session.';
    }
    return null;
  }

  int? _sessionNumber(Map<String, dynamic> s) {
    final n = s['session_number'] ?? s['visit_number'];
    if (n is int) return n;
    if (n is num) return n.toInt();
    if (n is String) return int.tryParse(n);
    return null;
  }

  String? _formatDate(Map<String, dynamic> session) {
    final dateStr = session['date'] as String?;
    final dt = dateStr != null ? DateTime.tryParse(dateStr) : null;
    if (dt == null) return null;
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final days = DateTime.now().difference(dt).inDays;
    final relative = days == 0
        ? 'today'
        : days == 1
            ? 'yesterday'
            : days < 7
                ? '$days days ago'
                : '${dt.day} ${months[dt.month]}';
    return relative;
  }

  bool _hasNote(Map<String, dynamic> s) {
    final soap = (s['soap_note'] as String?)?.trim();
    if (soap != null && soap.isNotEmpty) return true;
    final notes = (s['notes'] as String?)?.trim();
    return notes != null && notes.isNotEmpty;
  }

  String _firstName() {
    final parts = clientName.trim().split(RegExp(r'\s+'));
    return parts.isEmpty ? clientName : parts.first;
  }
}

class _StartPill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Color accent;
  const _StartPill({
    required this.label,
    required this.onTap,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final cue = CueColorsResolved.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: cue.isDark ? 0.15 : 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: accent.withValues(alpha: 0.45),
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: const ['system-ui', 'sans-serif'],
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: accent,
          ),
        ),
      ),
    );
  }
}
