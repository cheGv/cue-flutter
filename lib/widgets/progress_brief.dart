// lib/widgets/progress_brief.dart
//
// ProgressBrief — slot-driven READ surface for the universal brief shape
// (currently produced by assemble_cas_progress_brief; the widget carries
// NO disorder vocabulary — every clinical string it renders comes from
// the assembled jsonb verbatim: level labels, accuracy words, cue words).
//
// The five slots and their universal labels (the only strings that live
// here):
//   1. "where <name> is"                     ← where_he_is (first name —
//      the headline is the one place the name appears)
//   2. "how it's been moving ▸"              ← trend (verbatim dials).
//      COLLAPSED by default; tap to expand. session_dates render as a
//      ghost row inside the expanded detail only — dates never sit on
//      the fast read.
//   3. "where <pronoun> is strong"           ← best_so_far
//   4. "where you could go next — your call" ← next_move
//   5. "what helps <pronoun-object>"         ← empty-but-inviting; no
//      capture field feeds it yet, nothing is fabricated
//
// Pronouns: sourced from clients.pronoun (self-declared pair, e.g.
// 'he/him'; added 2026-07-05, sandbox). NEVER derived from
// clients.gender. Null/malformed → first name — never guess.
//
// Doctrine bindings:
//   • Fork, never recommendation — next_move options render in JSON
//     order, identical style, no visual ranking (equal-weight register,
//     same law as CueEvidenceDistribution's never-rank).
//   • Real clinical values verbatim — accurate/partial, minimal/maximal.
//     No translation layer. Warmth lives in the slot labels, precision
//     in the data.
//   • Light register — kin to AddSessionScreen's stripe sections
//     (kCuePaper fill, olive left stripe, eyebrow-then-content, no card
//     box). Borrows TodayBriefCard's labeled-row vocabulary
//     (clinicalLabel olive + dataMono dials) inside that register.
//   • Edge states: 1-session window = frontier with no floor (valid);
//     empty history = invitation, not failure; loading = skeleton bars
//     matching the STG card's.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../repositories/cas_session_progress_repository.dart';
import '../theme/cue_phase4_tokens.dart';
import '../theme/cue_type_v3.dart';

class ProgressBrief extends StatefulWidget {
  final String stgId;
  final String clientId;
  final String clientName;

  const ProgressBrief({
    super.key,
    required this.stgId,
    required this.clientId,
    required this.clientName,
  });

  @override
  State<ProgressBrief> createState() => _ProgressBriefState();
}

enum _Phase { loading, loaded, empty, error }

class _ProgressBriefState extends State<ProgressBrief> {
  final _repo = CasSessionProgressRepository();

  _Phase _phase = _Phase.loading;
  Map<String, dynamic> _brief = const {};
  bool _trendExpanded = false;

  // Parsed from clients.pronoun ('he/him' → subject 'he', object 'him').
  // Both stay null when the field is null or malformed — the labels then
  // fall back to the first name. Never derived from gender.
  String? _pronounSubject;
  String? _pronounObject;

  String get _firstName =>
      widget.clientName.trim().split(RegExp(r'\s+')).first;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Pronoun read is tolerant and independent: any failure (missing
    // column, no row) leaves the name fallback in place without touching
    // the brief's own phase.
    try {
      final row = await Supabase.instance.client
          .from('clients')
          .select('pronoun')
          .eq('id', widget.clientId)
          .maybeSingle();
      final raw = (row?['pronoun'] as String?)?.trim().toLowerCase();
      if (raw != null && raw.isNotEmpty) {
        final parts = raw.split('/');
        if (parts.length >= 2 &&
            parts[0].trim().isNotEmpty &&
            parts[1].trim().isNotEmpty) {
          _pronounSubject = parts[0].trim();
          _pronounObject  = parts[1].trim();
        }
      }
    } catch (_) {
      // name fallback
    }

    try {
      final brief = await _repo.callProgressBrief(widget.stgId);
      if (!mounted) return;
      final n = (brief['window_sessions'] as num?)?.toInt() ?? 0;
      setState(() {
        _brief = brief;
        _phase = n == 0 ? _Phase.empty : _Phase.loaded;
      });
    } catch (_) {
      if (mounted) setState(() => _phase = _Phase.error);
    }
  }

  /// Slot-3 label. 'they' takes the contraction so the verb agrees
  /// ("they're", not "they is"); unknown subject pronouns keep the
  /// `subject is` frame; null → first name.
  String get _strongLabel {
    final s = _pronounSubject;
    if (s == null) return 'where $_firstName is strong';
    if (s == 'they') return "where they're strong";
    return 'where $s is strong';
  }

  /// Slot-5 label. Object form when declared, else first name.
  String get _helpsLabel {
    final o = _pronounObject;
    return o == null ? 'what helps $_firstName' : 'what helps $o';
  }

