// lib/widgets/today_brief_variants.dart
//
// Phase 4.0.7.21 — design exploration. Five card variants showing the
// same SLP daily-brief case in distinct registers. Throwaway widgets;
// the chosen variant gets re-built for production in 4.0.7.21b.
//
// Tokens reused verbatim from goal_authoring_screen.dart (the existing
// parchment register) so the user is comparing across the same visual
// vocabulary as "A treatment plan, co-authored." and "LAYER 03 GOAL
// DRAFT". No new colors or fonts introduced.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ── Local tokens (mirror goal_authoring_screen.dart) ────────────────────
const Color _paper      = Color(0xFFFAF6EE);
const Color _ink        = Color(0xFF0E1C36);
const Color _inkGhost   = Color(0xFF6B7690);
const Color _teal       = Color(0xFF2A8F84);
const Color _tealSoft   = Color(0xFFD6E8E5);
const Color _amber      = Color(0xFFD68A2B);
const Color _amberSoft  = Color(0xFFF4E4C4);
const Color _line       = Color(0xFFE6DDCA);

// ── Mock data shared by all five variants ──────────────────────────────

class BriefCase {
  final String  clientName;
  final int     clientAge;
  final String  clientLens;
  final String  yesterdayDate;
  final String  yesterdayStg;
  final String  yesterdayActivity;
  final String  yesterdayResponse;
  final String  yesterdayAccuracy;
  final String  todayStg;
  final String  todayActivity;
  final String  todayTime;

  const BriefCase({
    required this.clientName,
    required this.clientAge,
    required this.clientLens,
    required this.yesterdayDate,
    required this.yesterdayStg,
    required this.yesterdayActivity,
    required this.yesterdayResponse,
    required this.yesterdayAccuracy,
    required this.todayStg,
    required this.todayActivity,
    required this.todayTime,
  });

  static BriefCase aaravMock() {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final ymd = '${yesterday.day} ${months[yesterday.month]}';
    return BriefCase(
      clientName:        'Aarav',
      clientAge:         4,
      clientLens:        'gestalt processor · autism + AAC',
      yesterdayDate:     ymd,
      yesterdayStg:
          'Aarav will activate core-vocabulary symbols on AAC system to request preferred items',
      yesterdayActivity:
          'Aided language stimulation during snack routine, mother as primary partner',
      yesterdayResponse:
          "Independent activation of 'more' symbol 3x; gestural rejection on 'finished'; dysregulated at transition out of preferred play",
      yesterdayAccuracy: '3 of 8 opportunities (38%)',
      todayStg:
          'Aarav will activate core-vocabulary symbols on AAC system to request preferred items',
      todayActivity:
          'Re-attempt aided language stimulation during snack with reduced session length and earlier transition warning',
      todayTime: '9:00 AM',
    );
  }
}

// ── Reusable text helpers ──────────────────────────────────────────────

TextStyle _eyebrow({Color color = _inkGhost, double size = 10}) =>
    GoogleFonts.syne(
      fontSize:      size,
      fontWeight:    FontWeight.w600,
      color:         color,
      letterSpacing: 1.6,
      height:        1.2,
    );

TextStyle _italicHead({Color color = _ink, double size = 26}) =>
    GoogleFonts.playfairDisplay(
      fontSize:   size,
      fontWeight: FontWeight.w400,
      fontStyle:  FontStyle.italic,
      color:      color,
      height:     1.1,
    );

TextStyle _body({Color color = _ink, double size = 14, double height = 1.6}) =>
    GoogleFonts.dmSans(
      fontSize: size,
      color:    color,
      height:   height,
    );

Widget _hairline({double opacity = 1.0}) => Container(
      height: 0.5,
      color:  _line.withValues(alpha: opacity),
    );

