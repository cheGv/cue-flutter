// lib/widgets/profile/active_stgs_pillar.dart
//
// Phase 5.3 Round B — Active STGs hero pillar. Reads the resolved
// active short-term goals + sessions list and renders Cue's "what's
// the focus right now" summary.
//
// Whisper categories — Pattern 6 lock, factual or interrogative ONLY:
//   • "A step here was last touched N sessions ago." — when the
//     oldest-touched active STG hasn't seen a session since its
//     last update (sessions count, not days).
//   • "No real-world impact captured yet." — when sessions exist but
//     SOAP S content is thin (no narrative beyond short markers).
//   • null — no signal qualifies. Most pillars stay quiet most days.
//
// FORBIDDEN: "ready to step up", "approaching mastery", "should
// progress", "trending toward", "close to" — these are projections
// and break Cue's meta-rule. If you edit this file, re-read the
// whisper strings and confirm every one names what IS, not what's
// expected to happen.

import 'package:flutter/material.dart';

import '../../theme/cue_color_scheme.dart';
import '_hero_pillar_frame.dart';

class ActiveStgsPillar extends StatelessWidget {
  /// Active short-term goals (status='active' or null/empty). Already
  /// filtered by Profile.
  final List<Map<String, dynamic>> activeStgs;

  /// Newest-first sessions list, used to compute the whisper signal.
  final List<Map<String, dynamic>> sessions;

  /// Client's display name — used in the headline copy.
  final String clientName;

  /// Optional tap handler — opens CuePopup with STG-scoped intent.
  /// Round B passes Profile's _toggleCuePopup; Round G refines to a
  /// real intent.
  final VoidCallback? onAskCue;

  const ActiveStgsPillar({
    super.key,
    required this.activeStgs,
    required this.sessions,
    required this.clientName,
    this.onAskCue,
  });

  @override
  Widget build(BuildContext context) {
    final cue = CueColorsResolved.of(context);
    if (activeStgs.isEmpty) {
      return HeroPillarFrame(
        icon:    Icons.flag_outlined,
        accent:  cue.olive,
        tag:     'Active steps',
        body:    _emptyState(cue),
        footer:  onAskCue == null
            ? null
            : _AskCuePill(label: 'Build plan with Cue →', onTap: onAskCue!, accent: cue.olive),
      );
    }

    final headline = _buildHeadline();
    final whisper  = _buildWhisper();

    return HeroPillarFrame(
      icon:    Icons.flag_outlined,
      accent:  cue.olive,
      tag:     'Active steps',
      count:   activeStgs.length.toString(),
      body:    _body(cue, headline),
      whisper: whisper,
    );
  }

  // ── Body composers ──────────────────────────────────────────────

  Widget _emptyState(CueColorsResolved cue) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'No active steps yet.',
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
          'Build a plan with Cue to start tracking ${_firstName()}\'s '
          'short-term steps.',
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

  Widget _body(CueColorsResolved cue, String headline) {
    final top = _topStgs();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Headline — Inter 15 / 500, NOT italic per spec.
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
        const SizedBox(height: 10),
        // Top 1–2 active goal summaries — Inter 13 / 400.
        for (final stg in top) ...[
          _stgRow(cue, stg),
          if (stg != top.last) const SizedBox(height: 6),
        ],
      ],
    );
  }

  Widget _stgRow(CueColorsResolved cue, Map<String, dynamic> stg) {
    final text   = _stgText(stg);
    final domain = _stgDomain(stg);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 5,
          height: 5,
          margin: const EdgeInsets.only(top: 6),
          decoration: BoxDecoration(
            color: cue.olive,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: const ['system-ui', 'sans-serif'],
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  height: 1.45,
                  color: cue.textBody,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (domain.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    domain.toUpperCase(),
                    style: TextStyle(
                      fontFamily: 'JetBrains Mono',
                      fontFamilyFallback: const ['monospace'],
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 9 * 0.16,
                      color: cue.textMuted,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Heuristics ──────────────────────────────────────────────────

  /// Top 1–2 STGs by most-recently-touched (updated_at).
  List<Map<String, dynamic>> _topStgs() {
    final sorted = [...activeStgs];
    sorted.sort((a, b) {
      final ad = DateTime.tryParse((a['updated_at'] as String?) ?? '');
      final bd = DateTime.tryParse((b['updated_at'] as String?) ?? '');
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return bd.compareTo(ad);
    });
    return sorted.take(2).toList();
  }

  String _buildHeadline() {
    if (activeStgs.isEmpty) {
      return 'No active steps yet.';
    }
    if (activeStgs.length == 1) {
      final text = _stgText(activeStgs.first);
      final short = text.length > 70 ? '${text.substring(0, 67)}…' : text;
      return short.isEmpty ? 'One active step in motion.' : short;
    }
    final domains = activeStgs
        .map((s) => _stgDomain(s))
        .where((d) => d.isNotEmpty)
        .toSet();
    final n = activeStgs.length;
    if (domains.length == 1) {
      return 'Working on $n steps in ${domains.first.toLowerCase()}.';
    }
    if (domains.length > 1) {
      return 'Working on $n steps across ${domains.length} domains.';
    }
    return 'Working on $n active steps.';
  }

  /// Whisper — factual or interrogative ONLY. Returns null when no
  /// signal qualifies (the design encourages quiet — most pillars
  /// will have no whisper).
  String? _buildWhisper() {
    if (sessions.isEmpty) return null;
    if (activeStgs.isEmpty) return null;

    // Count sessions since each active STG's last update; pick the
    // oldest-touched STG and report its session-count gap.
    int? maxSessionsSinceUpdate;
    for (final stg in activeStgs) {
      final upd = stg['updated_at'] as String?;
      final dt  = upd != null ? DateTime.tryParse(upd) : null;
      if (dt == null) continue;
      int count = 0;
      for (final s in sessions) {
        final sd = s['date'] as String?;
        final sdt = sd != null ? DateTime.tryParse(sd) : null;
        if (sdt != null && sdt.isAfter(dt)) count++;
      }
      if (maxSessionsSinceUpdate == null ||
          count > maxSessionsSinceUpdate) {
        maxSessionsSinceUpdate = count;
      }
    }

    if (maxSessionsSinceUpdate != null && maxSessionsSinceUpdate > 4) {
      return 'A step here was last touched '
             '$maxSessionsSinceUpdate sessions ago.';
    }

    // "No real-world impact captured yet" — heuristic: every session's
    // SOAP S (subjective) field is shorter than 30 chars. Roughly
    // "thin narrative" detection.
    final recent = sessions.take(3).toList();
    if (recent.length >= 3) {
      final allThin = recent.every((s) {
        final soap = (s['soap_note'] as String?) ?? '';
        final notes = (s['notes'] as String?) ?? '';
        final body = (soap.isNotEmpty ? soap : notes).trim();
        return body.length < 30;
      });
      if (allThin) {
        return 'No real-world impact captured yet.';
      }
    }

    return null;
  }

  // ── Field accessors ─────────────────────────────────────────────

  String _stgText(Map<String, dynamic> stg) {
    final t = (stg['specific'] as String?) ??
              (stg['goal_text'] as String?) ??
              (stg['target_behavior'] as String?) ??
              '';
    return t.trim();
  }

  String _stgDomain(Map<String, dynamic> stg) {
    final d = (stg['domain'] as String?) ?? (stg['category'] as String?) ?? '';
    return d.trim();
  }

  String _firstName() {
    final parts = clientName.trim().split(RegExp(r'\s+'));
    return parts.isEmpty ? clientName : parts.first;
  }
}

class _AskCuePill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Color accent;
  const _AskCuePill({
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