  // ── JSON accessors (tolerant — every block may be null) ────────────────

  Map<String, dynamic>? _block(String key) {
    final v = _brief[key];
    return v is Map ? Map<String, dynamic>.from(v) : null;
  }

  List<Map<String, dynamic>> get _trend {
    final v = _brief['trend'];
    if (v is! List) return const [];
    return v
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: kCuePaper,
        border: Border(
            left: BorderSide(color: kCueOlive, width: 1.5)),
      ),
      padding: const EdgeInsets.only(left: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _eyebrow('where things stand'),
          const SizedBox(height: 8),
          ..._content(),
        ],
      ),
    );
  }

  List<Widget> _content() {
    switch (_phase) {
      case _Phase.loading:
        return [
          _skeletonBar(220),
          const SizedBox(height: 8),
          _skeletonBar(150),
        ];

      case _Phase.error:
        return [
          Text('Progress brief unavailable — check connection.',
              style: CueTypeV3.body(color: kCueSubtitleInk)),
        ];

      case _Phase.empty:
        return [
          Text(
            'No sessions on this goal yet — the picture starts '
            'with the first one.',
            style: CueTypeV3.body(color: kCueSubtitleInk)
                .copyWith(fontStyle: FontStyle.italic),
          ),
        ];

      case _Phase.loaded:
        return [
          ..._whereTheyAreSlot(),
          ..._trendSlot(),
          ..._bestSoFarSlot(),
          ..._nextMoveSlot(),
          ..._whatHelpsSlot(),
        ];
    }
  }

  // ── Slot 1: where <name> is ─────────────────────────────────────────────

  List<Widget> _whereTheyAreSlot() {
    final w = _block('where_he_is');
    if (w == null) return const [];

    final frLabel = w['frontier_label'] as String?;
    final frAcc   = w['frontier_accuracy'] as String?;
    final frCue   = w['frontier_cue'] as String?;
    final frState = w['frontier_state'] as String?;
    final flLabel = w['floor_label'] as String?;
    final flCue   = w['floor_cue'] as String?;
    final holding = w['floor_holding'] as bool?;
    final accN    = (w['floor_accurate_count'] as num?)?.toInt();
    final winN    = (_brief['window_sessions'] as num?)?.toInt();

    final lines = <Widget>[];

    if (frLabel != null) {
      lines.add(_dataLine(
        lead: frState == 'breakthrough'
            ? '$frLabel — just broke through: '
            : '$frLabel — ',
        data: _joinDial(frAcc, frCue),
      ));
    }
    if (flLabel != null) {
      final held = (holding == true) ? ', holding' : '';
      final count = (accN != null && winN != null)
          ? ' — accurate in $accN of $winN$held'
          : '';
      lines.add(_dataLine(
        lead: '$flLabel underneath',
        data: '${flCue != null ? ' @ $flCue' : ''}$count',
        dataMuted: true,
      ));
    } else if (frLabel != null) {
      // Valid shape, not an error: nothing has held accurate across the
      // two most recent sessions yet (incl. every 1-session window).
      lines.add(Text(
        'no floor yet — nothing accurate two sessions running',
        style: CueTypeV3.body(color: kCueSubtitleInk),
      ));
    }
    if (lines.isEmpty) return const [];

    return _slot('where $_firstName is', lines);
  }

  // ── Slot 2: how it's been moving (collapsed by default) ─────────────────

  List<Widget> _trendSlot() {
    final levels = _trend;
    if (levels.isEmpty) return const [];

    // Tappable label — the chevron is the whole affordance; no box, no
    // button chrome (light register).
    final header = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _trendExpanded = !_trendExpanded),
      child: Text(
        _trendExpanded
            ? "how it's been moving ▾"
            : "how it's been moving ▸",
        style: CueTypeV3.clinicalLabel(
            emphasis: 'strong', color: kCueOlive),
      ),
    );

    if (!_trendExpanded) {
      return [header, const SizedBox(height: 14)];
    }

    final rows = <Widget>[];

    // Session dates live INSIDE the detail only — ghost row under the
    // label, aligned oldest → newest like the sequences beneath it.
    final dates = _sessionDatesLine();
    if (dates.isNotEmpty) {
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(dates,
            style: CueTypeV3.dataMono(color: kCueEyebrowInk)),
      ));
    }

    for (final level in levels) {
      final label = level['level_label'] as String? ?? '';
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: CueTypeV3.body(color: kCueInk)
                    .copyWith(fontWeight: FontWeight.w500)),
            const SizedBox(height: 2),
            Text(_seq(level['accuracy_seq']),
                style: CueTypeV3.dataMono(color: kCueOlive)),
            Text(_seq(level['cue_seq']),
                style: CueTypeV3.dataMono(color: kCueMutedInk)),
          ],
        ),
      ));
    }

    return [
      header,
      const SizedBox(height: 4),
      ...rows,
      const SizedBox(height: 8),
    ];
  }

  // ── Slot 3: where <name> is strong ──────────────────────────────────────

  List<Widget> _bestSoFarSlot() {
    final b = _block('best_so_far');
    if (b == null) return const [];

    final label = b['level_label'] as String?;
    final acc   = b['accuracy'] as String?;
    final cue   = b['cue_level_used'] as String?;
    final date  = _formatDate(b['session_date'] as String?);

    return _slot(_strongLabel, [
      _dataLine(
        lead: label != null ? '$label — ' : '',
        data: _joinDial(acc, cue),
        trail: date != null ? '  ·  $date' : '',
      ),
    ]);
  }

  // ── Slot 4: where you could go next — your call ─────────────────────────

  List<Widget> _nextMoveSlot() {
    final m = _block('next_move');
    if (m == null) return const [];

    final rawOptions = m['options'];
    final options = rawOptions is List
        ? rawOptions.map((o) => o.toString()).toList()
        : const <String>[];
    final basis = m['basis'] as String?;
    if (options.isEmpty) return const [];

    return _slot('where you could go next — your call', [
      // Equal weight is structural: JSON order, one shared style, no
      // marker, no emphasis difference. The fork is named, never picked.
      for (final option in options)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(option, style: CueTypeV3.body(color: kCueInk)),
        ),
      if (basis != null && basis.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text('from the dials: $basis',
              style: CueTypeV3.clinicalLabel(
                  emphasis: 'light', color: kCueEyebrowInk)),
        ),
    ]);
  }

  // ── Slot 5: what helps <name> ───────────────────────────────────────────

  List<Widget> _whatHelpsSlot() {
    return _slot(_helpsLabel, [
      Text(
        'Nothing captured yet.',
        style: CueTypeV3.body(color: kCueSubtitleInk)
            .copyWith(fontStyle: FontStyle.italic),
      ),
    ]);
  }

  // ── Shared pieces ───────────────────────────────────────────────────────

  List<Widget> _slot(String label, List<Widget> children) => [
        Text(label,
            style: CueTypeV3.clinicalLabel(
                emphasis: 'strong', color: kCueOlive)),
        const SizedBox(height: 4),
        ...children,
        const SizedBox(height: 14),
      ];

  /// One line mixing universal frame words (body ink) with verbatim dial
  /// values (dataMono olive) — the TodayBriefCard inline-data register.
  Widget _dataLine({
    required String lead,
    required String data,
    String trail = '',
    bool dataMuted = false,
  }) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: lead, style: CueTypeV3.body(color: kCueInk)),
          TextSpan(
              text: data,
              style: CueTypeV3.dataMono(
                  color: dataMuted ? kCueMutedInk : kCueOlive)),
          if (trail.isNotEmpty)
            TextSpan(
                text: trail,
                style: CueTypeV3.body(color: kCueSubtitleInk)),
        ],
      ),
    );
  }

  Widget _skeletonBar(double width) => Container(
        width: width,
        height: 14,
        decoration: BoxDecoration(
          color: kCueBorder,
          borderRadius: BorderRadius.circular(3),
        ),
      );

  // Same style as AddSessionScreen's private _eyebrow — replicated here
  // because the helper is screen-private (recon 2026-07-04).
  Widget _eyebrow(String label) => Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: kCueEyebrowInk,
          letterSpacing: kCueEyebrowLetterSpacing(11),
        ),
      );

  /// 'accurate' + 'minimal' → 'accurate @ minimal' — verbatim values,
  /// universal join. Either side may be absent.
  String _joinDial(String? accuracy, String? cue) {
    if (accuracy != null && cue != null) return '$accuracy @ $cue';
    return accuracy ?? cue ?? '—';
  }

  /// Verbatim sequence render: values joined oldest → newest, JSON nulls
  /// (level not recorded that session) shown as '—' to keep alignment.
  String _seq(dynamic seq) {
    if (seq is! List || seq.isEmpty) return '—';
    return seq.map((v) => v?.toString() ?? '—').join(' → ');
  }

  /// session_dates joined oldest → newest in the sequences' own arrow
  /// grammar — '20 Jun → 27 Jun → 3 Jul'. Detail-only (expanded trend).
  String _sessionDatesLine() {
    final v = _brief['session_dates'];
    if (v is! List || v.isEmpty) return '';
    return v.map((d) {
      final parsed = DateTime.tryParse(d?.toString() ?? '');
      if (parsed == null) return d?.toString() ?? '—';
      const months = [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      return '${parsed.day} ${months[parsed.month]}';
    }).join(' → ');
  }

  /// '2026-07-03' → '3 Jul 2026'. Formatting only — never invents a date;
  /// unparseable input passes through verbatim.
  String? _formatDate(String? iso) {
    if (iso == null) return null;
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month]} ${d.year}';
  }
}