// ─────────────────────────────────────────────────────────────────────────
//                  VARIANT A — EDITORIAL BRIEFING
//  Literary register. Eyebrow date, italic name headline, prose body.
// ─────────────────────────────────────────────────────────────────────────
class TodayBriefVariantA extends StatelessWidget {
  final BriefCase brief;
  const TodayBriefVariantA({super.key, required this.brief});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 28),
      decoration: BoxDecoration(
        color:        _paper,
        borderRadius: BorderRadius.circular(16),
        border:       Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("YESTERDAY · ${brief.yesterdayDate.toUpperCase()}",
              style: _eyebrow()),
          const SizedBox(height: 12),
          Text(brief.clientName,
              style: _italicHead(size: 32, color: _ink)),
          const SizedBox(height: 4),
          Text(
            'age ${brief.clientAge} · ${brief.clientLens}',
            style: _body(color: _inkGhost, size: 13),
          ),
          const SizedBox(height: 20),
          _hairline(),
          const SizedBox(height: 18),
          Text(
            'Worked on ${_lower(brief.yesterdayStg)} during ${_lower(brief.yesterdayActivity)}. ${brief.yesterdayResponse} Accuracy landed at ${brief.yesterdayAccuracy}.',
            style: _body(),
          ),
          const SizedBox(height: 22),
          _hairline(opacity: 0.6),
          const SizedBox(height: 18),
          Text(
            "Today at ${brief.todayTime}, continue the same goal. ${brief.todayActivity}.",
            style: _body(color: _ink, size: 14, height: 1.65)
                .copyWith(fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  String _lower(String s) =>
      s.isEmpty ? s : '${s[0].toLowerCase()}${s.substring(1)}';
}

// ─────────────────────────────────────────────────────────────────────────
//                  VARIANT B — CLINICAL HANDOFF
//   Three labeled sections, hospital-handoff scannability.
// ─────────────────────────────────────────────────────────────────────────
class TodayBriefVariantB extends StatelessWidget {
  final BriefCase brief;
  const TodayBriefVariantB({super.key, required this.brief});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
      decoration: BoxDecoration(
        color:        Colors.white,
        borderRadius: BorderRadius.circular(14),
        border:       Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(brief.clientName.toUpperCase(),
                  style: _eyebrow(color: _ink, size: 12)),
              const SizedBox(width: 8),
              Text('· ${brief.todayTime}',
                  style: _eyebrow(color: _inkGhost, size: 11)),
            ],
          ),
          const SizedBox(height: 18),
          _section(
            'WHAT HAPPENED',
            '${brief.yesterdayDate} · ${brief.yesterdayActivity}.',
          ),
          const SizedBox(height: 16),
          _section(
            'WHERE WE LEFT OFF',
            '${brief.yesterdayResponse} ${brief.yesterdayAccuracy}.',
          ),
          const SizedBox(height: 16),
          _section(
            "TODAY'S MOVE",
            brief.todayActivity,
            tinted: true,
          ),
        ],
      ),
    );
  }

  Widget _section(String label, String body, {bool tinted = false}) {
    return Container(
      padding: tinted
          ? const EdgeInsets.fromLTRB(12, 10, 12, 12)
          : EdgeInsets.zero,
      decoration: tinted
          ? BoxDecoration(
              color:        _tealSoft.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(8),
              border:       Border.all(color: _tealSoft),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: _eyebrow(color: tinted ? _teal : _inkGhost)),
          const SizedBox(height: 6),
          Text(body, style: _body(size: 13.5, height: 1.55)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
//                  VARIANT C — CONTINUUM
//   Two-column yesterday → today flow with connecting hairline.
// ─────────────────────────────────────────────────────────────────────────
class TodayBriefVariantC extends StatelessWidget {
  final BriefCase brief;
  const TodayBriefVariantC({super.key, required this.brief});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color:        _paper,
        borderRadius: BorderRadius.circular(14),
        border:       Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${brief.clientName} · ${brief.todayTime}',
              style: _italicHead(size: 18)),
          const SizedBox(height: 14),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _capsule(
                  eyebrow: 'YESTERDAY · ${brief.yesterdayDate.toUpperCase()}',
                  body: '${brief.yesterdayActivity}. ${brief.yesterdayAccuracy}.',
                  detail: brief.yesterdayResponse,
                  tone: _amberSoft,
                  ink: _amber,
                )),
                _arrow(),
                Expanded(child: _capsule(
                  eyebrow: 'TODAY',
                  body: brief.todayActivity,
                  detail: 'Same goal — continuing.',
                  tone: _tealSoft,
                  ink: _teal,
                )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _capsule({
    required String eyebrow,
    required String body,
    required String detail,
    required Color  tone,
    required Color  ink,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color:        tone.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
        border:       Border.all(color: tone),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(eyebrow, style: _eyebrow(color: ink, size: 9.5)),
          const SizedBox(height: 8),
          Text(body, style: _body(size: 13, height: 1.5)),
          const SizedBox(height: 8),
          Text(detail,
              style: _body(color: _inkGhost, size: 12, height: 1.5)
                  .copyWith(fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }

  Widget _arrow() => Container(
        width: 28,
        alignment: Alignment.center,
        child: Icon(Icons.arrow_forward_rounded,
            size: 18, color: _inkGhost.withValues(alpha: 0.7)),
      );
}

// ─────────────────────────────────────────────────────────────────────────
//                  VARIANT D — QUESTION-DRIVEN
//   Each block opens with a clinical question in Playfair italic.
// ─────────────────────────────────────────────────────────────────────────
class TodayBriefVariantD extends StatelessWidget {
  final BriefCase brief;
  const TodayBriefVariantD({super.key, required this.brief});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      decoration: BoxDecoration(
        color:        _paper,
        borderRadius: BorderRadius.circular(14),
        border:       Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(brief.clientName.toUpperCase(),
              style: _eyebrow(color: _ink, size: 11)),
          const SizedBox(height: 4),
          Text('${brief.todayTime} · age ${brief.clientAge}',
              style: _body(color: _inkGhost, size: 12)),
          const SizedBox(height: 24),
          _qa(
            question: 'What worked with ${brief.clientName} yesterday?',
            answer:
                "${brief.yesterdayResponse} Accuracy ${brief.yesterdayAccuracy}, during ${_lower(brief.yesterdayActivity)}.",
          ),
          const SizedBox(height: 22),
          _qa(
            question: "What's the next move?",
            answer: brief.todayActivity,
            answerTinted: true,
          ),
        ],
      ),
    );
  }

  Widget _qa({
    required String question,
    required String answer,
    bool answerTinted = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(question, style: _italicHead(size: 18, color: _amber)),
        const SizedBox(height: 8),
        Container(
          padding: answerTinted
              ? const EdgeInsets.fromLTRB(12, 10, 12, 12)
              : EdgeInsets.zero,
          decoration: answerTinted
              ? BoxDecoration(
                  color:        _amberSoft.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8),
                )
              : null,
          child: Text(answer, style: _body(size: 14, height: 1.6)),
        ),
      ],
    );
  }

  String _lower(String s) =>
      s.isEmpty ? s : '${s[0].toLowerCase()}${s.substring(1)}';
}

// ─────────────────────────────────────────────────────────────────────────
//                  VARIANT E — COMPACT STACK
//   Information-dense, tight rows. Spreadsheet-row tight, well-typed.
// ─────────────────────────────────────────────────────────────────────────
class TodayBriefVariantE extends StatelessWidget {
  final BriefCase brief;
  const TodayBriefVariantE({super.key, required this.brief});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      decoration: BoxDecoration(
        color:        Colors.white,
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline:       TextBaseline.alphabetic,
            children: [
              Text(brief.clientName,
                  style: GoogleFonts.dmSans(
                      fontSize:   16,
                      fontWeight: FontWeight.w600,
                      color:      _ink,
                      height:     1.2)),
              const SizedBox(width: 8),
              Text('${brief.todayTime}  ·  age ${brief.clientAge}',
                  style: _body(color: _inkGhost, size: 12)),
            ],
          ),
          const SizedBox(height: 10),
          _hairline(),
          const SizedBox(height: 10),
          _row(label: 'STG',     value: _shortStg(brief.todayStg)),
          const SizedBox(height: 6),
          _row(label: 'PREV',    value: brief.yesterdayAccuracy,
               valueTone: _amber),
          const SizedBox(height: 6),
          _row(label: 'NOTE',    value: _firstSentence(brief.yesterdayResponse)),
          const SizedBox(height: 6),
          _row(label: 'TODAY',   value: brief.todayActivity,
               valueTone: _teal, valueWeight: FontWeight.w500),
        ],
      ),
    );
  }

  Widget _row({
    required String label,
    required String value,
    Color valueTone = _ink,
    FontWeight valueWeight = FontWeight.w400,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 48,
          child: Text(label, style: _eyebrow(color: _inkGhost, size: 9.5)),
        ),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.dmSans(
              fontSize:   13,
              color:      valueTone,
              height:     1.45,
              fontWeight: valueWeight,
            ),
          ),
        ),
      ],
    );
  }

  String _shortStg(String s) => s.length > 80 ? '${s.substring(0, 77)}…' : s;
  String _firstSentence(String s) {
    final i = s.indexOf(';');
    return i > 0 ? s.substring(0, i) : s;
  }
}
